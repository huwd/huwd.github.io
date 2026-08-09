require 'yaml'
require 'json'
require 'fileutils'
require 'optparse'
require_relative 'support/helpers'
require_relative 'support/bookstore_client'
require_relative 'support/epub_toc'

# Finds books read in a given year with an epub available in the bookstore
# library, downloads them, and extracts the text of any bibliography/notes/
# references back-matter section for later citation-network analysis.
#
# Usage:
#   bundle exec ruby scripts/extract_bibliographies.rb --year 2026
#   bundle exec ruby scripts/extract_bibliographies.rb --year 2026 --only "Against Money"
#
# Output:
#   .tmp/bibliographies/epubs/<slug>.epub       — cached download
#   .tmp/bibliographies/extracted/<slug>.json   — matched sections + raw text
#   .tmp/bibliographies/report.json             — run summary across all books

class BibliographyExtractor
  include Helpers

  OUT_DIR   = ".tmp/bibliographies"
  EPUB_DIR  = "#{OUT_DIR}/epubs"
  TEXT_DIR  = "#{OUT_DIR}/extracted"

  def initialize(year:, only: nil)
    @year    = year
    @only    = only
    @client  = BookstoreClient.new
    FileUtils.mkdir_p(EPUB_DIR)
    FileUtils.mkdir_p(TEXT_DIR)
  end

  def run
    catalog = @client.full_catalog
    puts "Catalog: #{catalog.size} epub-bearing entries"

    targets = books_for_year(@year)
    targets = targets.select { |t| t[:title] == @only } if @only
    puts "Books read in #{@year}: #{targets.size}"

    report = targets.map { |t| process(t, catalog) }

    File.write("#{OUT_DIR}/report.json", JSON.pretty_generate(report))
    summarize(report)
  end

  private

  def books_for_year(year)
    load_stored_books.filter_map do |file, fm|
      ds = fm["date_started"].to_s
      df = fm["date_finished"].to_s
      next unless ds.start_with?(year.to_s) || df.start_with?(year.to_s)

      { file: file, title: fm["title"], authors: Array(fm["authors"]) }
    end.sort_by { |t| t[:file] }
  end

  def process(target, catalog)
    slug = safe_name(target[:title])
    entry = BookMatcher.find(catalog, target[:title], target[:authors])

    if entry.nil?
      # bookstore's browse pagination and search index have been observed out
      # of sync — retry with a targeted search before giving up on a book.
      search_results = @client.search(BookMatcher.search_query(target[:title], target[:authors]))
      entry = BookMatcher.find(search_results, target[:title], target[:authors])
    end

    unless entry
      puts "MISSING   #{target[:title]}"
      return { title: target[:title], status: "not_in_library" }
    end

    epub_path = "#{EPUB_DIR}/#{slug}.epub"
    unless File.exist?(epub_path)
      @client.download(entry.epub_href, to: epub_path)
    end

    toc_data = EpubToc.read_toc(epub_path)
    if toc_data[:matched].empty?
      puts "NO BACK MATTER   #{target[:title]}"
      # Full label list included so a reviewer can sense-check for headings
      # that are plausibly back matter but missed by BACK_MATTER_KEYWORDS
      # (translated/idiosyncratic phrasing, e.g. "A Note on Sources").
      return {
        title: target[:title],
        status: "no_back_matter",
        toc_labels: toc_data[:toc].map(&:label),
        toc_tail: toc_data[:toc].last(40).map(&:label)
      }
    end

    sections = toc_data[:matched].map do |m|
      extracted = EpubToc.extract_section(epub_path, m, toc_data[:toc])
      { label: m.label, exact: extracted[:exact], file: extracted[:file], text: extracted[:text] }
    end

    File.write("#{TEXT_DIR}/#{slug}.json", JSON.pretty_generate(
      title: target[:title], authors: target[:authors], sections: sections
    ))

    approx = sections.count { |s| !s[:exact] }
    flag = approx.positive? ? " (#{approx} approximate boundary)" : ""
    puts "OK   #{target[:title]} -> #{sections.map { |s| s[:label] }.join(', ')}#{flag}"

    { title: target[:title], status: "extracted", sections: sections.map { |s| s[:label] } }
  rescue StandardError => e
    puts "ERROR   #{target[:title]}: #{e.message}"
    { title: target[:title], status: "error", error: e.message }
  end

  def summarize(report)
    by_status = report.group_by { |r| r[:status] }
    puts "\n--- Summary ---"
    by_status.each { |status, rows| puts "#{status}: #{rows.size}" }
  end

  def safe_name(title)
    title.to_s.gsub(/[\/:*?"<>|]/, '-').strip
  end
end

if __FILE__ == $0
  options = { year: Time.now.year }
  OptionParser.new do |opts|
    opts.on("--year YEAR", Integer, "Year books were read (default: current year)") { |v| options[:year] = v }
    opts.on("--only TITLE", "Process a single book by exact title (for testing)") { |v| options[:only] = v }
  end.parse!

  BibliographyExtractor.new(year: options[:year], only: options[:only]).run
end
