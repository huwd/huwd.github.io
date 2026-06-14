require 'json'
require 'fileutils'
require_relative 'helpers'
require_relative 'frontmatter_updater'

class WikidataWriter
  include Helpers

  ACCEPTED_DIR = "_data/accepted_changes"
  CALENDAR_MODEL = "http://www.wikidata.org/entity/Q1985727"

  def create!(slug)
    data = load_accepted(slug)
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
    FileUtils.rm(accepted_path(slug))
    url = "https://www.wikidata.org/wiki/#{qid}"
    puts "✓ Created #{qid} — work_iri written to #{data['book_file']}"
    puts "  #{url}"
    qid
  end

  def update!(slug)
    data = load_accepted(slug)
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

    FileUtils.rm(accepted_path(slug))
    puts "✓ Patched #{item_id}"
    puts "  https://www.wikidata.org/wiki/#{item_id}"
  end

  private

  def load_accepted(slug)
    path = accepted_path(slug)
    raise "No accepted change for '#{slug}' — expected #{path}" unless File.exist?(path)
    JSON.parse(File.read(path))
  end

  def accepted_path(slug)
    File.join(ACCEPTED_DIR, "#{slug}.json")
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
    when 'qid'
      stmt['value']
    when 'monolingual_text'
      stmt['value']
    when 'time'
      {
        time:          stmt['value'],
        precision:     stmt.fetch('precision'),
        calendarmodel: CALENDAR_MODEL
      }
    else
      raise "Unknown value_type '#{stmt['value_type']}' in statement #{stmt.inspect}"
    end
  end

  def api
    @api ||= wikidata_rest_client
  end
end
