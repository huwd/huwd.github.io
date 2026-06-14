require_relative 'wikidata_sparql'

WikidataEditionMatch = Struct.new(
  :qid,
  :url,
  :p31,          # instance type QID or nil
  :p629,         # edition-of QID or nil
  :match_method, # :asin | :isbn13 | :p629_link
  keyword_init: true
)

class EditionMatcher
  WIKIDATA_BASE = "https://www.wikidata.org/wiki/"

  def initialize
    @sparql = WikidataSparql.new
  end

  # Search Wikidata for an existing edition item. Returns WikidataEditionMatch or nil.
  # Search order: ASIN (most precise) → ISBN-13 → work's existing P629 back-links.
  def find(asin: nil, isbn13: nil, work_qid: nil)
    if asin
      results = @sparql.edition_by_asin(asin)
      sleep(0.5)
      return build_match(results.first, :asin) if results.any?
    end

    if isbn13
      results = @sparql.edition_by_isbn13(isbn13)
      sleep(0.5)
      return build_match(results.first, :isbn13) if results.any?
    end

    if work_qid
      results = @sparql.editions_of_work(work_qid)
      sleep(0.5)
      return build_match(results.first, :p629_link) if results.any?
    end

    nil
  end

  private

  def build_match(binding, method)
    return nil unless binding
    qid = binding.dig('item', 'value')&.split('/')&.last
    return nil unless qid

    WikidataEditionMatch.new(
      qid:          qid,
      url:          "#{WIKIDATA_BASE}#{qid}",
      p31:          binding.dig('p31',  'value')&.split('/')&.last,
      p629:         binding.dig('p629', 'value')&.split('/')&.last,
      match_method: method
    )
  end
end
