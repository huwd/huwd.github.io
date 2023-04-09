require 'pry'
require 'json'
require 'httparty'

class Wikidata
  LINKED_DATA_STORE = 'https://huwdiprose.co.uk'.freeze
  WIKIDATA_SPARQL_URL = 'https://query.wikidata.org/sparql'.freeze

  def initialize
    @books = JSON.load File.new("_data/books.json")
  end

  def query_all
    @books.map do |book|
      puts "Querying #{book["title"]}, by #{book["authors"].join(", ")}"
      find_wikidata_iri(book) unless book["wikidata_iri"] || book["wikidata_potential_iris"]
    end
  end

  def sparql_query(book)
    "SELECT DISTINCT ?book ?label ?author_label
      WHERE
      {
        VALUES ?type {wd:Q571 wd:Q7725634}
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
    HTTParty.get(
      "https://query.wikidata.org/sparql?query=#{sparql_query(book)}&format=json",
      headers: { 'User-Agent' => 'Ruby scraping script' }
    )
  end

  def find_wikidata_iri(book)
    puts "> Querying Wikidata for #{book["title"]}"

    response = query_wikidata_books(book)

    return {
      **book,
      wikidata_iri: nil
    } unless response.code == 200

    wikidata_iri = JSON.parse(response)
                      .dig('results', 'bindings')
                      .map { |result| result['book']['value'] }
    return book if wikidata_iri == 0
    if wikidata_iri.count == 1
      puts "> Single IRI found: #{wikidata_iri.first}"
      return {
        **book,
        wikidata_iri: wikidata_iri.first
      }
    else
      puts "> WARNING: #{wikidata_iri.count} Wikidata entries found"
      potentials = wikidata_iri.empty? ? {} : { wikidata_potential_iris: wikidata_iri }

      return {
        **book,
        wikidata_iri: nil,
        **potentials
      }
    end
  end
end

wd = Wikidata.new
data = JSON.pretty_generate(wd.query_all)

File.open('_data/books_test.json', 'w') { |file| file.write(data) }
