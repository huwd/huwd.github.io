require 'yaml'
require_relative '../../../wikidata_adaptor/lib/wikidata_adaptor'

module Helpers
  class UnknownInstanceType < StandardError; end

  def load_scraped_books
    JSON.parse(File.read('_data/scraped_books.json'))
  end

  def load_stored_books
    Dir.glob("_books/*.md").each_with_object({}) do |file, acc|
      frontmatter = File.read(file)[/\A---\s*\n(.*?)\n---/m, 1]
      acc[file] = YAML.safe_load(frontmatter || "", permitted_classes: [Time], aliases: true) || {}
    end
  end

  def load_wikidata_works_to_improve
    JSON.parse(File.read('_data/wikidata_works_to_improve.json'))
  end

  # Treat only Q followed by digits as complete, e.g. https://www.wikidata.org/wiki/Q55360383
  def complete_wikidata_iri?(iri)
    iri.is_a?(String) && iri.strip.match?(%r{\Ahttps?://(?:www\.)?wikidata\.org/(?:wiki|entity)/Q\d+\z}i)
  end

  def wikidata_rest_client
    WikidataAdaptor.rest_api
  end
end