module Builders
  # bridgetown-seo-tag falls back to the sitewide site_metadata.description
  # for any document that doesn't set its own `description:` front matter -
  # which is every single book, review, and weeknote on this site, so every
  # page currently shows the identical generic homepage description in
  # search results and social shares. Derive a per-page one from the first
  # real paragraph of body content instead.
  #
  # Runs in :post_read, before Markdown conversion, so resource.content is
  # still raw Markdown source - plain_text strips just enough of it (links,
  # emphasis, inline code) to read cleanly as a meta description. Scoped to
  # .md files only: .erb pages (reading/blog/reviews/weeknotes listings) are
  # ERB template source at this point, not prose, and would produce garbage.
  class DescriptionFromExcerpt < SiteBuilder
    MAX_LENGTH = 155

    def build
      hook :site, :post_read do |site|
        site.resources.each do |resource|
          next if resource.collection.data?
          next if resource.data.key?("description")
          next unless resource.extname == ".md"

          excerpt = first_paragraph(resource.content)
          resource.data.description = truncate(excerpt) unless excerpt.empty?
        end
      end
    end

    private

    def first_paragraph(content)
      return "" if content.nil?

      paragraph = content.split(/\n\s*\n/).map(&:strip).find { |p| substantive?(p) }
      paragraph ? plain_text(paragraph) : ""
    end

    # Skips headings, blockquotes, list blocks, and reference-style link
    # definitions - not real prose, and a heading in particular would just
    # repeat the page's own title.
    def substantive?(paragraph)
      return false if paragraph.empty?
      return false if paragraph.start_with?("#", ">")
      return false if paragraph.lines.all? { |line| line.strip.start_with?("-", "*") }
      return false if paragraph.lines.all? { |line| line.strip =~ /\A\[[^\]]+\]:\s*\S+\z/ }

      true
    end

    def plain_text(markdown)
      markdown
        .gsub(/!\[[^\]]*\]\([^)]*\)/, "")       # images
        .gsub(/\[([^\]]+)\]\([^)]*\)/, '\1')    # inline links -> visible text
        .gsub(/\[([^\]]+)\]\[[^\]]*\]/, '\1')   # reference-style links -> visible text
        .gsub(/(\*\*|__)(.*?)\1/, '\2')         # bold
        .gsub(/(\*|_)(.*?)\1/, '\2')            # italic
        .gsub(/`([^`]+)`/, '\1')                # inline code
        .gsub(/\s+/, " ")
        .strip
    end

    def truncate(text)
      return text if text.length <= MAX_LENGTH

      "#{text[0...MAX_LENGTH].sub(/\s+\S*\z/, "")}…"
    end
  end
end
