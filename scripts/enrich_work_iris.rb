require_relative 'support/helpers'
require_relative 'support/wikidata_matcher'
require_relative 'support/frontmatter_updater'
require_relative 'book_iri_audit'

class WorkIriEnricher
  include Helpers

  # States where we have a confident enough QID to write back to frontmatter.
  WRITABLE_STATES = %i[complete partial].freeze

  STATE_LABELS = {
    complete:      "✓ complete",
    partial:       "~ partial",
    wrong_instance:"⚠ wrong instance",
    ambiguous:     "? ambiguous",
    not_found:     "✗ not found",
  }.freeze

  def initialize(dry_run: true)
    @matcher   = WikidataMatcher.new
    @updater   = FrontmatterUpdater.new(dry_run:)
    @dry_run   = dry_run
    @results   = []
    @write_log = []
  end

  def run
    books = BookIriAudit.new.without_work_iri
    total = books.count
    mode  = @dry_run ? "dry run" : "WRITE MODE"

    puts "Matching #{total} books against Wikidata... [#{mode}]\n\n"

    books.each_with_index do |book, i|
      print "  [#{i + 1}/#{total}] #{book.title}..."
      result = @matcher.match(book)
      @results << { book:, result: }
      puts " #{STATE_LABELS[result.state]}"
      sleep(0.2)

      next unless WRITABLE_STATES.include?(result.state) && result.item_id

      outcome = @updater.update_work_iri(book.file, result.item_id)
      @write_log << { book:, result:, outcome: }
    end

    print_report
  end

  private

  def print_report
    puts "\n#{"─" * 70}"
    puts "WIKIDATA WORK IRI ENRICHMENT REPORT"
    puts "#{"─" * 70}\n\n"

    by_state = @results.group_by { |r| r[:result].state }

    print_section(:complete,       "Already complete — work IRI can be written",     by_state)
    print_section(:partial,        "Partial — exists, some mandatory fields missing", by_state)
    print_section(:wrong_instance, "Wrong instance type — needs manual review",       by_state)
    print_section(:ambiguous,      "Ambiguous — multiple candidates found",           by_state)
    print_section(:not_found,      "Not found — may need creating on Wikidata",       by_state)

    print_write_log

    puts "\nSummary"
    puts "─" * 30
    STATE_LABELS.each do |state, label|
      count = by_state[state]&.count || 0
      puts "  #{label.ljust(25)} #{count}" if count > 0
    end
    puts "  #{"Total".ljust(25)} #{@results.count}"
  end

  def print_section(state, heading, by_state)
    entries = by_state[state]
    return unless entries&.any?

    puts "#{heading} (#{entries.count})"
    puts "─" * 70

    entries.each do |r|
      book    = r[:book]
      result  = r[:result]
      authors = book.authors.join(", ")

      puts "  #{book.title}"
      puts "    Author(s): #{authors}"
      puts "    Method:    #{result.match_method}"
      puts "    Item:      https://www.wikidata.org/wiki/#{result.item_id}" if result.item_id
      puts "    P31:       #{result.instance_type}" if result.instance_type
      puts "    Note:      #{result.note}" if result.note
      puts
    end
  end

  def print_write_log
    return if @write_log.empty?

    label = @dry_run ? "Frontmatter updates (dry run — not written)" : "Frontmatter updates written"
    puts "#{label} (#{@write_log.count})"
    puts "─" * 70

    @write_log.each do |entry|
      icon = case entry[:outcome]
             when :updated      then @dry_run ? "→" : "✓"
             when :already_set  then "="
             when :no_match     then "!"
             end
      puts "  #{icon} #{entry[:book].title}"
      puts "      #{entry[:book].file}"
      puts "      work_iri: https://www.wikidata.org/wiki/#{entry[:result].item_id}"
      puts "      (#{entry[:outcome]})"
      puts
    end
  end
end

dry_run = !ARGV.include?("--write")
WorkIriEnricher.new(dry_run:).run
