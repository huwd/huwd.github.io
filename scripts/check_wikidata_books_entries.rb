require 'json'
require 'httparty'
require 'pry'

class CheckWikidataBookEntries
  WIKIDATA_REST_GET_ITEM = "https://www.wikidata.org/w/rest.php/wikibase/v0/entities/items"

  def initialize
    @books = JSON.load File.new("_data/books.json")
  end

  def works_iris
    @books.select do |book|
      book["work_iri"] != nil && book["work_iri"]&.split("/")&.count > 4
    end.map { |book| book["work_iri"].split("/").last }
  end

  def edition_iris
    @books.select do |book|
      book["edition_iri"] != nil && book["edition_iri"]&.split("/")&.count > 4
    end.map { |book| book["edition_iri"].split("/").last }
  end

  def query_wikidata(iris)
    print
    iris.map.with_index do |iri, i|
      print "\r"
      print "Querying #{i+1}/#{iris.count}"
      HTTParty.get(
        "#{WIKIDATA_REST_GET_ITEM}/#{iri}",
        headers: {
          'accept' => 'application/json'
          }
        ).parsed_response
    end
  end

  def validate_work
    print "Validating Works:\n"
    work_items = query_wikidata(works_iris)
    work_items.map.with_index do |work, i|
      print "\r"
      print "Validating #{i+1}/#{work_items.count}"
      instance_of = work["statements"]["P31"].map { |s| s["value"]["content"] }.first
      unless ["Q114051262", "Q756604"].include?(work["id"])
        binding.pry if !validation_data.keys.include?(instance_of)
      end
      schema = validation_data[instance_of]
      if schema.nil?
        {}
      else
        {
          work["id"] => {
            "labels" => { **work["labels"] },
            "Missing Mandatory" => schema["Mandatory"].keys - work["statements"].keys,
          }
        }
      end
    end
  end

  def validate_edition
    print "Validating Editions:\n"
    items = query_wikidata(edition_iris)
    items.map.with_index do |item, i|
      print "\r"
      print "Validating #{i+1}/#{items.count}"
      instance_of = item["statements"]["P31"].map { |s| s["value"]["content"] }.first
      unless [].include?(item["id"])
        binding.pry if !validation_data.keys.include?(instance_of)
      end
      schema = validation_data[instance_of]
      if schema.nil?
        {}
      else
        {
          item["id"] => {
            "labels" => { **item["labels"] },
            "Missing Mandatory" => schema["Mandatory"].keys - item["statements"].keys,
          }
        }
      end
    end
  end

  def validation_data
    {
      "Q7725634" => {
        "Mandatory" => {
          "P31" => "instance of",
          "P1476" => "title",
          "P50" => "author",
          "P407" => "language of work or name",
          "P577" => "publication date",
          "P747" => "has edition or translation"
        },
        "Mandatory if applicable" => {
          "P1680" => {
            "label" => "subtitle",
            "condition" => "if present"
          },
          "P767" => {
            "label" => "contributor to the creative work or subject",
            "condition" => "if present"
          },
          "P155" => {
            "label" => "follows",
            "condition" => "if present"
          },
          "P156" => {
            "label" => "followed by",
            "condition" => "if present"
          },
          "P571" => {
            "label" => "inception",
            "condition" => "if known"
          }
        },
        "Optional" => {
          "P136" => "genre",
          "P135" => "movement",
          "P921" => "main subject",
          "P674" => "characters",
          "P840" => "narrative location",
          "P144" => "based on",
          "P941" => "inspired by"
        }
      },
      "Q35760" => {
        "Mandatory" => {
          "P31" => "instance of",
          "P1476" => "title",
          "P577" => "publication date",
          "P50" => "author",
          "P407" => "language of work or name",
          "P747" => "has edition or translation"
        },
        "Mandatory if applicable" => {
          "P1680" => {
            "label" => "subtitle",
            "condition" => "if present"
          },
          "P767" => {
            "label" => "contributor to the creative work or subject",
            "condition" => "if present"
          },
          "P155" => {
            "label" => "follows",
            "condition" => "if present"
          },
          "P156" => {
            "label" => "followed by",
            "condition" => "if present"
          },
          "P571" => {
            "label" => "inception",
            "condition" => "if known"
          }
        },
        "Optional" => {
          "P136" => "genre",
          "P135" => "movement",
          "P921" => "main subject",
          "P674" => "characters",
          "P840" => "narrative location",
          "P144" => "based on",
          "P941" => "inspired by"
        }
      },
      "Q725377" => {
        "Mandatory" => {
          "P31" => "instance of",
          "P1476" => "title",
          "P577" => "publication date",
          "P50" => "author",
          "P747" => "has edition or translation",
          "P407" => "language of work or name"
        },
        "Mandatory if applicable" => {
          "P1680" => {
            "label" => "subtitle",
            "condition" => "if present"
          },
          "P767" => {
            "label" => "contributor to the creative work or subject",
            "condition" => "if present"
          },
          "P155" => {
            "label" => "follows",
            "condition" => "if present"
          },
          "P156" => {
            "label" => "followed by",
            "condition" => "if present"
          },
          "P571" => {
            "label" => "inception",
            "condition" => "if known"
          }
        },
        "Optional" => {
          "P136" => "genre",
          "P135" => "movement",
          "P921" => "main subject",
          "P674" => "characters",
          "P840" => "narrative location",
          "P144" => "based on",
          "P941" => "inspired by"
        }
      },
      "Q8261" => {
        "Mandatory" => {
          "P31" => "instance of",
          "P1476" => "title",
          "P577" => "publication date",
          "P50" => "author",
          "P407" => "language of work or name",
          "P747" => "has edition or translation",
        },
        "Mandatory if applicable" => {
          "P1680" => {
            "label" => "subtitle",
            "condition" => "if present"
          },
          "P767" => {
            "label" => "contributor to the creative work or subject",
            "condition" => "if present"
          },
          "P155" => {
            "label" => "follows",
            "condition" => "if present"
          },
          "P156" => {
            "label" => "followed by",
            "condition" => "if present"
          },
          "P571" => {
            "label" => "inception",
            "condition" => "if known"
          }
        },
        "Optional" => {
          "P136" => "genre",
          "P135" => "movement",
          "P921" => "main subject",
          "P674" => "characters",
          "P840" => "narrative location",
          "P144" => "based on",
          "P941" => "inspired by"
        }
      },
      "Q47461344" => {
        "Mandatory" => {
          "P31" => "instance of",
          "P1476" => "title",
          "P577" => "publication date",
          "P50" => "author",
          "P407" => "language of work or name",
          "P747" => "has edition or translation",
        },
        "Mandatory if applicable" => {
          "P1680" => {
            "label" => "subtitle",
            "condition" => "if present"
          },
          "P767" => {
            "label" => "contributor to the creative work or subject",
            "condition" => "if present"
          },
          "P155" => {
            "label" => "follows",
            "condition" => "if present"
          },
          "P156" => {
            "label" => "followed by",
            "condition" => "if present"
          },
          "P571" => {
            "label" => "inception",
            "condition" => "if known"
          }
        },
        "Optional" => {
          "P136" => "genre",
          "P135" => "movement",
          "P921" => "main subject",
          "P674" => "characters",
          "P840" => "narrative location",
          "P144" => "based on",
          "P941" => "inspired by"
        }
      },
      "Q106833" => {
        "Mandatory" => {
          "P31" => "instance of",
          "P629" => "edition or translation of",
          "P577" => "publication date",
          "P123" => "publisher",
          "P407" => "language of work or name",
          "P2438" => "narrator",
          "P2047" => "duration"
        },
        "Mandatory if applicable" => {
          "P2679" => {
            "label" => "author of foreword",
            "condition" => "if present"
          },
          "P2680" => {
            "label" => "author of afterword",
            "condition" => "if present"
          },
          "P98" => {
            "label" => "editor",
            "condition" => "if present"
          },
        },
        "Mandatory if different from work" => {
          "P50" => "author",
          "P1476" => "title",
          "P1680" => "subtitle",
        },
        "Optional" => {
          "P655" => "translator"
        }
      },
      "Q3331189" => {
        "Mandatory" => {
          "P31" => "instance of",
          "P629" => "edition or translation of",
          "P1476" => "title",
          "P1680" => "subtitle",
          "P291" => "place of publication",
          "P577" => "publication date",
          "P123" => "publisher",
          "P407" => "language of work or name"
        },
        "Mandatory if applicable" => {
          "P2679" => {
            "label" => "author of foreword",
            "condition" => "if present"
          },
          "P2680" => {
            "label" => "author of afterword",
            "condition" => "if present"
          },
          "P98" => {
            "label" => "editor",
            "condition" => "if present"
          },
        },
        "Mandatory if different from work" => {
          "P50" => "author",
          "P1476" => "title",
          "P1680" => "subtitle",
        },
        "Optional" => {
          "P655" => "translator",
          "P110" => "illustrator",
          "P872" => "printed by",
        }
      }
    }
  end
end

entry_checker = CheckWikidataBookEntries.new
output_works = entry_checker.validate_work
print "\n"
todo_works = output_works.nil? ? {} : output_works.reject { |work| work == {} }.select { |work| work.values.first["Missing Mandatory"] != [] }

output_editions = entry_checker.validate_edition
print "\n"
todo_editions = output_editions.nil? ? {} : output_editions.reject { |ed| ed == {} }.select { |ed| ed.values.first["Missing Mandatory"] != [] }
File.open('_data/wikidata_works_to_improve.json', 'w') { |file| file.write(JSON.pretty_generate(todo_works)) }
File.open('_data/wikidata_edition_to_improve.json', 'w') { |file| file.write(JSON.pretty_generate(todo_editions)) }
