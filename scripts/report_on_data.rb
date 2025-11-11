require 'json'
require_relative './support/helpers'

class DataReport
  include Helpers

  def initialize
     @scraped_books = load_scraped_books
  end

  def books_missing_works
    @books_missing_works ||= @scraped_books.reject do |book_key|
      complete_wikidata_iri?(@scraped_books[book_key]["work_iri"])
    end
  end

  def books_edition_works
    @books_missing_works ||= @scraped_books.reject do |book_key|
      complete_wikidata_iri?(@scraped_books[book_key]["edition_iri"])
    end
  end

  def data_assembler
    @scraped_book_count = @scraped_books.count
    @missing_work_count = books_missing_works.count
    @potential_work_match_count = books_missing_works.keys.count { |book_key| books_missing_works[book_key]["wikidata_potential_work_iris"]&.any? }
    @missing_work_percentage = ((@missing_work_count.to_f / @scraped_book_count) * 100).round(2)
    @missing_edition_count = books_edition_works.count
    @missing_edition_percentage = ((@missing_edition_count.to_f / @scraped_book_count) * 100).round(2)
  end

  def report_presenter
    data_assembler
    puts "======================================="
    puts "Total Books: #{@scraped_book_count}"
    puts "Books missing Wikidata work IRIs: #{@missing_work_count} (#{@missing_work_percentage}%)"
    puts "  -> of which with potential matches #{@potential_work_match_count}"
    puts "Books missing Wikidata edition IRIs: #{@missing_edition_count} (#{@missing_edition_percentage}%)"
    puts "======================================="
  end
end

DataReport.new.report_presenter