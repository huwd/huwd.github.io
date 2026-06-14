require_relative 'helpers'

class FrontmatterUpdater
  include Helpers

  WIKIDATA_BASE = "https://www.wikidata.org/wiki/"

  def initialize(dry_run: true)
    @dry_run = dry_run
  end

  # Write a work_iri back to the book's frontmatter.
  # Returns :updated, :already_set, or :no_match.
  def update_work_iri(file, qid)
    content = File.read(file)
    new_iri  = "#{WIKIDATA_BASE}#{qid}"

    return :already_set if content.match?(/^work_iri:\s*#{Regexp.escape(new_iri)}\s*$/)

    updated = content.sub(
      /^(work_iri:\s*).*$/,
      "\\1#{new_iri}"
    )

    return :no_match if updated == content

    File.write(file, updated) unless @dry_run
    :updated
  end
end
