require 'net/http'
require 'uri'
require 'rexml/document'
require 'set'

BookstoreCatalogEntry = Struct.new(:title, :author, :epub_href, keyword_init: true)

# Client for the OPDS catalog at BOOKSTORE_HOST (bookstore). Read-only: search
# and download only, no library management.
class BookstoreClient
  def initialize
    @host = ENV.fetch("BOOKSTORE_HOST")
    @user = ENV.fetch("BOOKSTORE_USER")
    @pass = ENV.fetch("BOOKSTORE_PASSWORD")
  end

  # Fetches the full OPDS catalog (paginated) and returns entries that have
  # an EPUB acquisition link. Titles/authors with blank text are skipped —
  # Bookstore has some catalog rows with empty metadata that would otherwise
  # false-match against any query.
  def full_catalog(max_pages: 20)
    entries = []
    page = 1
    loop do
      res = get("/api/v1/opds/catalog?page=#{page}&size=50")
      doc = REXML::Document.new(res.body)
      page_entries = doc.elements.to_a("feed/entry")
      break if page_entries.empty?

      page_entries.each do |entry|
        title = entry.elements["title"]&.text
        next if title.to_s.strip.empty?

        author = entry.elements["author/name"]&.text
        epub_link = entry.elements.to_a("link").find { |l| l.attributes["type"].to_s.include?("epub") }
        next unless epub_link

        entries << BookstoreCatalogEntry.new(title: title, author: author, epub_href: epub_link.attributes["href"])
      end

      page += 1
      break if page > max_pages
    end
    entries
  end

  # Targeted OPDS search. bookstore's browse pagination and its search index
  # have been observed out of sync (a book present in search absent from the
  # paginated catalog walk) — use this as a fallback when full_catalog misses
  # something, rather than trusting either source alone.
  def search(query)
    res = get("/api/v1/opds/catalog?q=#{URI.encode_www_form_component(query)}")
    doc = REXML::Document.new(res.body)
    doc.elements.to_a("feed/entry").filter_map do |entry|
      title = entry.elements["title"]&.text
      next if title.to_s.strip.empty?

      author = entry.elements["author/name"]&.text
      epub_link = entry.elements.to_a("link").find { |l| l.attributes["type"].to_s.include?("epub") }
      next unless epub_link

      BookstoreCatalogEntry.new(title: title, author: author, epub_href: epub_link.attributes["href"])
    end
  end

  def download(href, to:)
    res = get(href)
    raise "Download failed (#{res.code}) for #{href}" unless res.code == "200"
    File.binwrite(to, res.body)
    res.body.bytesize
  end

  private

  def get(path)
    uri = URI("#{@host}#{path}")
    Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == 'https') do |http|
      req = Net::HTTP::Get.new(uri)
      req.basic_auth(@user, @pass)
      http.request(req)
    end
  end
end

module BookMatcher
  module_function

  def normalize(s)
    s.to_s.downcase.gsub(/&[a-z]+;/, ' ').gsub(/[^a-z0-9]+/, ' ').strip.squeeze(' ')
  end

  # Most "Title: Subtitle" frontmatter splits correctly on the first colon,
  # but some titles are stored as "Author: Title" (seen in ABS-sourced
  # entries where the source platform's marketing title prefixes the
  # author, e.g. "Orwell: The Essays" for what the catalog just lists as
  # "Essays") -- when the pre-colon segment matches a listed author, use
  # the post-colon segment instead, since that's the real title.
  def main_title_key(title, authors = [])
    parts = title.to_s.split(':', 2)
    if parts.size == 2 && Array(authors).any? { |a| normalize(a) == normalize(parts[0]) }
      normalize(parts[1].split('(').first.to_s)
    else
      normalize(title.to_s.split(/[:(]/).first.to_s)
    end
  end

  # Finds the best catalog entry for a book (title + candidate author list).
  # Falls back through: exact main-title match -> word-superset match in
  # either direction, then disambiguates by author overlap only when there
  # are multiple candidates (translated works and multi-author books often
  # have the catalog list a different author than is listed first locally,
  # e.g. a translator credited as primary author).
  def find(catalog, title, authors)
    key_title = main_title_key(title, authors)
    title_words = key_title.split(' ').to_set

    candidates = catalog.select do |e|
      entry_words = normalize(e.title).split(' ').to_set
      main_title_key(e.title) == key_title || entry_words.superset?(title_words) || title_words.superset?(entry_words)
    end

    if candidates.size > 1
      author_words = Array(authors).flat_map { |a| normalize(a).split(' ') }.to_set
      filtered = candidates.select { |e| normalize(e.author).split(' ').any? { |w| author_words.include?(w) } }
      candidates = filtered unless filtered.empty?
    end

    candidates.first
  end

  # Query string for the OPDS search fallback. bookstore's search does
  # literal/phrase-ish matching, not fuzzy word matching — a long subtitle
  # or a leading "The"/"A" article can cause an otherwise-present book to
  # return zero results, so strip both before searching.
  def search_query(title, authors = [])
    main_title_key(title, authors).split(' ').drop_while { |w| %w[the a an].include?(w) }.join(' ')
  end
end
