require 'json'
require 'fileutils'
require_relative 'helpers'
require_relative 'frontmatter_updater'

class WikidataWriter
  include Helpers

  ACCEPTED_DIR         = "_data/accepted_changes"
  ACCEPTED_EDITION_DIR = "_data/accepted_edition_changes"
  CALENDAR_MODEL       = "http://www.wikidata.org/entity/Q1985727"
  WIKIDATA_BASE        = "https://www.wikidata.org/wiki/"

  # ── Works ──────────────────────────────────────────────────────────────────

  def create!(slug)
    data = load_accepted(slug, ACCEPTED_DIR)
    raise "Expected create_work, got #{data['action']}" unless data['action'] == 'create_work'

    payload = {
      item: {
        labels:       { en: data.fetch('label_en') },
        descriptions: { en: data.fetch('description_en') },
        statements:   build_statements(data.fetch('statements'))
      },
      comment: data.fetch('edit_summary')
    }

    r = api.post_item(payload)
    raise "Wikidata API error #{r.code}: #{r.body}" unless r.code.to_i == 201

    qid = r.parsed_content['id']
    FrontmatterUpdater.new(dry_run: false).update_work_iri(data['book_file'], qid)
    FileUtils.rm(accepted_path(slug, ACCEPTED_DIR))
    puts "✓ Created #{qid} — work_iri written to #{data['book_file']}"
    puts "  #{WIKIDATA_BASE}#{qid}"
    qid
  end

  def update!(slug)
    data = load_accepted(slug, ACCEPTED_DIR)
    raise "Expected patch_work, got #{data['action']}" unless data['action'] == 'patch_work'

    item_id = data.fetch('item_id')
    summary = data.fetch('edit_summary')

    data.fetch('statements').each do |stmt|
      payload = {
        statement: {
          property: { id: stmt['property'] },
          value: { type: 'value', content: build_value_content(stmt) }
        },
        comment: summary
      }
      r = api.post_item_statement(item_id, payload)
      raise "Wikidata API error #{r.code}: #{r.body}" unless r.code.to_i == 201
      puts "  + #{stmt['property']} added to #{item_id}"
    end

    FileUtils.rm(accepted_path(slug, ACCEPTED_DIR))
    puts "✓ Patched #{item_id}"
    puts "  #{WIKIDATA_BASE}#{item_id}"
  end

  # ── Editions ───────────────────────────────────────────────────────────────

  def create_edition!(slug)
    data = load_accepted(slug, ACCEPTED_EDITION_DIR)
    raise "Expected create_edition, got #{data['action']}" unless data['action'] == 'create_edition'

    payload = {
      item: {
        labels:       { en: data.fetch('label_en') },
        descriptions: { en: data.fetch('description_en') },
        statements:   build_statements(data.fetch('statements'))
      },
      comment: data.fetch('edit_summary')
    }

    r = api.post_item(payload)
    raise "Wikidata API error #{r.code}: #{r.body}" unless r.code.to_i == 201

    edition_qid = r.parsed_content['id']
    updater = FrontmatterUpdater.new(dry_run: false)
    updater.update_edition_iri(data['book_file'], edition_qid)

    add_p747_to_work(data.fetch('work_qid'), edition_qid, data.fetch('edit_summary'))

    FileUtils.rm(accepted_path(slug, ACCEPTED_EDITION_DIR))
    puts "✓ Created edition #{edition_qid} — edition_iri written to #{data['book_file']}"
    puts "  #{WIKIDATA_BASE}#{edition_qid}"
    edition_qid
  end

  def link_edition!(slug)
    data = load_accepted(slug, ACCEPTED_EDITION_DIR)
    raise "Expected link_edition, got #{data['action']}" unless data['action'] == 'link_edition'

    edition_qid = data.fetch('edition_qid')
    FrontmatterUpdater.new(dry_run: false).update_edition_iri(data['book_file'], edition_qid)

    add_p747_to_work(data.fetch('work_qid'), edition_qid, data.fetch('edit_summary'))

    FileUtils.rm(accepted_path(slug, ACCEPTED_EDITION_DIR))
    puts "✓ Linked edition #{edition_qid} — edition_iri written to #{data['book_file']}"
    puts "  #{WIKIDATA_BASE}#{edition_qid}"
  end

  private

  def add_p747_to_work(work_qid, edition_qid, summary)
    payload = {
      statement: {
        property: { id: 'P747' },
        value:    { type: 'value', content: edition_qid }
      },
      comment: summary
    }
    r = api.post_item_statement(work_qid, payload)
    raise "Failed to add P747 to #{work_qid}: #{r.code} #{r.body}" unless r.code.to_i == 201
    puts "  + P747 → #{edition_qid} added to #{work_qid}"
  end

  def load_accepted(slug, dir)
    path = accepted_path(slug, dir)
    raise "No accepted change for '#{slug}' — expected #{path}" unless File.exist?(path)
    JSON.parse(File.read(path))
  end

  def accepted_path(slug, dir)
    File.join(dir, "#{slug}.json")
  end

  def build_statements(stmts)
    stmts.group_by { |s| s['property'] }.transform_values do |group|
      group.map do |s|
        { property: { id: s['property'] }, value: { type: 'value', content: build_value_content(s) } }
      end
    end
  end

  def build_value_content(stmt)
    case stmt['value_type']
    when 'qid', 'string'
      stmt['value']
    when 'monolingual_text'
      stmt['value']
    when 'time'
      {
        time:          stmt['value'],
        precision:     stmt.fetch('precision'),
        calendarmodel: CALENDAR_MODEL
      }
    when 'quantity'
      {
        amount: "+#{stmt['value']}",
        unit:   "http://www.wikidata.org/entity/#{stmt.fetch('unit')}"
      }
    else
      raise "Unknown value_type '#{stmt['value_type']}' in statement #{stmt.inspect}"
    end
  end

  def api
    @api ||= wikidata_rest_client
  end
end
