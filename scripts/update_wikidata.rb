require_relative './support/helpers'
require 'pry'

class WikidataUpdater
  include Helpers

  HANDLED_PROPERTIES = [
    "P577", # https://www.wikidata.org/wiki/Property:P577 publication date
    "P407"  # https://www.wikidata.org/wiki/Property:P407 language of work or name
    # "P747", # https://www.wikidata.org/wiki/Property:P747 has edition or translation
  ]

  def initialize
    @wikidata_works_to_improve = load_wikidata_works_to_improve
    @to_update = data_properties_to_update
  end

  def update_works
    # @to_update["P577"].each { |qid, details| update_publication_date(qid,details) }
    @to_update["P407"].each { |qid, details| update_language_of_work_or_name(qid,details) }
    return "Finished"
  end

  private

  def update_language_of_work_or_name(qid,details)
    puts "========================================="
    puts "#{qid}: #{details['labels']['en']}"
    puts "https://www.wikidata.org/wiki/#{qid}"
    puts "========================================="

    puts "Querying: language of work or name (P407)"
    language_of_work = wikidata_rest_client.get_item_statements(qid, {property: "P407"})
                      .parsed_content

    if language_of_work.dig("P407")&.any?
      puts "Work already has language of work or name (P407). Skipping."
      puts ""
      return
    end

    puts "No language of work or name (P407) available. Manual intervention required to determine appropriate language."
    print "Do you believe this was first published in English? [y/N]: "
    answer = STDIN.gets.to_s.strip.downcase
    if answer == 'y'
      res = wikidata_rest_client.post_item_statements(qid, update_p407_payload_english)
      puts "Success, see https://www.wikidata.org/wiki/#{qid}" if res.code == 201
      puts "Failed to update #{qid}: #{res.code} - #{res.body}" unless res.code == 201
    else
      puts "Language not in english, Manual intervention required. Skipping."
      puts "visit https://www.wikidata.org/wiki/#{qid}"
    end
  end

  def update_publication_date(qid,details)
    puts "========================================="
    puts "#{qid}: #{details['labels']['en']}"
    puts "https://www.wikidata.org/wiki/#{qid}"
    puts "========================================="

    puts "Querying: publication date (P577)"
    publication_date = wikidata_rest_client.get_item_statements(qid, {property: "P577"})
                      .parsed_content

    if publication_date.dig("P577")&.any?
      puts "Work already has publication date (P577). Skipping."
      puts ""
      return
    end

    puts "Querying: inception (P571)"

    inception = wikidata_rest_client.get_item_statements(qid, {property: "P571"})
                      .parsed_content
                      .dig("P571",0,"value")

    if inception
      puts "Inception date found: #{pretty_inception(inception)}"
      print "Use this as publication date (P577)? [y/N]: "
      answer = STDIN.gets.to_s.strip.downcase
      if answer == 'y'
        puts "Will use inception date #{pretty_inception(inception)} for publication date."
        res = wikidata_rest_client.post_item_statements(qid, update_p577_payload(qid, inception))
        puts "Success, see https://www.wikidata.org/wiki/#{qid}" if res.code == 201
        puts "Failed to update #{qid}: #{res.code} - #{res.body}" unless res.code == 201
      else
        puts "User declined using inception date. Skipping."
      end
    else
      puts "No inception date available."
    end
  end

  def pretty_inception(inception)
    render_partial_date(inception.dig("content", "time"))
  end

  def render_partial_date(str)
    # remove leading '+' and trailing 'Z'
    clean = str.gsub(/\A\+|\Z/, "").delete_suffix("Z")

    # split into components
    year, month, day = clean.split(/[-T]/)

    # render progressively
    if month == "00" || month.nil?
      year
    elsif day == "00" || day.nil?
      "#{year}-#{month}"
    else
      "#{year}-#{month}-#{day}"
    end
  end

  def update_p407_payload_english
    {
      "statement": {
        "property": {
          "id": "P407"
        },
        "value": {"type" => "value", "content" => "Q1860"}
      },
        "bot": false,
        "comment": "Updating language of work or name (P407) via script with manual user intervention"
    }
  end

  def update_p577_payload(qid, inception_statement)
    {
      "statement": {
        "property": {
          "id": "P577"
        },
        "value": inception_statement
      },
        "bot": false,
        "comment": "Updating publication date (P577) based on inception (P571) via script with manual user intervention"
    }
  end

  def data_properties_to_update
    HANDLED_PROPERTIES.each_with_object({}) do |prop, acc|
      acc[prop] = @wikidata_works_to_improve["available"]
        .select { |_qid, v| v["Missing Mandatory"].include?(prop) }
    end
  end
end

puts  WikidataUpdater.new.update_works