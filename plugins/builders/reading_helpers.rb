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

      # Same "reviewed book or multi-book review, newest first" query
      # reviews.erb builds inline - pulled out here so the reviews feed
      # (issue #187) can list exactly what the reviews page lists, without
      # the two drifting apart.
      helper "all_reviews" do
        book_reviews = site.collections["books"].resources.select { |book| book.data.has_review }
        multi_reviews = site.collections["reviews"]&.resources || []
        (book_reviews + multi_reviews).sort_by { |post| Time.parse(post.data.date.to_s) }.reverse
      end

      # Same weeknotes query as weeknotes.erb (excluding weeknotes that are
      # themselves a book review), but newest first - the feed should read
      # newest first regardless of what order the listing page happens to
      # display them in.
      helper "all_weeknotes" do
        (site.collections["weeknotes"]&.resources || [])
          .select { |weeknote| Array(weeknote.data.categories).first != "review" }
          .sort_by { |post| Time.parse(post.data.date.to_s) }.reverse
      end

      helper "all_blog_posts" do
        (site.collections["blogs"]&.resources || [])
          .sort_by { |post| Time.parse(post.data.date.to_s) }.reverse
      end
    end
  end
end
