require 'pry'
require 'json'
require 'httparty'
require 'cgi'
require 'ostruct'  # needed for OpenStruct fallback
require_relative './support/helpers'

class Wikidata
  include Helpers

  WIKIDATA_SPARQL_URL = 'https://query.wikidata.org/sparql'.freeze
  MAX_CONCURRENT = 5
  RATE_LIMIT_DELAY = 0.5 # seconds between batches (tweakable)
  MAX_RETRIES = 5
  RETRY_BASE_DELAY = 2.0

  def initialize
    @books = load_stored_books
  end

  def query_all
    results = {}
    @books.keys.each_slice(MAX_CONCURRENT) do |batch|
      threads = batch.map do |book_key|
        Thread.new do
          book = @books[book_key]
          if complete_wikidata_iri?(book["work_iri"]) || book["wikidata_potential_work_iris"]
            [book_key, book]
          else
            puts "Querying #{book["title"]}, by #{Array(book["authors"]).join(", ")}"
            [book_key, find_work_iri(book)]
          end
        end
      end
      threads.each do |t|
        key, updated = t.value
        results[key] = updated
      end
      sleep RATE_LIMIT_DELAY
    end
    results
  end

  def sparql_query(book)
    "SELECT DISTINCT ?book ?label ?author_label
      WHERE
      {
        VALUES ?type {wdt:P279 wd:Q47461344}
        ?book wdt:P31 ?type .
        ?book wdt:P1476 ?title FILTER (contains(lcase(?title), lcase('#{book["title"]}'))) .
        ?book rdfs:label ?label FILTER (lang(?label) = 'en')
        ?book wdt:P50 ?author .
        ?author rdfs:label ?author_label FILTER (contains(lcase(?author_label), lcase('#{book["author"]}'))) .
        ?author rdfs:label ?author_label FILTER (lang(?author_label) = 'en')
      }
    "
  end

  def query_wikidata_books(book)
    encoded = CGI.escape(sparql_query(book))
    HTTParty.get(
      "#{WIKIDATA_SPARQL_URL}?query=#{encoded}&format=json",
      headers: {
        'User-Agent' => 'Ruby Wikidata script (contact: wikidata@huwdiprose.co.uk)',
        'Accept-Encoding' => 'gzip,deflate'
      }
    )
  end

  def request_with_retry(book)
    attempt = 0
    begin
      response = query_wikidata_books(book)
      return response if [200].include?(response.code)
      if [429, 503].include?(response.code)
        attempt += 1
        raise "Retryable #{response.code}" if attempt <= MAX_RETRIES
      else
        return response
      end
    rescue => e
      if attempt <= MAX_RETRIES
        sleep (RETRY_BASE_DELAY * (2 ** (attempt - 1))) + rand * 0.25
        retry
      else
        puts "> Giving up after #{attempt} attempts (#{e.message})"
        return OpenStruct.new(code: 599, body: '{"results":{"bindings":[]}}')
      end
    end
  end

  def find_work_iri(book)
    response = request_with_retry(book)

    # Leave work_iri untouched on non-200
    return book unless response.code == 200

    work_iri = JSON.parse(response.body)
                   .dig('results', 'bindings')
                   .map { |result| result['book']['value'] }

    # No results: leave untouched
    return book if work_iri.count == 0

    if work_iri.count == 1
      puts "> Single IRI found: #{work_iri.first}"
      # Overwrite existing work_iri only when we have a confirmed match
      { **book, "work_iri" => work_iri.first }
    else
      puts "> WARNING: #{work_iri.count} Wikidata entries found"
      # Multiple results: keep existing work_iri, add potentials
      { **book, "wikidata_potential_work_iris" => work_iri }
    end
  end
end

wd = Wikidata.new
data = JSON.pretty_generate(wd.query_all)
File.open('_data/scraped_books.json', 'w') { |file| file.write(data) }
