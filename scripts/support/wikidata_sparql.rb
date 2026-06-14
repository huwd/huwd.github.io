require 'net/http'
require 'json'
require 'uri'

# Handles direct HTTP queries to Wikidata outside the wikidata_adaptor gem:
#   - SPARQL via the Query Service (read-only, no auth)
#   - Entity search via the MediaWiki API (the gem's search targets a v0 endpoint
#     that doesn't exist on the live Wikidata instance)
#
# Designed to port cleanly into wikidata_adaptor as an optional module — no
# project dependencies, pure Net::HTTP, stateless.
class WikidataSparql
  SPARQL_ENDPOINT  = "https://query.wikidata.org/sparql"
  MEDIAWIKI_ENDPOINT = "https://www.wikidata.org/w/api.php"

  # P31 values we recognise as book-related — correct work types, deprecated Q571,
  # and edition types (included so author-first search surfaces everything linked to them).
  BOOK_INSTANCE_QIDS = %w[
    Q47461344 Q7725634 Q35760 Q725377 Q8261
    Q571
    Q3331189 Q122731938 Q1224889
  ].freeze

  def works_by_author(author_qid)
    values = BOOK_INSTANCE_QIDS.map { |q| "wd:#{q}" }.join(" ")

    query(<<~SPARQL)
      SELECT ?work ?workLabel ?instance WHERE {
        ?work wdt:P50 wd:#{author_qid} .
        ?work wdt:P31 ?instance .
        VALUES ?instance { #{values} }
        SERVICE wikibase:label { bd:serviceParam wikibase:language "en". }
      }
    SPARQL
  end

  # Find edition items by ASIN (P5749). Returns raw bindings.
  def edition_by_asin(asin)
    query(<<~SPARQL)
      SELECT ?item ?p31 ?p629 WHERE {
        ?item wdt:P5749 "#{asin}" .
        OPTIONAL { ?item wdt:P31 ?p31 }
        OPTIONAL { ?item wdt:P629 ?p629 }
      } LIMIT 5
    SPARQL
  end

  # Find edition items by ISBN-13 (P212). Returns raw bindings.
  def edition_by_isbn13(isbn13)
    query(<<~SPARQL)
      SELECT ?item ?p31 ?p629 WHERE {
        ?item wdt:P212 "#{isbn13}" .
        OPTIONAL { ?item wdt:P31 ?p31 }
        OPTIONAL { ?item wdt:P629 ?p629 }
      } LIMIT 5
    SPARQL
  end

  # Find edition items linked to a work via P629. Returns raw bindings.
  def editions_of_work(work_qid)
    query(<<~SPARQL)
      SELECT ?item ?p31 WHERE {
        VALUES ?work { wd:#{work_qid} }
        ?item wdt:P629 ?work .
        OPTIONAL { ?item wdt:P31 ?p31 }
      } LIMIT 10
    SPARQL
  end

  # Fetch P31 (instance type) and P407 (language) for a single work item.
  # Returns [p31_qid, p407_qid] — either may be nil.
  def work_type_and_language(work_qid)
    results = query(<<~SPARQL)
      SELECT ?p31 ?p407 WHERE {
        VALUES ?work { wd:#{work_qid} }
        OPTIONAL { ?work wdt:P31 ?p31 }
        OPTIONAL { ?work wdt:P407 ?p407 }
      } LIMIT 1
    SPARQL
    return [nil, nil] if results.empty?
    r = results.first
    [
      r.dig('p31',  'value')&.split('/')&.last,
      r.dig('p407', 'value')&.split('/')&.last
    ]
  end

  # Search Wikidata entities via the MediaWiki wbsearchentities API.
  # Returns Array of { "id", "label", "description", "match" } hashes.
  def search_entities(query, limit: 10, type: "item", language: "en")
    uri = URI(MEDIAWIKI_ENDPOINT)
    uri.query = URI.encode_www_form(
      action: "wbsearchentities",
      search: query,
      language: language,
      type: type,
      format: "json",
      limit: limit
    )

    response = Net::HTTP.start(uri.host, uri.port, use_ssl: true) do |http|
      req = Net::HTTP::Get.new(uri)
      req["Accept"] = "application/json"
      req["User-Agent"] = user_agent
      http.request(req)
    end

    raise "Search error #{response.code}: #{response.body[0, 200]}" unless response.is_a?(Net::HTTPSuccess)

    JSON.parse(response.body)["search"] || []
  end

  TransientError = Class.new(StandardError)

  def query(sparql, retries: 3, backoff: 10)
    uri = URI(SPARQL_ENDPOINT)
    uri.query = URI.encode_www_form(query: sparql, format: "json")

    attempts = 0
    begin
      attempts += 1
      response = Net::HTTP.start(uri.host, uri.port, use_ssl: true, read_timeout: 30) do |http|
        req = Net::HTTP::Get.new(uri)
        req["Accept"] = "application/sparql-results+json"
        req["User-Agent"] = user_agent
        http.request(req)
      end

      raise TransientError, "HTTP #{response.code}" if %w[502 503 429].include?(response.code)
      raise "SPARQL error #{response.code}: #{response.body[0, 200]}" unless response.is_a?(Net::HTTPSuccess)

      JSON.parse(response.body).dig("results", "bindings") || []
    rescue TransientError, Net::ReadTimeout => e
      raise if attempts > retries
      delay = backoff * attempts
      warn "  SPARQL #{e.message} — retry #{attempts}/#{retries} after #{delay}s"
      sleep(delay)
      retry
    end
  end

  private

  def user_agent
    name    = ENV.fetch("APP_NAME",    "book-enrichment")
    version = ENV.fetch("APP_VERSION", "1.0")
    contact = ENV.fetch("APP_CONTACT", "")
    "#{name}/#{version} (#{contact})"
  end
end
