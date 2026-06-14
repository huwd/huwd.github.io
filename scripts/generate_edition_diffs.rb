require 'json'
require 'fileutils'
require 'date'
require_relative 'support/helpers'
require_relative 'support/abs_client'
require_relative 'support/hardcover_client'
require_relative 'support/edition_matcher'
require_relative 'support/wikidata_sparql'

class EditionDiffGenerator
  include Helpers

  OUTPUT_DIR        = "_data/proposed_edition_changes"
  HARDCOVER_IDS_PATH = "_data/hardcover_ids.json"

  AUDIOBOOK_QID = "Q122731938"
  PRINT_QID     = "Q3331189"
  ENGLISH_QID   = "Q1860"

  # Work P31 values we defer to manual handling (no conventional edition concept).
  DEFERRED_TYPES = {
    "Q1004"     => "comics",
    "Q2442098"  => "comic book",
    "Q21198342" => "manga series",
    "Q7366"     => "song",
    "Q1279564"  => "anthology",
  }.freeze

  def run(title_filter = nil)
    books          = load_stored_books
    narrator_cache = load_cache('_data/narrator_qids.json')
    hardcover_ids  = load_cache(HARDCOVER_IDS_PATH)

    targets = books.select { |file, fm|
      complete_wikidata_iri?(fm['work_iri']) &&
        !complete_wikidata_iri?(fm['edition_iri']) &&
        (title_filter.nil? || fm['title'].to_s.downcase.include?(title_filter.downcase))
    }

    puts "Generating edition diffs for #{targets.size} book(s)...\n\n"
    FileUtils.mkdir_p(OUTPUT_DIR)

    abs     = ABSClient.new
    hc      = HardcoverClient.new
    matcher = EditionMatcher.new
    sparql  = WikidataSparql.new

    results = { create: [], link: [], review: [], no_op: [] }

    targets.each_with_index do |(file, fm), idx|
      title    = fm['title'].to_s
      authors  = Array(fm['authors'])
      work_qid = fm['work_iri'].to_s.split('/').last
      slug     = File.basename(file, '.md')

      print "  [#{idx + 1}/#{targets.size}] #{title} ... "

      # Gate on work type and language — translation chains and deferred types first
      p31, p407 = sparql.work_type_and_language(work_qid)
      sleep(0.5)

      if DEFERRED_TYPES.key?(p31)
        label = DEFERRED_TYPES[p31]
        puts "deferred (#{label})"
        write_diff(slug, review_diff(file, fm, work_qid, "deferred_type: work is #{label} (#{p31})"))
        results[:review] << title
        next
      end

      if p407 && p407 != ENGLISH_QID
        puts "review (translation chain)"
        write_diff(slug, review_diff(file, fm, work_qid, "needs_translation_work: work language is #{p407}, not English (#{ENGLISH_QID})"))
        results[:review] << title
        next
      end

      # Fetch source data
      abs_record = abs.find(main_title(title), authors: authors)
      hc_record  = hc.find(main_title(title),  authors: authors)

      # Capture Hardcover IDs as a side-effect (for future fast querying)
      if hc_record
        hardcover_ids[slug] = {
          'work_id'      => hc_record.work.hardcover_id,
          'work_slug'    => hc_record.work.slug,
          'edition_id'   => hc_record.edition_id,
          'user_book_id' => hc_record.user_book_id,
        }.compact
      end

      # Determine edition type
      date_finished = fm['date_finished']
      is_audiobook  = (abs_record && date_finished) ||
                      hc_record&.edition&.reading_format == "Listened"

      asin   = abs_record&.asin   || hc_record&.edition&.asin
      isbn13 = hc_record&.edition&.isbn_13

      # Search Wikidata for an existing edition
      edition_match = matcher.find(asin: asin, isbn13: isbn13, work_qid: work_qid)

      if edition_match
        puts "link (#{edition_match.match_method})"
        write_diff(slug, link_diff(file, fm, work_qid, edition_match))
        results[:link] << title
      elsif is_audiobook
        puts "create_edition [audiobook]"
        write_diff(slug, create_audiobook_diff(file, fm, work_qid, abs_record, hc_record, narrator_cache))
        results[:create] << title
      elsif isbn13
        puts "create_edition [print]"
        write_diff(slug, create_print_diff(file, fm, work_qid, hc_record))
        results[:create] << title
      else
        puts "review (insufficient data)"
        write_diff(slug, review_diff(file, fm, work_qid, "insufficient_data: no ASIN or ISBN-13 found"))
        results[:review] << title
      end
    end

    save_hardcover_ids(hardcover_ids)
    print_summary(results)
  end

  private

  def create_audiobook_diff(file, fm, work_qid, abs, hc, narrator_cache)
    title        = fm['title'].to_s
    authors      = Array(fm['authors'])
    statements   = []
    unfillable   = []
    prerequisites = []
    review_flags  = []
    sources_used  = []

    statements << stmt('P31',   'qid', AUDIOBOOK_QID)
    statements << stmt('P629',  'qid', work_qid)
    statements << stmt('P1476', 'monolingual_text', { 'text' => title, 'language' => 'en' })
    statements << stmt('P407',  'qid', ENGLISH_QID)

    date_val, precision, date_src = best_date(abs, hc)
    if date_val
      statements   << stmt('P577', 'time', date_val, precision: precision, source: date_src)
      sources_used |= [date_src]
    end

    asin = abs&.asin || hc&.edition&.asin
    if asin
      statements   << stmt('P5749', 'string', asin)
      sources_used |= [asin == abs&.asin ? 'abs' : 'hardcover']
    end

    if abs&.duration_seconds && abs.duration_seconds > 0
      minutes      = (abs.duration_seconds / 60.0).round
      statements   << stmt('P2047', 'quantity', minutes.to_s, unit: 'Q7727')
      sources_used |= ['abs']
    end

    # P123 publisher — note name but defer until publisher QID cache exists
    publisher = abs&.publisher || hc&.edition&.publisher
    if publisher
      unfillable << { 'property' => 'P123', 'label' => 'publisher',
                      'reason' => "no QID — publisher name is '#{publisher}'" }
    end

    # P2438 narrators — use cache, flag unresolved
    narrators = abs&.narrators || []
    narrators.each do |name|
      qid = narrator_cache[name]
      if qid
        statements    << stmt('P2438', 'qid', qid, note: name)
        prerequisites << prereq('narrator_node', name, qid, :found)
        sources_used  |= ['abs']
      else
        prerequisites << prereq('narrator_node', name, nil, :unresolved)
        review_flags  << "Narrator '#{name}' not in narrator cache — search Wikidata before writing P2438"
      end
    end

    confidence = review_flags.any? ? 'low' : (statements.size >= 6 ? 'high' : 'medium')

    {
      'book_file'           => file,
      'book_title'          => title,
      'book_authors'        => authors,
      'work_iri'            => fm['work_iri'],
      'work_qid'            => work_qid,
      'action'              => 'create_edition',
      'edition_type'        => 'audiobook',
      'wikidata_state'      => 'not_found',
      'item_id'             => nil,
      'item_url'            => nil,
      'proposed_statements' => statements,
      'unfillable'          => unfillable,
      'prerequisites'       => prerequisites,
      'confidence'          => confidence,
      'review_flags'        => review_flags,
      'sources_used'        => sources_used.uniq,
    }
  end

  def create_print_diff(file, fm, work_qid, hc)
    title        = fm['title'].to_s
    authors      = Array(fm['authors'])
    ed           = hc&.edition
    statements   = []
    unfillable   = []
    sources_used = ['hardcover']

    statements << stmt('P31',   'qid', PRINT_QID)
    statements << stmt('P629',  'qid', work_qid)
    statements << stmt('P1476', 'monolingual_text', { 'text' => title, 'language' => 'en' })
    statements << stmt('P407',  'qid', ENGLISH_QID)
    statements << stmt('P212',  'string', ed.isbn_13) if ed&.isbn_13
    statements << stmt('P957',  'string', ed.isbn_10) if ed&.isbn_10

    date_val, precision, _src = best_date(nil, hc)
    statements << stmt('P577', 'time', date_val, precision: precision) if date_val

    publisher = ed&.publisher
    if publisher
      unfillable << { 'property' => 'P123', 'label' => 'publisher',
                      'reason' => "no QID — publisher name is '#{publisher}'" }
    end

    # P291 place of publication — required but not available from Hardcover
    unfillable << { 'property' => 'P291', 'label' => 'place of publication',
                    'reason' => 'not available from Hardcover — add manually if known' }

    {
      'book_file'           => file,
      'book_title'          => title,
      'book_authors'        => authors,
      'work_iri'            => fm['work_iri'],
      'work_qid'            => work_qid,
      'action'              => 'create_edition',
      'edition_type'        => 'print',
      'wikidata_state'      => 'not_found',
      'item_id'             => nil,
      'item_url'            => nil,
      'proposed_statements' => statements,
      'unfillable'          => unfillable,
      'prerequisites'       => [],
      'confidence'          => 'medium',
      'review_flags'        => [],
      'sources_used'        => sources_used,
    }
  end

  def link_diff(file, fm, work_qid, match)
    {
      'book_file'           => file,
      'book_title'          => fm['title'].to_s,
      'book_authors'        => Array(fm['authors']),
      'work_iri'            => fm['work_iri'],
      'work_qid'            => work_qid,
      'action'              => 'link_edition',
      'edition_type'        => p31_to_type(match.p31),
      'wikidata_state'      => 'found',
      'item_id'             => match.qid,
      'item_url'            => match.url,
      'match_method'        => match.match_method.to_s,
      'proposed_statements' => [],
      'unfillable'          => [],
      'prerequisites'       => [],
      'confidence'          => 'high',
      'review_flags'        => [],
      'sources_used'        => [],
    }
  end

  def review_diff(file, fm, work_qid, reason)
    {
      'book_file'           => file,
      'book_title'          => fm['title'].to_s,
      'book_authors'        => Array(fm['authors']),
      'work_iri'            => fm['work_iri'],
      'work_qid'            => work_qid,
      'action'              => 'review',
      'edition_type'        => nil,
      'wikidata_state'      => 'review',
      'item_id'             => nil,
      'item_url'            => nil,
      'proposed_statements' => [],
      'unfillable'          => [],
      'prerequisites'       => [],
      'confidence'          => 'low',
      'review_flags'        => [reason],
      'sources_used'        => [],
    }
  end

  def write_diff(slug, diff)
    File.write(File.join(OUTPUT_DIR, "#{slug}.json"), JSON.pretty_generate(diff))
  end

  def save_hardcover_ids(ids)
    return if ids.empty?
    existing = load_cache(HARDCOVER_IDS_PATH)
    merged   = existing.merge(ids)
    File.write(HARDCOVER_IDS_PATH, JSON.pretty_generate(merged.sort.to_h))
    puts "\nHardcover IDs cached for #{ids.size} book(s) → #{HARDCOVER_IDS_PATH}"
  end

  # ── Helpers ─────────────────────────────────────────────────────────────────

  def stmt(property, value_type, value, precision: nil, unit: nil, source: nil, note: nil)
    h = { 'property' => property, 'value_type' => value_type, 'value' => value }
    h['precision'] = precision if precision
    h['unit']      = unit      if unit
    h['source']    = source    if source
    h['note']      = note      if note
    h
  end

  def prereq(type, name, qid, status)
    { 'type' => type, 'name' => name, 'qid' => qid, 'status' => status.to_s }
  end

  def best_date(abs, hc)
    if hc&.edition&.release_date
      val, precision = parse_hc_date(hc.edition.release_date)
      return [val, precision, 'hardcover'] if val
    end
    if hc&.work&.release_date
      val, precision = parse_hc_date(hc.work.release_date)
      return [val, precision, 'hardcover'] if val
    end
    if abs&.published_date
      val, precision = abs_date_to_wikidata(abs.published_date)
      return [val, precision, 'abs'] if val
    end
    [nil, nil, nil]
  end

  # Hardcover gives "YYYY-MM-DD" strings. Cap at month precision — specific day unverified.
  def parse_hc_date(str)
    return [nil, nil] if str.nil? || str.strip.empty?
    parts = str.split('-').map(&:to_i).reject(&:zero?)
    case parts.size
    when 3 then ["+#{parts[0]}-#{format('%02d', parts[1])}-00T00:00:00Z", 10]
    when 2 then ["+#{parts[0]}-#{format('%02d', parts[1])}-00T00:00:00Z", 10]
    when 1 then ["+#{parts[0]}-00-00T00:00:00Z", 9]
    else        [nil, nil]
    end
  rescue StandardError
    [nil, nil]
  end

  # ABS: year-only dates become Date.new(year,1,1) → precision 9; real dates → precision 10.
  def abs_date_to_wikidata(date)
    return [nil, nil] unless date
    if date.month == 1 && date.day == 1
      ["+#{date.year}-00-00T00:00:00Z", 9]
    else
      ["+#{date.year}-#{format('%02d', date.month)}-00T00:00:00Z", 10]
    end
  end

  def p31_to_type(p31)
    { AUDIOBOOK_QID => 'audiobook', PRINT_QID => 'print' }.fetch(p31, 'unknown')
  end

  def load_cache(path)
    return {} unless File.exist?(path)
    JSON.parse(File.read(path))
  end

  def print_summary(results)
    sep = '-' * 50
    puts "\n#{'=' * 70}"
    puts "EDITION DIFF SUMMARY"
    puts "#{'=' * 70}\n"

    unless results[:link].empty?
      puts "\nFound on Wikidata — link only (#{results[:link].size})"
      puts sep
      results[:link].each { |t| puts "  ✓ #{t}" }
    end

    unless results[:create].empty?
      puts "\nNeeds creating on Wikidata (#{results[:create].size})"
      puts sep
      results[:create].each { |t| puts "  ◑ #{t}" }
    end

    unless results[:review].empty?
      puts "\nNeeds manual review (#{results[:review].size})"
      puts sep
      results[:review].each { |t| puts "  ⚠ #{t}" }
    end

    total = results.values.sum(&:size)
    puts "\n#{total} diffs written to #{OUTPUT_DIR}/"
  end
end

# ── Entry point ───────────────────────────────────────────────────────────────
filter = ARGV.first
EditionDiffGenerator.new.run(filter)
