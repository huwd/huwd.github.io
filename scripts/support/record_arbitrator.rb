require 'json'
require 'set'
require_relative 'helpers'
require_relative 'data_model'

# Structs that form the structured diff output.
# All are JSON-serialisable via to_h / to_json.

ProposedStatement = Struct.new(
  :property,        # "P577"
  :property_label,  # "publication date"
  :value,           # raw value: String QID, Hash {text:, language:}, ISO date string, etc.
  :value_type,      # :qid | :qid_list | :time | :monolingual_text | :string
  :source,          # :frontmatter | :abs | :hardcover | :author_cache | :inferred
  :confidence,      # :high | :medium | :low
  :note,
  keyword_init: true
) do
  def to_h = super.merge(value_type: value_type.to_s, source: source.to_s, confidence: confidence.to_s)
end

Conflict = Struct.new(
  :property,
  :property_label,
  :our_value,
  :our_source,
  :wikidata_value,
  :note,
  keyword_init: true
) do
  def to_h = super.merge(our_source: our_source.to_s)
end

Prerequisite = Struct.new(
  :type,    # :author_node | :edition_node | :publisher_node
  :name,
  :qid,     # nil when not yet on Wikidata
  :status,  # :found | :needs_creation | :unresolvable
  keyword_init: true
) do
  def to_h = super.merge(type: type.to_s, status: status.to_s)
end

ChangeDiff = Struct.new(
  :book_file,
  :book_title,
  :book_authors,
  :action,               # :create_work | :patch_work | :no_op | :review
  :wikidata_state,
  :item_id,
  :item_url,
  :proposed_statements,  # Array<ProposedStatement> — additive, safe to POST
  :unfillable,           # Array<{property:, label:, reason:}> — missing but no source
  :conflicts,            # Array<Conflict> — our data differs from existing Wikidata value
  :prerequisites,        # Array<Prerequisite>
  :confidence,           # :high | :medium | :low (overall write confidence)
  :review_flags,         # Array<String>
  :sources_used,         # Array<Symbol>
  keyword_init: true
) do
  def to_h
    super.merge(
      action:          action.to_s,
      wikidata_state:  wikidata_state.to_s,
      confidence:      confidence.to_s,
      sources_used:    sources_used.map(&:to_s),
      proposed_statements: proposed_statements.map(&:to_h),
      conflicts:           conflicts.map(&:to_h),
      prerequisites:       prerequisites.map(&:to_h),
    )
  end

  def to_json(...) = to_h.to_json(...)

  # Compact context for an AI model — strip internals, keep decision-relevant facts.
  def ai_context
    {
      title:          book_title,
      authors:        book_authors,
      action:         action.to_s,
      wikidata_state: wikidata_state.to_s,
      item_url:       item_url,
      confidence:     confidence.to_s,
      proposed: proposed_statements.map { |s|
        { property: s.property, label: s.property_label,
          value: s.value, source: s.source.to_s, confidence: s.confidence.to_s }
      },
      unfillable: unfillable,
      conflicts: conflicts.map { |c|
        { property: c.property, label: c.property_label,
          our_value: c.our_value, wikidata_value: c.wikidata_value }
      },
      prerequisites: prerequisites.map { |p|
        { type: p.type.to_s, name: p.name, qid: p.qid, status: p.status.to_s }
      },
      flags: review_flags,
    }
  end
end

class RecordArbitrator
  include Helpers

  PROPERTY_LABELS = {
    "P31"   => "instance of",
    "P1476" => "title",
    "P50"   => "author",
    "P407"  => "language",
    "P577"  => "publication date",
    "P747"  => "has edition or translation",
    "P1680" => "subtitle",
    "P136"  => "genre",
    "P629"  => "edition or translation of",
    "P291"  => "place of publication",
    "P123"  => "publisher",
  }.freeze

  DEFAULT_WORK_TYPE = "Q47461344"  # written work — safest generic type
  ENGLISH_QID       = "Q1860"

  def initialize(author_cache_path: "_data/author_qids.json")
    @author_cache = load_json_cache(author_cache_path)
    @data_model   = DataModel.new
  end

  def arbitrate(book:, abs:, hardcover:, wikidata:)
    action           = determine_action(wikidata)
    prereqs          = resolve_prerequisites(book, action)
    proposed, unfill = build_proposed(book, abs, hardcover, wikidata, action)
    conflicts        = find_conflicts(proposed, wikidata)
    confidence       = compute_confidence(action, proposed, prereqs, conflicts)
    flags            = build_flags(wikidata, prereqs, conflicts, proposed)

    ChangeDiff.new(
      book_file:           book.file,
      book_title:          book.title,
      book_authors:        book.authors,
      action:,
      wikidata_state:      wikidata.state,
      item_id:             wikidata.item_id,
      item_url:            wikidata.item_id ? "https://www.wikidata.org/wiki/#{wikidata.item_id}" : nil,
      proposed_statements: proposed,
      unfillable:          unfill,
      conflicts:,
      prerequisites:       prereqs,
      confidence:,
      review_flags:        flags,
      sources_used:        active_sources(abs, hardcover)
    )
  end

  private

  def determine_action(wikidata)
    case wikidata.state
    when :complete       then :no_op
    when :partial        then :patch_work
    when :not_found      then :create_work
    when :ambiguous      then :review
    when :wrong_instance then :review
    else                      :review
    end
  end

  def resolve_prerequisites(book, action)
    prereqs = book.authors.map { |name|
      qid = @author_cache[name]
      Prerequisite.new(
        type:   :author_node,
        name:   name,
        qid:,
        status: qid ? :found : :unresolved
      )
    }

    # Edition will need creating regardless — flag it so the reviewer knows P747 is pending.
    if %i[patch_work create_work].include?(action)
      prereqs << Prerequisite.new(
        type:   :edition_node,
        name:   "edition of #{book.title}",
        qid:    nil,
        status: :needs_creation
      )
    end

    prereqs
  end

  def build_proposed(book, abs, hardcover, wikidata, action)
    proposed   = []
    unfillable = []
    existing   = wikidata.item&.fetch("statements", {})&.keys&.to_set || Set.new

    target_props = case action
                   when :create_work
                     @data_model.work_types[DEFAULT_WORK_TYPE]["Mandatory"].keys
                   when :patch_work
                     Array(wikidata.missing_mandatory)
                   else
                     []
                   end

    target_props.each do |prop|
      next if existing.include?(prop)

      stmts = source_for(prop, book, abs, hardcover)
      if stmts.any?
        proposed.concat(stmts)
      else
        unfillable << { property: prop, label: PROPERTY_LABELS[prop] || prop, reason: "no source available" }
      end
    end

    [proposed, unfillable]
  end

  # Returns an array of ProposedStatements for a property (usually one, but P50 can be several).
  def source_for(prop, book, abs, hardcover)
    case prop
    when "P31"
      [ProposedStatement.new(
        property: "P31", property_label: "instance of",
        value: DEFAULT_WORK_TYPE, value_type: :qid,
        source: :inferred, confidence: :medium,
        note: "default 'written work' — set more specific type if known (e.g. Q20540385 non-fiction, Q8261 novel)"
      )]

    when "P1476"
      [ProposedStatement.new(
        property: "P1476", property_label: "title",
        value: { text: book.title, language: "en" }, value_type: :monolingual_text,
        source: :frontmatter, confidence: :high
      )]

    when "P50"
      book.authors.filter_map { |name|
        qid = @author_cache[name]
        next unless qid
        ProposedStatement.new(
          property: "P50", property_label: "author",
          value: qid, value_type: :qid,
          source: :author_cache, confidence: :high,
          note: name
        )
      }

    when "P407"
      [ProposedStatement.new(
        property: "P407", property_label: "language",
        value: ENGLISH_QID, value_type: :qid,
        source: :inferred, confidence: :high,
        note: "assumed English — verify if different"
      )]

    when "P577"
      date, source, confidence = best_date(abs, hardcover)
      return [] unless date
      [ProposedStatement.new(
        property: "P577", property_label: "publication date",
        value: date, value_type: :time,
        source:, confidence:
      )]

    when "P747"
      []  # can't fill until edition node exists

    else
      []
    end
  end

  def best_date(abs, hardcover)
    # P577 on a work item should be the work's original publication date — Hardcover's
    # work-level release_date is the only source that actually represents that. Edition
    # (and ABS, which is edition-only) dates reflect the specific consumed edition and
    # can differ substantially from the work's first publication (e.g. a 2026 audiobook
    # of a 1975 book) — only used as a fallback, flagged for manual verification.
    if (d = hardcover&.work&.release_date)
      return [d, :hardcover_work, :high]
    end
    if (d = hardcover&.edition&.release_date)
      return [d, :hardcover, :medium]
    end
    # ABS: publishedYear field may be a full date or year-only (we parse it to Date in ABSClient).
    # Always edition-level (ABS only knows about the specific audiobook) — never :high.
    if (d = abs&.published_date)
      return [d.to_s, :abs, :medium]
    end
    nil
  end

  def find_conflicts(proposed, wikidata)
    return [] unless wikidata.item
    existing = wikidata.item.fetch("statements", {})

    proposed.filter_map { |stmt|
      next unless existing.key?(stmt.property)
      existing_val = existing[stmt.property]&.first&.dig("value", "content")
      next if existing_val.nil? || existing_val == stmt.value

      Conflict.new(
        property:       stmt.property,
        property_label: stmt.property_label,
        our_value:      stmt.value,
        our_source:     stmt.source,
        wikidata_value: existing_val,
        note:           "Wikidata holds a different value — do not overwrite without manual review"
      )
    }
  end

  def compute_confidence(action, proposed, prereqs, conflicts)
    return :low if conflicts.any?

    unresolved_authors = prereqs.count { |p| p.type == :author_node && p.status == :needs_creation }

    # Creating a work with an unresolved author is low confidence — we'd be writing P50 without a QID
    return :low    if action == :create_work && prereqs.any? { |p| p.type == :author_node && p.status == :needs_creation }
    return :medium if unresolved_authors > 0
    return :medium if proposed.any? { |s| s.confidence == :medium }

    proposed.empty? ? :low : :high
  end

  def build_flags(wikidata, prereqs, conflicts, proposed = [])
    flags = []

    flags << wikidata.note if wikidata.note

    prereqs.each do |p|
      flags << "Author '#{p.name}' not in author cache — search Wikidata before writing P50" if p.type == :author_node && p.status == :unresolved
      flags << "Author '#{p.name}' confirmed absent from Wikidata — node must be created first" if p.type == :author_node && p.status == :needs_creation
    end

    conflicts.each do |c|
      flags << "Conflict on #{c.property} (#{c.property_label}): our value '#{c.our_value}' differs from Wikidata '#{c.wikidata_value}'"
    end

    flags << "P747 (has edition) requires an edition node to be created first" if wikidata.missing_mandatory&.include?("P747")

    if (p577 = proposed.find { |s| s.property == "P577" }) && p577.source != :hardcover_work
      flags << "P577 date is sourced from the consumed edition (#{p577.source}), not the work's original publication — verify against an external source (e.g. first-edition print date) before writing to the work item"
    end

    flags
  end

  def active_sources(abs, hardcover)
    sources = [:wikidata]
    sources << :abs       if abs
    sources << :hardcover if hardcover
    sources
  end

  def load_json_cache(path)
    return {} unless File.exist?(path)
    JSON.parse(File.read(path))
  end
end
