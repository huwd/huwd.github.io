require 'dotenv/load'
require_relative 'support/wikidata_writer'

module WikidataBooks
  def self.works
    WikidataWriter.new
  end

  def self.editions
    WikidataWriter.new
  end
end
