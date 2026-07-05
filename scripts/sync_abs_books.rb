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

# Finish dates whose entire batch should be skipped — e.g. Audible cleanup
# imports that ABS stamped with a synthetic date rather than the real listen date.
IGNORE_FINISH_DATES = %w[
  2025-03-31
  2025-04-05
].freeze

# ABS item IDs to skip even if marked finished and absent from _books/.
# Use IDs rather than titles so this list doesn't expose reading history in source.
# To find an ID: bundle exec ruby scripts/sync_abs_books.rb --finished --write
# and check the ABS web UI, or use the search endpoint.
IGNORE_IDS = %w[
  941621d6-6406-4619-882c-5647bd1a1000
  80333a8b-29ef-4639-81ee-53d3da0d6e35
  d96b5947-b5cb-4544-ba24-2cfc7b1d4d3e
  04664ff3-fa36-4151-9363-d52b45badad3
  06591b95-84f4-4be1-b74a-a165cae53a89
  08d30cb0-e80a-4a24-b591-099649d1b06d
  d20af765-e9c0-4ef9-bd0b-b89e0ce012fb
  2964a24b-18cc-4590-bd03-6bf9704940b3
  2480c2ed-1542-4751-84d2-8294154c5019
  fb018cd6-7ce5-4cea-b30e-5aab67fff751
  e3b53627-8b30-4c66-a73d-9adf626a87c2
  8ac980e9-1aaa-4c98-8d01-00b40f55028a
  d749ec57-6b09-4b75-a4b6-dd618b095212
  0a6a77e3-913a-43c2-99cb-13e44ee78e44
  846a3ebd-fc69-4b10-8fe6-186cedaffb12
  bdb37a2e-12b8-490f-b3a8-df2e4932d167
  00370f03-8e03-4ab5-bdda-4384ecb01f69
].freeze

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

    finished_items = []
    if @include_finished
      date_str = @cutoff.strftime("%Y-%m-%d")
      puts "Fetching items finished since #{date_str}..."
      finished_items = @abs.finished_since(@cutoff)
    end

    candidates = gather_candidates(existing_norm, finished_items)
    patches    = @include_finished ? gather_patches(existing, finished_items) : []

    if candidates.empty? && patches.empty?
      puts "Nothing to do — all ABS books are already in _books/."
      return
    end

    unless candidates.empty?
      puts "#{candidates.size} stub(s) to create:\n\n"
      candidates.each { |c| process(c) }
      puts "\nRe-run with --write to create the files." unless @write
    end

    unless patches.empty?
      puts "\n#{patches.size} stub(s) to patch with date_finished:\n\n"
      patches.each { |p| apply_patch(p) }
      puts "\nRe-run with --write to apply patches." unless @write
    end
  end

  private

  def gather_candidates(existing_norm, finished_items)
    candidates = []

    puts "Checking in-progress items..."
    @abs.in_progress.each do |item|
      next if existing_norm.include?(normalize_title(item.record.title))
      next if IGNORE_IDS.include?(item.record.abs_id)
      candidates << { kind: :in_progress, item: item }
    end

    if @include_finished
      finished_items.each do |item|
        next if existing_norm.include?(normalize_title(item.record.title))
        next if IGNORE_IDS.include?(item.record.abs_id)
        next if IGNORE_FINISH_DATES.include?(item.finished_at.utc.strftime("%Y-%m-%d"))
        candidates << { kind: :finished, item: item }
      end
    end

    candidates
  end

  def gather_patches(existing, finished_items)
    finished_by_title = finished_items.each_with_object({}) do |item, h|
      h[normalize_title(item.record.title)] = item
    end

    existing.filter_map do |path, fm|
      next if fm["date_finished"]
      next unless fm["date_started"] && fm["title"]

      abs_item = finished_by_title[normalize_title(fm["title"])]
      next unless abs_item

      { path: path, title: fm["title"], item: abs_item }
    end
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

  def apply_patch(patch)
    path         = patch[:path]
    title        = patch[:title]
    item         = patch[:item]
    finished_iso = item.finished_at.utc.strftime("%Y-%m-%dT%H:%M:%SZ")

    puts "  [now finished #{item.finished_at.strftime('%Y-%m-%d')}] #{title}"
    puts "      → #{path}"

    if @write
      content = File.read(path)
      patched = content.sub(/(date_started: (['"]).*?\2\n)/, "\\1date_finished: '#{finished_iso}'\n")
      raise "date_started line not found in #{path} — patch not applied" if patched == content
      File.write(path, patched)
      puts "      patched"
    else
      puts "      [dry run]"
    end
    puts
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
