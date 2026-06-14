require 'json'
require_relative 'helpers'
require_relative 'data_model'
require_relative 'wikidata_sparql'

WikidataMatchResult = Struct.new(
  :state,             # :not_found, :ambiguous, :wrong_instance, :partial, :complete
  :item_id,           # "Q123456" or nil
  :item,              # parsed_content Hash or nil
  :instance_type,     # P31 QID or nil
  :missing_mandatory, # Array<String> of property IDs missing from the item
  :note,              # human-readable explanation
  :match_method,      # :sparql_author_first or :search_fallback
  keyword_init: true
)

class WikidataMatcher
  include Helpers

  TITLE_MATCH_THRESHOLD = 0.6

  CORRECT_WORK_TYPES = DataModel.new.work_types.keys.freeze
  EDITION_TYPES      = DataModel.new.edition_types.keys.freeze

  def initialize(author_cache_path: '_data/author_qids.json')
    @author_cache = load_author_cache(author_cache_path)
    @sparql       = WikidataSparql.new
    @data_model   = DataModel.new
  end

  def match(book)
    author_qid = @author_cache[book.authors.first]

    if author_qid
      candidates = sparql_candidates(author_qid, book.title)
      method     = :sparql_author_first
    else
      candidates = search_candidates(book.title)
      method     = :search_fallback
    end

    classify_candidates(candidates, method:)
  end

  private

  def sparql_candidates(author_qid, title)
    results = @sparql.works_by_author(author_qid)
    sleep(1) # SPARQL service courtesy delay

    # Group by QID — a work with multiple P31s appears once per P31 in SPARQL results
    by_qid = results
      .map { |r|
        {
          'id'       => extract_qid(r.dig('work', 'value')),
          'label'    => r.dig('workLabel', 'value'),
          'instance' => extract_qid(r.dig('instance', 'value')),
        }
      }
      .reject { |c| bare_qid_label?(c['label']) }
      .group_by { |c| c['id'] }

    # Deduplicate: for each QID keep the most correct instance type
    by_qid.filter_map { |id, entries|
      best_instance = entries.map { |e| e['instance'] }
                             .min_by { |i| CORRECT_WORK_TYPES.include?(i) ? 0 : 1 }
      candidate = { 'id' => id, 'label' => entries.first['label'], 'instance' => best_instance }
      candidate if title_score(title, candidate['label']) >= TITLE_MATCH_THRESHOLD
    }
  end

  def search_candidates(title)
    short = main_title(title)
    # Search with the main title (no subtitle) for better recall, then score against both
    @sparql.search_entities(short, limit: 10).map { |r|
      best_score = [title_score(title, r['label']), title_score(short, r['label'])].max
      { 'id' => r['id'], 'label' => r['label'], 'instance' => nil, 'score' => best_score }
    }.select { |c| c['score'] >= TITLE_MATCH_THRESHOLD }
  end

  def classify_candidates(candidates, method:)
    # When we have SPARQL instance data, prefer correct work types over deprecated/edition nodes.
    # For search_fallback candidates (instance: nil) we must fetch to know the type.
    work_candidates = candidates.select { |c| CORRECT_WORK_TYPES.include?(c['instance']) }
    best            = work_candidates.any? ? work_candidates : candidates

    case best.count
    when 0
      WikidataMatchResult.new(state: :not_found, match_method: method)
    when 1
      fetch_and_classify(best.first['id'], method:)
    else
      WikidataMatchResult.new(
        state:        :ambiguous,
        match_method: method,
        note:         "#{best.count} candidates: #{best.map { |c| "#{c['id']} (#{c['label']})" }.join(', ')}"
      )
    end
  end

  def fetch_and_classify(item_id, method:)
    response = with_exponential_backoff { wikidata_rest_client.get_item(item_id) }
    unless response.code == 200
      return WikidataMatchResult.new(state: :not_found, match_method: method, note: "HTTP #{response.code}")
    end

    item = response.parsed_content
    p31  = primary_instance_type(item)

    return wrong_instance_result(item, p31, method:) unless CORRECT_WORK_TYPES.include?(p31)

    schema  = @data_model.work_types[p31]
    present = item.fetch("statements", {}).keys
    missing = schema["Mandatory"].keys - present

    WikidataMatchResult.new(
      state:             missing.empty? ? :complete : :partial,
      item_id:           item['id'],
      item:,
      instance_type:     p31,
      missing_mandatory: missing,
      match_method:      method,
      note:              missing.any? ? "missing: #{missing.join(', ')}" : nil
    )
  end

  def wrong_instance_result(item, p31, method:)
    note = case p31
           when "Q571"         then "deprecated P31 Q571 ('book') — flag for manual P31 correction"
           when *EDITION_TYPES then "edition node (#{p31}), not a work node"
           else                     "unrecognised instance type #{p31.inspect}"
           end

    WikidataMatchResult.new(
      state:         :wrong_instance,
      item_id:       item['id'],
      item:,
      instance_type: p31,
      match_method:  method,
      note:
    )
  end

  def primary_instance_type(item)
    Array(item.dig("statements", "P31")).first&.dig("value", "content")
  end

  def bare_qid_label?(label)
    label.nil? || label.match?(/\AQ\d+\z/)
  end

  def extract_qid(uri)
    uri&.split('/')&.last
  end

  # Jaccard similarity on normalised word sets, with a bonus exact-match shortcut.
  # Jaccard (intersection / union) is symmetric so a long query with a subtitle won't
  # unfairly penalise a short candidate, and a short query won't falsely match a superset
  # (e.g. "My Brilliant Friend" vs "My Brilliant Friend, season 2").
  def title_score(query, candidate)
    return 0.0 if candidate.nil? || candidate.empty?

    norm = ->(s) {
      s.downcase
       .gsub(/\b(the|a|an|of|in|for|and|by|from|with)\b/, '')
       .gsub(/[^a-z0-9]/, ' ')
       .split
    }

    q_words = norm.(query)
    c_words = norm.(candidate)
    return 0.0 if q_words.empty? || c_words.empty?
    return 1.0 if q_words.sort == c_words.sort

    intersection = (q_words & c_words).count
    union        = (q_words | c_words).count
    intersection.to_f / union
  end

  def load_author_cache(path)
    return {} unless File.exist?(path)
    JSON.parse(File.read(path))
  end
end
