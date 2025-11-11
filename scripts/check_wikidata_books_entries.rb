require 'json'
require 'httparty'
require 'yaml'
require 'pry'
require_relative './support/helpers'
require_relative './data_model'

class Skippable
  def works
    [
      "Q114051262", # Tweet of the day, no written work, was a Radio Programme
      "Q756604"     # Persepolis, no written work, is comic serise
    ]
  end

  def editions
    []
  end
end

class CheckWikidataBookEntries
  include Helpers

  def initialize
    @books = load_stored_books
  end

  def validate_item(type)
    items_to_validate = book_iris("#{type}_iri")
    wikidata_items = query_wikidata(items_to_validate, type)

    available_items = wikidata_items.reject { |item| item.code != 200 }

    available_item_details = available_items.map.with_index do |item, i|
      validation_against_schema(item.parsed_content, type)
    end

    return {
      available: available_item_details.compact,
    }
  end

  private

  def format_return_payload(item, validation_schema)
    return {} if validation_schema.nil?

    missing_mandatory = validation_schema["Mandatory"].keys - item["statements"].keys
    missing_conditionally_mandatory = validation_schema["Mandatory if applicable"].keys - item["statements"].keys
    missing_optional = validation_schema["Optional"].keys - item["statements"].keys

    {
      item["id"] => {
        "labels" => { **item["labels"].select { |k, v| k == "en" } },
        "Missing Mandatory" => missing_mandatory.compact,
        "Mandatory if applicable" => missing_conditionally_mandatory.compact,
        "Optional" => missing_optional.compact
      }
    }
  end

  def item_instance(item)
    item.dig("statements", "P31", 0, "value", "content")
  end

  def book_iris(key)
    @books.values
      .map { |book| book[key] }
      .select { |iri| complete_wikidata_iri?(iri) }
      .map { |iri| iri.split("/").last }
      .uniq
  end

  def query_wikidata(iris, type)
    print
    iris.map.with_index do |iri, i|
      print "\rQuerying Wikidata #{type.capitalize} #{i + 1}/#{iris.count}"
      wikidata_rest_client.get_item(iri)
    end
  end

  def validation_against_schema(item, type)
    instance_of = item_instance(item)

    if unknown_instance_type?(instance_of, type) && !not_known_edgecase_work?(item["id"], type)
      raise UnknownInstanceType
    end

    validation_schema = validation_data(type)[instance_of]
    return format_return_payload(item, validation_schema)

  rescue UnknownInstanceType
    binding.pry
  end

  def not_known_edgecase_work?(work_id, type)
    case type
    when "work"
      !Skippable.new.works.include?(work_id)
    when "edition"
      !Skippable.new.editions.include?(work_id)
    end
  end

  def unknown_instance_type?(instance_type, allowable_type)
    validation_data(allowable_type).keys.include?(instance_type)
  end

  def validation_data(type)
    data_model = DataModel.new

    case type
    when "work"
      data_model.work_types
    when "edition"
      data_model.edition_types
    else
      raise UnknownInstanceType
    end
  end
end

entry_checker = CheckWikidataBookEntries.new
output_works = entry_checker.validate_item("work")

# output_editions = entry_checker.validate_edition
# print "\n"
# todo_editions = output_editions.nil? ? {} : output_editions.reject { |ed| ed == {} }.compact.select { |ed| ed.values.first["Missing Mandatory"] != [] }
File.open('_data/wikidata_works_to_improve.json', 'w') { |file| file.write(JSON.pretty_generate(output_works)) }
# File.open('_data/wikidata_edition_to_improve.json', 'w') { |file| file.write(JSON.pretty_generate(todo_editions)) }
