require 'json'
require_relative 'support/helpers'

class AuthorCacheSeeder
  include Helpers

  CACHE_PATH = '_data/author_qids.json'

  def initialize
    @books      = load_stored_books
    @cache      = load_existing_cache
    @conflicts  = {}
    @unresolved = []
  end

  def seed
    confirmed = @books.select { |_, fm| complete_wikidata_iri?(fm["work_iri"]) }
    total = confirmed.count

    confirmed.each_with_index do |(file, fm), i|
      print "\rSeeding from confirmed work IRIs: #{i + 1}/#{total}"

      authors = Array(fm["authors"]).compact
      next if authors.empty? || authors.all? { |a| @cache.key?(a) }

      work_qid = fm["work_iri"].split("/").last

      begin
        response = with_exponential_backoff { wikidata_rest_client.get_item(work_qid) }
        next warn "\nSkipping #{work_qid}: HTTP #{response.code}" unless response.code == 200

        p50_qids = extract_p50_qids(response.parsed_content)
        map_authors_to_qids(authors, p50_qids, source: file)
      rescue => e
        warn "\nSkipping #{work_qid}: #{e.message}"
      end

      sleep(0.1)
    end

    save_cache
    print_summary(total)
  end

  private

  def extract_p50_qids(item)
    Array(item.dig("statements", "P50")).filter_map do |s|
      s.dig("value", "content")
    end
  end

  def map_authors_to_qids(authors, p50_qids, source:)
    return if p50_qids.empty?

    if authors.count == 1 && p50_qids.count == 1
      assign(authors.first, p50_qids.first, source:)
      return
    end

    # Multi-author: fetch each P50 item label, then match by name similarity
    p50_labels = p50_qids.each_with_object({}) do |qid, acc|
      label = fetch_label(qid)
      acc[qid] = label if label
      sleep(0.1)
    end

    authors.each do |author|
      qid = best_match(author, p50_labels)
      if qid
        assign(author, qid, source:)
      else
        @unresolved << { author:, source: } unless @unresolved.any? { |u| u[:author] == author }
      end
    end
  end

  def assign(author, qid, source:)
    existing = @cache[author]
    if existing && existing != qid
      @conflicts[author] ||= [existing]
      @conflicts[author] << qid unless @conflicts[author].include?(qid)
    else
      @cache[author] = qid
    end
  end

  def fetch_label(qid)
    response = with_exponential_backoff { wikidata_rest_client.get_item(qid) }
    return nil unless response.code == 200
    response.parsed_content.dig("labels", "en")
  rescue
    nil
  end

  # Normalised exact match first; word-overlap fallback for name variants
  # (handles "J.K. Rowling" vs "J. K. Rowling", initials, accents stripped by downcase).
  def best_match(name, qid_labels)
    norm  = ->(s) { s.downcase.gsub(/[^a-z0-9]/, '') }
    words = ->(s) { norm.(s).scan(/[a-z]{2,}/) }

    norm_name = norm.(name)

    exact = qid_labels.find { |_, label| norm.(label) == norm_name }
    return exact.first if exact

    name_words = words.(name)
    return nil if name_words.empty?

    best_qid, best_overlap = qid_labels
      .map { |qid, label| [qid, (name_words & words.(label)).count] }
      .max_by { |_, overlap| overlap }

    best_overlap.positive? ? best_qid : nil
  end

  def load_existing_cache
    return {} unless File.exist?(CACHE_PATH)
    JSON.parse(File.read(CACHE_PATH))
  end

  def save_cache
    File.write(CACHE_PATH, JSON.pretty_generate(@cache.sort.to_h))
  end

  def print_summary(total)
    puts "\n\nSeeded #{@cache.count} authors from #{total} confirmed books → #{CACHE_PATH}"

    if @conflicts.any?
      puts "\n⚠  #{@conflicts.count} QID conflict(s) — same author name mapped to different QIDs:"
      @conflicts.each { |author, qids| puts "  #{author}: #{qids.join(', ')}" }
    end

    if @unresolved.any?
      puts "\n?  #{@unresolved.count} unresolved — could not match author name to a P50:"
      @unresolved.each { |u| puts "  #{u[:author]}  (#{u[:source]})" }
    end
  end
end

AuthorCacheSeeder.new.seed if __FILE__ == $PROGRAM_NAME
