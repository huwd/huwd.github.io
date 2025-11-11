require 'json'
require 'yaml'
require_relative './support/helpers'

class UpdateBooks
  include Helpers

  def initialize
     @scraped_books = load_scraped_books        # hash: filepath => data
     @stored_books  = load_stored_books         # hash: filepath => frontmatter
  end

  def process
    summary = diff_and_update_wikidata_iris
    present_results(summary)
  end

  private

  def present_results(summary)
    puts JSON.pretty_generate(summary)
  end

  def diff_and_update_wikidata_iris
    updated_files = []
    new_scraped_books = []

    @scraped_books.each do |filepath, scraped_data|
      unless @stored_books.key?(filepath)
        new_scraped_books << { filepath: filepath, data: scraped_data }
        next
      end

      stored_data = @stored_books[filepath]
      stored_iri  = stored_data["work_iri"]
      scraped_iri = scraped_data["work_iri"]

      next unless complete_wikidata_iri?(scraped_iri) # only act if scraped has a complete IRI

      needs_update =
        stored_iri.nil? ||
        !complete_wikidata_iri?(stored_iri) ||
        (complete_wikidata_iri?(stored_iri) && stored_iri != scraped_iri)

      if needs_update
        stored_data["work_iri"] = scraped_iri
        write_updated_frontmatter(filepath, stored_data)
        updated_files << filepath
      end
    end

    {
      updated_files: updated_files,
      new_scraped_books: new_scraped_books
    }
  end

  def write_updated_frontmatter(filepath, data)
    content = File.read(filepath)
    new_frontmatter = "---\n" + YAML.dump(data).sub(/\A---\s*\n/, '')
    if content.match(/\A---\s*\n.*?\n---/m)
      updated = content.sub(/\A---\s*\n.*?\n---/m, new_frontmatter.strip + "\n---")
    else
      updated = new_frontmatter + "\n" + content
    end
    File.write(filepath, updated)
  end
end

UpdateBooks.new.process