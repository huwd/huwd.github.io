require 'yaml'
require 'wikidata_adaptor'

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

  # Executes a block with exponential backoff retry logic for rate limiting
  # @param max_retries [Integer] Maximum number of retry attempts (default: 5)
  # @param base_delay [Float] Initial delay in seconds (default: 1.0)
  # @yield The block to execute with retry logic
  # @return The result of the block execution
  def with_exponential_backoff(max_retries: 5, base_delay: 1.0)
    retries = 0

    begin
      yield
    rescue RestClient::TooManyRequests, ApiAdaptor::HTTPTooManyRequests => e
      if retries < max_retries
        delay = base_delay * (2 ** retries)
        retries += 1
        print "\n⚠️  Rate limited. Retry #{retries}/#{max_retries} after #{delay.round(1)}s..."
        sleep(delay)
        retry
      else
        print "\n❌ Max retries (#{max_retries}) exceeded. Giving up.\n"
        raise
      end
    end
  end
end