# Pipeline coverage notes (items marked † require a future pass):
#
# P123 (publisher) — required for editions; needs publisher QID resolution.
#   A separate publisher_qids.json cache and minimum-viable publisher node spec
#   (P31=Q2085381, P1476, P571) is required before P123 can be written.
#   The publisher name is captured in edition diffs as an unfillable note.
#
# P291 (place of publication) — required for print editions; not available from
#   Hardcover. Captured in edition diffs as an unfillable note; add manually
#   from ISBN/publisher data if known.
#
# Hardcover IDs — not a Wikidata property yet; cached locally in
#   _data/hardcover_ids.json for future fast querying.

class DataModel
  def work_types
    {
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
      "Q20540385" => {
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
      "Q122731938" => {
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
      },
      "Q1224889" => {
        "Mandatory" => {
          "P31" => "instance of",
          "P629" => "edition or translation of",
          "P1476" => "title",
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

  def edition_types
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
        }
      },
      "Q122731938" => {
        "Mandatory" => {
          "P31" => "instance of",
          "P629" => "edition or translation of",
          "P5749" => "aisn"
        },
        "Mandatory if different from work" => {
          "P50" => "author",
          "P1476" => "title",
          "P577" => "publication date",
          "P407" => "language of work or name",
          "P2047" => "duration"
        },
        "Mandatory requires separate item" => {
          "P123" => "publisher",
          "P2438" => "narrator"
        }
      }
    }
  end
end
