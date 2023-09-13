class DataModel
  def work
    {
      "Q47461344" => {
        "Mandatory" => {
          "P31" => "instance of",
          "P1476" => "title",
          "P571" => "inception",
          "P50" => "author",
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
      }
    }
  end

  def edition
    {
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
          "P50" => "author"
        },
        "Optional" => {
          "P655" => "translator",
          "P110" => "illustrator",
          "P872" => "printed by",
          "P655" => "translator"
        }
      }
    }
  end
end