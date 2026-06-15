#!/usr/bin/env ruby
# Resolves narrator names from proposed edition diffs to Wikidata QIDs.
#
# Three-phase approach to minimise API calls:
#   Phase 1 — single SPARQL exact-label match for all names at once
#   Phase 2 — wbsearchentities only for names that didn't exact-match (1s sleep)
#   Phase 3 — single SPARQL batch to check remaining candidates for P31=Q5
#
# Pass --write to save resolved names to _data/narrator_qids.json.
# After writing, regenerate affected diffs to pick up P2438 statements.

require_relative 'support/wikidata_sparql'
require 'json'
require 'optparse'

PROPOSED_DIR   = "_data/proposed_edition_changes"
NARRATOR_CACHE = "_data/narrator_qids.json"

options = { write: false }
OptionParser.new do |o|
  o.on("--write", "Write resolved QIDs to narrator cache") { options[:write] = true }
end.parse!

sparql = WikidataSparql.new

# ── Collect narrator names from diffs ──────────────────────────────────────

narrator_books = Hash.new { |h, k| h[k] = [] }

Dir.glob("#{PROPOSED_DIR}/*.json").sort.each do |path|
  data = JSON.parse(File.read(path))
  (data['prerequisites'] || []).each do |prereq|
    next unless prereq['type'] == 'narrator_node' && prereq['status'] == 'unresolved'
    narrator_books[prereq['name']] << data['book_title']
  end
end

if narrator_books.empty?
  puts "No unresolved narrators found in #{PROPOSED_DIR}/"
  exit 0
end

existing_cache = File.exist?(NARRATOR_CACHE) ? JSON.parse(File.read(NARRATOR_CACHE)) : {}
names_to_resolve = narrator_books.keys.reject { |n| existing_cache.key?(n) }.sort

puts "Narrator QID cache builder"
puts "  #{narrator_books.size} unique narrator names across diffs"
puts "  #{existing_cache.size} already in cache"
puts "  #{names_to_resolve.size} to resolve"

# ── Phase 1: exact label match via SPARQL (one call for all names) ─────────

puts "\nPhase 1: exact label SPARQL for #{names_to_resolve.size} names..."

label_values = names_to_resolve.map { |n| "\"#{n.gsub('"', '\\"')}\"@en" }.join(" ")

exact_results = sparql.query(<<~SPARQL)
  SELECT ?item ?name ?itemDescription WHERE {
    VALUES ?name { #{label_values} }
    ?item rdfs:label ?name .
    ?item wdt:P31 wd:Q5 .
    OPTIONAL {
      ?item schema:description ?itemDescription .
      FILTER(LANG(?itemDescription) = "en")
    }
  }
SPARQL

# name => Array<{ qid, description }>
exact_matches = Hash.new { |h, k| h[k] = [] }
exact_results.each do |r|
  name = r.dig('name', 'value')
  qid  = r.dig('item', 'value').split('/').last
  desc = r.dig('itemDescription', 'value')
  exact_matches[name] << { qid: qid, description: desc }
end

exact_found     = names_to_resolve.select { |n| exact_matches[n].size == 1 }
exact_ambiguous = names_to_resolve.select { |n| exact_matches[n].size > 1 }
needs_search    = names_to_resolve.select { |n| exact_matches[n].empty? }

puts "  #{exact_found.size} exact matches, #{exact_ambiguous.size} ambiguous, #{needs_search.size} need search"

# ── Phase 2: wbsearchentities for unmatched names ─────────────────────────

name_candidates = {}

unless needs_search.empty?
  puts "\nPhase 2: searching #{needs_search.size} unmatched names (1s between calls)...\n\n"

  needs_search.each_with_index do |name, i|
    print "  [#{i + 1}/#{needs_search.size}] #{name} ... "
    $stdout.flush

    candidates = sparql.search_entities(name, limit: 8)
    name_candidates[name] = candidates
    puts "#{candidates.size} result#{candidates.size == 1 ? '' : 's'}"

    sleep(1)
  end
end

# ── Phase 3: batch SPARQL P31=Q5 check for search candidates ──────────────

search_human_info = {}

all_search_qids = name_candidates.values.flatten.map { |c| c['id'] }.uniq
unless all_search_qids.empty?
  puts "\nPhase 3: batch SPARQL — checking #{all_search_qids.size} search candidates for P31=Q5..."

  values = all_search_qids.map { |q| "wd:#{q}" }.join(" ")
  results = sparql.query(<<~SPARQL)
    SELECT ?item ?itemLabel ?itemDescription WHERE {
      VALUES ?item { #{values} }
      ?item wdt:P31 wd:Q5 .
      SERVICE wikibase:label { bd:serviceParam wikibase:language "en". }
    }
  SPARQL

  results.each do |r|
    qid  = r.dig('item', 'value').split('/').last
    search_human_info[qid] = {
      label:       r.dig('itemLabel', 'value'),
      description: r.dig('itemDescription', 'value')
    }
  end

  puts "  #{search_human_info.size} humans found"
end

# ── Classify each narrator ────────────────────────────────────────────────

Result = Struct.new(:name, :status, :qid, :label, :description, :candidates, :books)

results = names_to_resolve.map do |name|
  books = narrator_books[name]

  if exact_matches[name].size == 1
    m = exact_matches[name].first
    Result.new(name, :found, m[:qid], name, m[:description], [], books)

  elsif exact_matches[name].size > 1
    Result.new(name, :ambiguous, nil, nil, nil,
               exact_matches[name].map { |m| m[:qid] }, books)

  else
    candidates     = name_candidates[name] || []
    human_cands    = candidates.select { |c| search_human_info.key?(c['id']) }

    case human_cands.size
    when 0
      Result.new(name, :not_found, nil, nil, nil,
                 candidates.map { |c| c['id'] }, books)
    when 1
      c    = human_cands.first
      info = search_human_info[c['id']]
      Result.new(name, :found, c['id'], info[:label], info[:description], [], books)
    else
      Result.new(name, :ambiguous, nil, nil, nil,
                 human_cands.map { |c| c['id'] }, books)
    end
  end
end

# ── Print summary ─────────────────────────────────────────────────────────

found     = results.select { |r| r.status == :found }
ambiguous = results.select { |r| r.status == :ambiguous }
not_found = results.select { |r| r.status == :not_found }

puts "\n#{"─" * 70}"

unless found.empty?
  puts "\nRESOLVED (#{found.size})"
  found.each do |r|
    puts "  ✓ %-32s %s" % [r.name, r.qid]
    puts "    #{r.description}" if r.description
    puts "    Books: #{r.books.first(3).join(", ")}#{r.books.size > 3 ? " (+#{r.books.size - 3} more)" : ""}"
  end
end

unless ambiguous.empty?
  puts "\nAMBIGUOUS — manual resolution required (#{ambiguous.size})"
  ambiguous.each do |r|
    puts "  ? #{r.name}"
    puts "    Candidates: #{r.candidates.map { |q| "https://www.wikidata.org/wiki/#{q}" }.join(", ")}"
    puts "    Books: #{r.books.join(", ")}"
  end
end

unless not_found.empty?
  puts "\nNOT FOUND — may need a Wikidata item created (#{not_found.size})"
  not_found.each do |r|
    puts "  ✗ #{r.name}"
    puts "    Books: #{r.books.join(", ")}"
  end
end

puts "\n#{"─" * 70}"
puts "Already cached: #{existing_cache.size}"
puts "Resolved now:   #{found.size}"
puts "Ambiguous:      #{ambiguous.size}"
puts "Not found:      #{not_found.size}"

# ── Write ─────────────────────────────────────────────────────────────────

if options[:write]
  if found.empty?
    puts "\nNothing to write."
  else
    updated = existing_cache.merge(found.each_with_object({}) { |r, h| h[r.name] = r.qid })
    File.write(NARRATOR_CACHE, JSON.pretty_generate(updated))
    puts "\n✓ Wrote #{updated.size} entries to #{NARRATOR_CACHE} (#{found.size} new)"
  end
else
  puts "\nDry run — pass --write to save #{found.size} resolved narrators to #{NARRATOR_CACHE}"
end
