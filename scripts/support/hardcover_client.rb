require 'net/http'
require 'json'
require 'uri'

HardcoverWork = Struct.new(
  :hardcover_id,
  :title,
  :subtitle,
  :slug,
  :release_date,  # String "YYYY-MM-DD" or nil
  :pages,
  :author_names,  # Array<String>
  keyword_init: true
)

HardcoverEdition = Struct.new(
  :hardcover_id,
  :isbn_10,
  :isbn_13,
  :asin,
  :release_date,     # String "YYYY-MM-DD" or nil
  :pages,
  :publisher,        # String or nil
  :language,         # String e.g. "English"
  :reading_format,   # String e.g. "Listened", "Read", "Ebook"
  keyword_init: true
)

HardcoverRecord = Struct.new(
  :user_book_id,
  :edition_id,
  :work,     # HardcoverWork
  :edition,  # HardcoverEdition or nil
  keyword_init: true
)

class HardcoverClient
  GRAPHQL_ENDPOINT = "https://api.hardcover.app/v1/graphql"

  def initialize
    @token = ENV.fetch("HARDCOVER_TOKEN")
  end

  # Find the user's specific read record for a book.
  # Searches Hardcover by title + author, then looks up the user's edition.
  # Returns HardcoverRecord or nil.
  def find(title, authors: [])
    hits = search(title)
    return nil if hits.empty?

    # Filter search results by author overlap when we have author names
    if authors.any?
      norm_query = authors.map { |a| normalize(a) }
      hits = hits.select { |h|
        hit_authors = Array(h["author_names"]).map { |a| normalize(a) }
        (hit_authors & norm_query).any?
      }
      return nil if hits.empty?
    end

    # Pick the hit whose title best matches (Jaccard, normalised)
    best = hits.min_by { |h| -title_score(h["title"].to_s, title) }
    book_id = best["id"].to_i

    lookup_user_book(book_id, book_doc: best)
  end

  private

  SEARCH_QUERY = <<~GQL
    query($q: String!) {
      search(query: $q, query_type: "Book", per_page: 5) {
        results
      }
    }
  GQL

  USER_BOOK_QUERY = <<~GQL
    query($book_id: Int!) {
      user_books(
        where: { book_id: { _eq: $book_id }, status_id: { _eq: 3 } }
        limit: 1
      ) {
        id edition_id
        book {
          id title subtitle slug release_date pages
          cached_contributors
        }
        edition {
          id isbn_10 isbn_13 asin
          release_date pages
          publisher  { name }
          language   { language }
          reading_format { format }
        }
      }
    }
  GQL

  def search(title)
    data = graphql(SEARCH_QUERY, { q: title })
    hits = data.dig("data", "search", "results", "hits") || []
    hits.map { |h| h["document"] }
  end

  def lookup_user_book(book_id, book_doc: nil)
    data     = graphql(USER_BOOK_QUERY, { book_id: })
    ub_list  = data.dig("data", "user_books") || []
    return nil if ub_list.empty?

    ub = ub_list.first
    build_record(ub)
  end

  def build_record(ub)
    b  = ub["book"]
    ed = ub["edition"]

    work = HardcoverWork.new(
      hardcover_id: b["id"],
      title:        b["title"],
      subtitle:     b["subtitle"],
      slug:         b["slug"],
      release_date: b["release_date"],
      pages:        b["pages"],
      author_names: extract_authors(b["cached_contributors"])
    )

    edition = ed && HardcoverEdition.new(
      hardcover_id: ed["id"],
      isbn_10:      ed["isbn_10"],
      isbn_13:      ed["isbn_13"],
      asin:         ed["asin"],
      release_date: ed["release_date"],
      pages:        ed["pages"],
      publisher:    ed.dig("publisher", "name"),
      language:     ed.dig("language", "language"),
      reading_format: ed.dig("reading_format", "format")
    )

    HardcoverRecord.new(
      user_book_id: ub["id"],
      edition_id:   ub["edition_id"],
      work:         work,
      edition:      edition
    )
  end

  # nil contribution = primary author; non-nil = role like "Translator"
  def extract_authors(cached)
    return [] unless cached
    cached
      .select { |c| c["contribution"].nil? }
      .filter_map { |c| c.dig("author", "name") }
  end

  # Jaccard similarity on normalised word sets (same as wikidata_matcher)
  def title_score(a, b)
    return 0.0 if a.empty? || b.empty?
    wa = normalize(a).split
    wb = normalize(b).split
    return 0.0 if wa.empty? || wb.empty?
    ((wa & wb).size.to_f / (wa | wb).size)
  end

  def normalize(s)
    s.to_s.downcase.gsub(/[^a-z0-9 ]/, '').squeeze(' ').strip
  end

  def graphql(query, variables = {})
    uri = URI(GRAPHQL_ENDPOINT)
    res = Net::HTTP.start(uri.host, uri.port, use_ssl: true, read_timeout: 30) do |http|
      req = Net::HTTP::Post.new(uri)
      req["Content-Type"]  = "application/json"
      req["Authorization"] = @token
      req["x-hasura-role"] = "user"
      req.body = { query:, variables: }.to_json
      http.request(req)
    end
    raise "Hardcover HTTP #{res.code}: #{res.body[0, 200]}" unless res.is_a?(Net::HTTPSuccess)
    JSON.parse(res.body)
  end
end
