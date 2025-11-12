require 'json'
require_relative './support/helpers'

class DataReport
  include Helpers

  def initialize
     @scraped_books = load_scraped_books
     @wikidata_works_to_improve = load_wikidata_works_to_improve
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

  def parse_wikidata_works_missing_mandatory_except_edition
    @wikidata_works_to_improve["available"]
      .select { |_qid, v| (v["Missing Mandatory"] - ["P747"]).any? }
  end

  def data_assembler
    @scraped_book_count = @scraped_books.count
    @missing_work_count = books_missing_works.count
    @potential_work_match = books_missing_works.select { |book_key, _v| books_missing_works[book_key]["wikidata_potential_work_iris"]&.any? }
    @potential_work_match_count = @potential_work_match.count
    @missing_work_percentage = ((@missing_work_count.to_f / @scraped_book_count) * 100).round(2)
    @missing_edition_count = books_edition_works.count
    @missing_edition_percentage = ((@missing_edition_count.to_f / @scraped_book_count) * 100).round(2)
    @wikidata_prioritised_todo_list = parse_wikidata_works_missing_mandatory_except_edition
  end

  def report_presenter
    data_assembler
    puts "======================================="
    puts "Total Books: #{@scraped_book_count}"
    puts "Books missing Wikidata work IRIs: #{@missing_work_count} (#{@missing_work_percentage}%)"
    puts "  -> of which with potential matches #{@potential_work_match_count}"
    @potential_work_match.each do |book_key, details|
      puts "    Potential matches for: #{book_key}:"
       details["wikidata_potential_work_iris"].each do |iri|
         puts "       - #{iri}"
       end
    end
    puts "Books missing Wikidata edition IRIs: #{@missing_edition_count} (#{@missing_edition_percentage}%)"
    puts "Next five up to add:"
    books_missing_works.keys.reverse[0..4].each do |book_filename|
      puts "- #{book_filename}"
    end
    puts "======================================="
    puts "Wikidata works needing improvement (missing mandatory properties except edition):"
    puts "Total: #{@wikidata_prioritised_todo_list.count}"
    @wikidata_prioritised_todo_list.each do |qid, details|
      puts "- https://www.wikidata.org/wiki/#{qid} | #{details["labels"]["en"]}: Missing #{details['Missing Mandatory'].join(', ')}"
    end
    puts "======================================="
    puts "List of properties needing attention:"
    puts @wikidata_prioritised_todo_list.flat_map { |k, details| details['Missing Mandatory'] }.uniq
    puts "======================================="
  end
end

DataReport.new.report_presenter