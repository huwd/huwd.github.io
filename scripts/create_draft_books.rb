require 'date'
require 'yaml'
require 'fileutils'
require_relative 'support/helpers'
require_relative 'support/abs_client'

class DraftBookCreator
  include Helpers

  BOOKS_DIR = "_books"

  def run(dry_run: true)
    abs       = ABSClient.new
    in_prog   = abs.in_progress
    existing  = load_stored_books

    puts "ABS in-progress items: #{in_prog.size}"
    puts "Existing book files: #{existing.size}\n\n"

    new_items = in_prog.reject { |item| already_exists?(item.record, existing) }

    if new_items.empty?
      puts "All in-progress books already have a draft or review file."
      return
    end

    puts "#{new_items.size} new draft(s) to create:\n\n"

    new_items.each do |item|
      r         = item.record
      started   = item.started_at || item.last_update || Time.now.utc
      slug      = slugify(r.title)
      date_str  = started.strftime("%Y-%m-%d")
      filename  = "#{date_str}-#{slug}.md"
      path      = File.join(BOOKS_DIR, filename)
      pct       = (item.progress * 100).round

      puts "  #{pct}% — #{r.title}"
      puts "      #{r.authors.join(', ')}"
      puts "      → #{path}"
      if dry_run
        puts "      [dry run — not written]"
      else
        File.write(path, build_frontmatter(r, started))
        puts "      ✓ written"
      end
      puts
    end

    if dry_run
      puts "\nRe-run with --write to create files."
    end
  end

  private

  def already_exists?(record, existing)
    norm_title = normalize(record.title)
    existing.any? do |_file, fm|
      normalize(fm['title'].to_s) == norm_title
    end
  end

  def build_frontmatter(record, started)
    started_iso = started.strftime("%Y-%m-%dT%H:%M:%SZ")
    duration    = format_duration(record.duration_seconds)

    fm = {
      "layout"      => "book",
      "title"       => record.title,
      "authors"     => record.authors,
      "work_iri"    => "https://www.wikidata.org/wiki/Q",
      "edition_iri" => "https://www.wikidata.org/wiki/Q",
      "date_started"=> started_iso,
      "categories"  => "book",
      "published"   => false,
      "version"     => "1.0.0",
    }

    fm["series"] = record.series.first if record.series.any?

    unless record.narrators.empty? && record.asin.nil? && duration.nil?
      format_block = {}
      format_block["asin"]      = record.asin        if record.asin
      format_block["narrators"] = record.narrators    unless record.narrators.empty?
      format_block["runtime"]   = duration            if duration
      format_block["publisher"] = { "name" => record.publisher } if record.publisher
      format_block["type"]      = "Audiobook"
      fm["format"] = format_block
    end

    "---\n#{YAML.dump(fm).sub(/\A---\n/, '')}---\n\n"
  end

  def format_duration(seconds)
    return nil unless seconds && seconds > 0
    h = seconds / 3600
    m = (seconds % 3600) / 60
    parts = []
    parts << "#{h} hour#{"s" if h != 1}" if h > 0
    parts << "#{m} minute#{"s" if m != 1}" if m > 0
    parts.join(" and ")
  end

  def slugify(title)
    title.to_s.downcase
         .gsub(/['''ʼ]/, '')
         .gsub(/[^a-z0-9\s-]/, ' ')
         .strip
         .gsub(/\s+/, '-')
         .gsub(/-+/, '-')
         .slice(0, 80)
  end

  def normalize(s)
    s.downcase.gsub(/[^a-z0-9]/, '').strip
  end
end

write = ARGV.include?("--write")
DraftBookCreator.new.run(dry_run: !write)
