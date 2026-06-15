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
    update_iri(file, 'work_iri', qid)
  end

  # Write an edition_iri back to the book's frontmatter.
  # Returns :updated, :already_set, or :no_match.
  def update_edition_iri(file, qid)
    update_iri(file, 'edition_iri', qid)
  end

  private

  def update_iri(file, field, qid)
    content = File.read(file)
    new_iri  = "#{WIKIDATA_BASE}#{qid}"

    return :already_set if content.match?(/^#{field}:\s*#{Regexp.escape(new_iri)}\s*$/)

    # Replace existing field if present
    updated = content.sub(/^(#{field}:\s*).*$/, "\\1#{new_iri}")

    # Insert after work_iri if field not present
    if updated == content
      updated = content.sub(/^(work_iri:[^\n]*)/) { "#{$1}\n#{field}: #{new_iri}" }
    end

    return :no_match if updated == content

    File.write(file, updated) unless @dry_run
    :updated
  end
end
