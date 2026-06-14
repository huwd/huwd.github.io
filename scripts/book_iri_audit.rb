require_relative 'support/helpers'

Book = Struct.new(:file, :title, :authors, :work_iri, :edition_iri, keyword_init: true)

class BookIriAudit
  include Helpers

  def initialize
    @books = load_stored_books.map do |file, fm|
      Book.new(
        file: file,
        title: fm["title"] || File.basename(file, ".md"),
        authors: Array(fm["authors"]),
        work_iri: fm["work_iri"],
        edition_iri: fm["edition_iri"]
      )
    end
  end

  def with_work_iri
    @books.select { |b| complete_wikidata_iri?(b.work_iri) }
  end

  def without_work_iri
    @books.reject { |b| complete_wikidata_iri?(b.work_iri) }
  end

  def report
    total = @books.count
    puts "Work IRI audit: #{with_work_iri.count}/#{total} have a valid work IRI, #{without_work_iri.count} do not"

    return if without_work_iri.empty?

    puts "\nMissing work IRI:"
    without_work_iri.each { |b| puts "  #{b.title} (#{b.file})" }
  end
end

BookIriAudit.new.report if __FILE__ == $PROGRAM_NAME
