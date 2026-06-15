#!/usr/bin/env ruby
# Creates minimal Wikidata stubs for audiobook narrators not yet on Wikidata.
# Items are created as humans (P31=Q5) with occupation voice actor (P106=Q2405480),
# plus optional gender (P21), citizenship (P27), and IMDB ID (P345).
#
# Pass --dry-run to preview without writing.
# Cache is updated after each creation so progress is never lost.

require 'dotenv/load'
require 'json'
require_relative 'support/helpers'

include Helpers

NARRATOR_QID_FILE = '_data/narrator_qids.json'

COUNTRY_QIDS = {
  'US' => 'Q30',
  'GB' => 'Q145',
  'ZA' => 'Q258',
  'IE' => 'Q27'
}.freeze

GENDER_QIDS = {
  'male'   => 'Q6581097',
  'female' => 'Q6581072'
}.freeze

NARRATORS = [
  { name: 'Cameron Stewart',      description: 'British audiobook narrator',                 nationality: 'GB', gender: 'male',   imdb_id: nil },
  { name: 'Jamie Grant',          description: 'British audiobook narrator',                 nationality: 'GB', gender: 'male',   imdb_id: nil },
  { name: 'John Banks',           description: 'British actor and audiobook narrator',       nationality: 'GB', gender: 'male',   imdb_id: 'nm0713943' },
  { name: 'John Skelley',         description: 'American actor and audiobook narrator',      nationality: 'US', gender: 'male',   imdb_id: 'nm3025504' },
  { name: 'Kevin Shen',           description: 'British actor and audiobook narrator',       nationality: 'GB', gender: 'male',   imdb_id: 'nm4586939' },
  { name: 'Michael Fox',          description: 'English actor and audiobook narrator',       nationality: 'GB', gender: 'male',   imdb_id: 'nm5320024' },
  { name: 'Paul Hodgson',         description: 'British audiobook narrator',                 nationality: 'GB', gender: 'male',   imdb_id: nil },
  { name: 'Peter Noble',          description: 'audiobook narrator',                         nationality: nil,  gender: 'male',   imdb_id: 'nm4150936' },
  { name: 'René Ruiz',            description: 'American voice actor and audiobook narrator', nationality: 'US', gender: 'male',  imdb_id: nil },
  { name: 'Tiffany Morgan',       description: 'American actress and audiobook narrator',    nationality: 'US', gender: 'female', imdb_id: 'nm1390793' },
  { name: 'Aldrich Barrett',      description: 'audiobook narrator',                         nationality: nil,  gender: 'female', imdb_id: nil },
  { name: 'Billie Fulford-Brown', description: 'British actress and audiobook narrator',     nationality: 'GB', gender: 'female', imdb_id: 'nm3638780' },
  { name: 'Bob Souer',            description: 'American audiobook narrator',                nationality: 'US', gender: 'male',   imdb_id: nil },
  { name: 'Darren Chetty',        description: 'British educator and audiobook narrator',    nationality: 'GB', gender: 'male',   imdb_id: nil },
  { name: 'Edward Bauer',         description: 'audiobook narrator',                         nationality: nil,  gender: 'male',   imdb_id: nil },
  { name: 'Eric Jason Martin',    description: 'American audiobook narrator',                nationality: 'US', gender: 'male',   imdb_id: nil },
  { name: 'George Backman',       description: 'British-born audiobook narrator',            nationality: 'GB', gender: 'male',   imdb_id: nil },
  { name: 'Helen Lloyd',          description: 'British actress and audiobook narrator',     nationality: 'GB', gender: 'female', imdb_id: nil },
  { name: 'Hugh Kermode',         description: 'British actor and audiobook narrator',       nationality: 'GB', gender: 'male',   imdb_id: 'nm1459079' },
  { name: 'John Lescault',        description: 'American actor and audiobook narrator',      nationality: 'US', gender: 'male',   imdb_id: 'nm0503884' },
  { name: 'Laural Merlington',    description: 'American actress and audiobook narrator',    nationality: 'US', gender: 'female', imdb_id: 'nm3627944' },
  { name: 'Matt Bates',           description: 'British actor and audiobook narrator',       nationality: 'GB', gender: 'male',   imdb_id: 'nm0060986' },
  { name: 'Michael David Axtell', description: 'American actor and audiobook narrator',      nationality: 'US', gender: 'male',   imdb_id: 'nm10184253' },
  { name: 'Michael Rutland',      description: 'audiobook narrator',                         nationality: nil,  gender: 'male',   imdb_id: 'nm7456774' },
  { name: 'Nicol Zanzarella',     description: 'American audiobook narrator',                nationality: 'US', gender: 'female', imdb_id: nil },
  { name: 'Rachel Bavidge',       description: 'British actress and audiobook narrator',     nationality: 'GB', gender: 'female', imdb_id: 'nm1544023' },
  { name: 'Samantha Desz',        description: 'American audiobook narrator',                nationality: 'US', gender: 'female', imdb_id: nil },
  { name: 'Theodore O\'Brien',    description: 'audiobook narrator',                         nationality: nil,  gender: 'male',   imdb_id: nil },
  { name: 'Tia Rider Sorensen',   description: 'American audiobook narrator',                nationality: 'US', gender: 'female', imdb_id: nil },
].freeze

def build_statements(narrator)
  stmts = {}

  stmts['P31']  = [{ property: { id: 'P31' },  value: { type: 'value', content: 'Q5' } }]
  stmts['P106'] = [{ property: { id: 'P106' }, value: { type: 'value', content: 'Q2405480' } }]

  if (g = GENDER_QIDS[narrator[:gender]])
    stmts['P21'] = [{ property: { id: 'P21' }, value: { type: 'value', content: g } }]
  end

  if narrator[:nationality] && (c = COUNTRY_QIDS[narrator[:nationality]])
    stmts['P27'] = [{ property: { id: 'P27' }, value: { type: 'value', content: c } }]
  end

  if narrator[:imdb_id]
    stmts['P345'] = [{ property: { id: 'P345' }, value: { type: 'value', content: narrator[:imdb_id] } }]
  end

  stmts
end

dry_run = ARGV.include?('--dry-run')
api     = wikidata_rest_client unless dry_run

cache = JSON.parse(File.read(NARRATOR_QID_FILE))

created  = {}
skipped  = []

NARRATORS.each do |narrator|
  name = narrator[:name]

  if cache.key?(name)
    puts "  = #{name}: already cached (#{cache[name]})"
    skipped << name
    next
  end

  if dry_run
    tag = [narrator[:nationality], narrator[:gender]].compact.join(', ')
    tag += ", #{narrator[:imdb_id]}" if narrator[:imdb_id]
    puts "  ~ #{name} (#{tag}): would create"
    next
  end

  print "  + #{name} ... "
  $stdout.flush

  payload = {
    item: {
      labels:       { en: name },
      descriptions: { en: narrator[:description] },
      statements:   build_statements(narrator)
    },
    comment: "Create stub for audiobook narrator #{name}"
  }

  r = api.post_item(payload)
  raise "Wikidata API error #{r.code}: #{r.body}" unless r.code.to_i == 201

  qid = r.parsed_content['id']
  puts qid

  created[name] = qid
  cache[name]   = qid
  File.write(NARRATOR_QID_FILE, JSON.pretty_generate(cache.sort.to_h) + "\n")

  sleep 0.5
rescue => e
  puts "ERROR: #{e.message}"
end

puts
puts "Created #{created.size} narrator items:"
created.each { |name, qid| puts "  #{name} → https://www.wikidata.org/wiki/#{qid}" }
puts "Skipped #{skipped.size} already cached." if skipped.any?
