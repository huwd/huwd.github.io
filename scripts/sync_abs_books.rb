require 'date'
require 'time'
require 'yaml'
require 'fileutils'
require_relative 'support/helpers'
require_relative 'support/abs_client'

# Syncs Audiobookshelf → _books/ stub files.
#
# Modes (may be combined):
#   (default)                  — in-progress items not yet in _books/
#   --finished                 — also finished items since auto cutoff
#                                (defaults to date of most recent date_finished in _books/)
#   --finished-since YYYY-MM-DD — same but with an explicit cutoff date
#   --write                    — write files (default is dry-run)
#
# Usage:
#   bundle exec ruby scripts/sync_abs_books.rb
#   bundle exec ruby scripts/sync_abs_books.rb --finished
#   bundle exec ruby scripts/sync_abs_books.rb --finished-since 2025-01-01
#   bundle exec ruby scripts/sync_abs_books.rb --finished --write

class AbsBookSync
  include Helpers

  BOOKS_DIR = "_books"

  def initialize(write:, include_finished:, cutoff:)
    @write            = write
    @include_finished = include_finished
    @cutoff           = cutoff
    @abs              = ABSClient.new
  end

  def run
    existing      = load_stored_books
    existing_norm = build_existing_norm(existing)

    candidates = gather_candidates(existing_norm)

    if candidates.empty?
      puts "Nothing to create — all ABS books are already in _books/."
      return
    end

    puts "#{candidates.size} stub(s) to create:\n\n"
    candidates.each { |c| process(c) }
    puts "\nRe-run with --write to create the files." unless @write
  end

  private

  def gather_candidates
    raise ArgumentError, "gather_candidates requires existing_norm arg"
  end

  def gather_candidates(existing_norm)
    candidates = []

    puts "Checking in-progress items..."
    @abs.in_progress.each do |item|
      next if existing_norm.include?(normalize_title(item.record.title))
      candidates << { kind: :in_progress, item: item }
    end

    if @include_finished
      date_str = @cutoff.strftime("%Y-%m-%d")
      puts "Checking items finished since #{date_str}..."
      @abs.finished_since(@cutoff).each do |item|
        next if existing_norm.include?(normalize_title(item.record.title))
        candidates << { kind: :finished, item: item }
      end
    end

    candidates
  end

  def process(candidate)
    kind = candidate[:kind]
    item = candidate[:item]
    r    = item.record

    case kind
    when :in_progress
      started  = item.started_at || item.last_update || Time.now.utc
      date_str = started.strftime("%Y-%m-%d")
      pct      = (item.progress * 100).round
      label    = "#{pct}% in progress"
    when :finished
      started  = item.started_at || item.finished_at
      date_str = started.strftime("%Y-%m-%d")
      label    = "finished #{item.finished_at.strftime('%Y-%m-%d')}"
    end

    slug     = slugify(r.title)
    filename = "#{date_str}-#{slug}.md"
    path     = File.join(BOOKS_DIR, filename)

    puts "  [#{label}] #{r.title}"
    puts "      #{r.authors.join(', ')}"
    puts "      → #{path}"

    if @write
      content = build_frontmatter(r, item)
      File.write(path, content)
      puts "      written"
    else
      puts "      [dry run]"
    end
    puts
  end

  def build_frontmatter(record, item)
    started_iso  = item.started_at&.utc&.strftime("%Y-%m-%dT%H:%M:%SZ")
    finished_iso = item.respond_to?(:finished_at) ? item.finished_at&.utc&.strftime("%Y-%m-%dT%H:%M:%SZ") : nil
    duration     = format_duration(record.duration_seconds)

    fm = {
      "layout"      => "book",
      "title"       => normalize_apostrophes(record.title),
      "authors"     => record.authors,
      "work_iri"    => "https://www.wikidata.org/wiki/Q",
      "edition_iri" => "https://www.wikidata.org/wiki/Q",
      "categories"  => "book",
      "published"   => false,
      "version"     => "1.0.0",
    }

    fm["series"]        = record.series.first if record.series.any?
    fm["date_started"]  = started_iso          if started_iso
    fm["date_finished"] = finished_iso         if finished_iso

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

  def build_existing_norm(existing)
    existing.values.filter_map { |fm| normalize_title(fm["title"]) if fm["title"] }.to_set
  end

  def normalize_title(t)
    t.to_s
     .unicode_normalize(:nfc)
     .gsub(/[''‚‛’]/, "'")
     .gsub(/[""„‟“”]/, '"')
     .sub(/\s*\(Unabridged\)\s*/i, "")
     .sub(/\s*:\s+.*/, "")
     .downcase.strip
  end

  def normalize_apostrophes(t)
    t.to_s
     .unicode_normalize(:nfc)
     .gsub(/[''‚‛’]/, "'")
     .gsub(/[""„‟“”]/, '"')
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
    normalize_apostrophes(title)
      .downcase
      .gsub(/[^a-z0-9\s-]/, ' ')
      .strip
      .gsub(/\s+/, '-')
      .gsub(/-+/, '-')
      .slice(0, 80)
  end
end

# ── Entry point ───────────────────────────────────────────────────────────────

write           = ARGV.delete("--write")
include_finished = ARGV.delete("--finished")
since_arg       = ARGV.index("--finished-since") && ARGV.delete_at(ARGV.index("--finished-since") + 1)
ARGV.delete("--finished-since")

cutoff = if since_arg
           include_finished = true
           Time.parse(since_arg)
         elsif include_finished
           # Default: most recent date_finished in _books/
           dates = Dir.glob("_books/*.md").filter_map do |f|
             fm = File.read(f)[/\A---\s*\n(.*?)\n---/m, 1]
             next unless fm
             data = YAML.safe_load(fm, permitted_classes: [Time, Date], aliases: true) || {}
             d = data["date_finished"]
             next unless d
             d.is_a?(Time) ? d : Time.parse(d.to_s)
           rescue ArgumentError, TypeError
             nil
           end.compact.max
           if dates
             puts "Auto cutoff: #{dates.strftime('%Y-%m-%d')} (most recent date_finished in _books/)\n\n"
             dates
           else
             puts "No date_finished found in _books/ — defaulting to 30 days ago\n\n"
             Time.now - 30 * 24 * 3600
           end
         end

AbsBookSync.new(write: !!write, include_finished: !!include_finished, cutoff: cutoff).run
