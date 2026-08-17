require "time"

module Builders
  # Shared queries used by the book_listing layout (book_list_by_year) and
  # the book/review layouts' book-to-book nav - both need "books finished,
  # sorted newest first" and "does this book have a review, and if so
  # where" (checking has_review or being referenced from a multi-book
  # review's books_reviewed list).
  #
  # Date fields (date, date_started, date_finished) are quoted in some
  # content files and bare in others, so YAML parses them as a String in
  # some and a Time in others - sorting or calling Time methods directly
  # on that mix would raise. Time.parse on #to_s handles both uniformly
  # (Time#to_s round-trips fine).
  class ReadingHelpers < SiteBuilder
    def build
      helper "time_for" do |value|
        Time.parse(value.to_s)
      end

      # Ascending (oldest first), matching book_links.html's un-reversed
      # sort - it needs chronological order for prev/next. Reverse this
      # where newest-first display is wanted (e.g. book_list_by_year).
      helper "finished_books" do
        site.collections["books"].resources
          .select { |book| book.data.date_finished }
          .sort_by { |book| Time.parse(book.data.date_finished.to_s) }
      end

      helper "review_link_for" do |book|
        next book.relative_url if book.data.has_review

        review = site.collections["reviews"]&.resources&.find do |r|
          Array(r.data.books_reviewed).include?(book.relative_url)
        end
        review&.relative_url
      end
    end
  end
end
