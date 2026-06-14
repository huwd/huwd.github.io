require_relative 'support/helpers'
require_relative 'support/abs_client'
require_relative 'support/hardcover_client'
require_relative 'support/wikidata_matcher'
require_relative 'support/record_arbitrator'
require_relative 'book_iri_audit'

# Runs the full enrichment pipeline for each book without a valid work_iri and
# writes a structured diff JSON file per book to _data/proposed_changes/.
# Reads only — no Wikidata writes. Review the diffs, then use --write to apply.
#
# Usage:
#   bundle exec ruby scripts/generate_diffs.rb              # all books missing work_iri
#   bundle exec ruby scripts/generate_diffs.rb <title>      # single book by title substring

class DiffGenerator
  include Helpers

  OUTPUT_DIR = "_data/proposed_changes"

  def initialize(filter: nil)
    @filter      = filter
    @abs         = ABSClient.new
    @hardcover   = HardcoverClient.new
    @matcher     = WikidataMatcher.new
    @arbitrator  = RecordArbitrator.new
  end

  def run
    books = BookIriAudit.new.without_work_iri
    books = books.select { |b| b.title.downcase.include?(@filter.downcase) } if @filter

    if books.empty?
      puts @filter ? "No books matching '#{@filter}'" : "No books missing work_iri"
      return
    end

    FileUtils.mkdir_p(OUTPUT_DIR)
    total = books.count
    puts "Generating diffs for #{total} book(s)...\n\n"

    diffs = []

    books.each_with_index do |book, i|
      print "  [#{i + 1}/#{total}] #{book.title}"

      abs_rec  = @abs.find(main_title(book.title), authors: book.authors)
      hc_rec   = @hardcover.find(book.title, authors: book.authors)
      wikidata = @matcher.match(book)

      diff = @arbitrator.arbitrate(book:, abs: abs_rec, hardcover: hc_rec, wikidata:)
      diffs << diff

      puts " → #{diff.action} [#{diff.confidence}]"
      sleep(0.5)  # courtesy delay between books

      write_diff(diff)
    end

    print_summary(diffs)
  end

  private

  def write_diff(diff)
    slug    = File.basename(diff.book_file, ".md")
    outfile = "#{OUTPUT_DIR}/#{slug}.json"
    File.write(outfile, JSON.pretty_generate(diff.to_h))
  end

  def print_summary(diffs)
    puts "\n#{"─" * 70}"
    puts "DIFF GENERATION SUMMARY"
    puts "#{"─" * 70}\n"

    by_action = diffs.group_by(&:action)

    {
      create_work: "Need creating on Wikidata",
      patch_work:  "Patch — fill missing mandatory properties",
      no_op:       "Already complete",
      review:      "Need manual review / disambiguation",
    }.each do |action, label|
      entries = by_action[action] || []
      next if entries.empty?
      puts "\n#{label} (#{entries.count})"
      puts "─" * 50
      entries.each do |d|
        conf  = { high: "●", medium: "◑", low: "○" }[d.confidence]
        flags = d.review_flags.any? ? " ⚠ #{d.review_flags.count} flag(s)" : ""
        puts "  #{conf} #{d.book_title}#{flags}"
        puts "    #{d.item_url || 'no Wikidata item yet'}"
        d.proposed_statements.each { |s| puts "    + #{s.property} #{s.property_label}: #{s.value} (#{s.source})" }
        d.unfillable.each          { |u| puts "    ? #{u[:property]} #{u[:label]}: #{u[:reason]}" }
        d.review_flags.each        { |f| puts "    ⚠ #{f}" }
        puts
      end
    end

    puts "\nDiff files written to #{OUTPUT_DIR}/"
    puts "Review them, then run wikidata_writer.rb --write to apply approved changes."
  end
end

filter = ARGV.first
DiffGenerator.new(filter:).run
