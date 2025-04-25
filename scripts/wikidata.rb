require 'pry'
require 'json'
require 'httparty'

class Wikidata
  LINKED_DATA_STORE = 'https://huwdiprose.co.uk'.freeze
  WIKIDATA_SPARQL_URL = 'https://query.wikidata.org/sparql'.freeze

  def initialize
    @books = Dir.glob("_books/*.md").map do |file|
      frontmatter = File.read(file)[/\A---\s*\n(.*?)\n---/m, 1]
      YAML.safe_load(frontmatter || "", permitted_classes: [Time], aliases: true) || {}
    end
  end

  def query_all
    @books.map do |book|
      puts "Querying #{book["title"]}, by #{book["authors"].join(", ")}"
      find_work_iri(book) unless book["work_iri"] || book["wikidata_potential_iris"]
    end
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
    HTTParty.get(
      "https://query.wikidata.org/sparql?query=#{sparql_query(book)}&format=json",
      headers: { 'User-Agent' => 'Ruby scraping script', 'Accept-Encoding' => 'gzip,deflat' }
    )
  end

  def find_work_iri(book)
    puts "> Querying Wikidata for #{book["title"]}"
    response = query_wikidata_books(book)

    return {
      **book,
      work_iri: nil
    } unless response.code == 200

    work_iri = JSON.parse(response)
                      .dig('results', 'bindings')
                      .map { |result| result['book']['value'] }
    return book if work_iri == 0
    if work_iri.count == 1
      puts "> Single IRI found: #{work_iri.first}"
      return {
        **book,
        work_iri: work_iri.first
      }
    else
      puts "> WARNING: #{work_iri.count} Wikidata entries found"
      potentials = work_iri.empty? ? {} : { wikidata_potential_work_iris: work_iri }

      return {
        **book,
        work_iri: nil,
        **potentials
      }
    end
  end
end

wd = Wikidata.new
data = JSON.pretty_generate(wd.query_all)

File.open('_data/scraped_books.json', 'w') { |file| file.write(data) }
