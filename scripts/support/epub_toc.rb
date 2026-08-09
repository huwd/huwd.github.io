require 'zip'
require 'cgi'

# Reads an EPUB's table of contents (EPUB3 nav or EPUB2 NCX) and extracts the
# text of back-matter sections (bibliography, notes, references, etc.) by
# locating their entries in the TOC and pulling the corresponding content.
module EpubToc
  BACK_MATTER_KEYWORDS = [
    "bibliography", "select bibliography", "further reading", "works cited",
    "endnotes", "notes on sources", "sources", "references", "select sources",
    "notes", "notes and references"
  ].freeze

  TocEntry = Struct.new(:label, :href, :file, :anchor, keyword_init: true)

  # Returns { toc: [TocEntry, ...], matched: [TocEntry, ...] }
  def self.read_toc(epub_path, keywords: BACK_MATTER_KEYWORDS)
    Zip::File.open(epub_path) do |zip|
      opf_path = find_opf(zip)
      opf_dir = File.dirname(opf_path)
      opf_dir = "" if opf_dir == "."
      opf = zip.read(opf_path)

      toc_doc_path = find_toc_doc_path(opf, opf_dir)
      raise "No TOC document found (checked EPUB3 nav and EPUB2 NCX)" unless toc_doc_path

      entry = zip.find_entry(toc_doc_path) || zip.glob("**/#{File.basename(toc_doc_path)}").first
      raise "TOC document #{toc_doc_path} not found in archive" unless entry

      toc_content = entry.get_input_stream.read.force_encoding('UTF-8')
      toc = parse_toc_labels(toc_content)

      matched = toc.select do |t|
        norm = normalize(t.label)
        keywords.any? { |kw| norm == kw || norm.start_with?("#{kw} ") }
      end

      { toc: toc, matched: matched }
    end
  end

  # Extracts the text content for a single matched TocEntry.
  # Returns { text:, exact:, file: } — exact: false means we fell back to
  # dumping the whole file because the section shares a file via anchors
  # and we could not cleanly slice by id boundaries.
  def self.extract_section(epub_path, toc_entry, all_toc_entries)
    Zip::File.open(epub_path) do |zip|
      opf_path = find_opf(zip)
      opf_dir = File.dirname(opf_path)
      opf_dir = "" if opf_dir == "."

      file_path = resolve_path(opf_dir, toc_entry.file)
      entry = zip.find_entry(file_path) || zip.glob("**/#{File.basename(file_path)}").first
      return { text: nil, exact: false, file: file_path } unless entry

      html = entry.get_input_stream.read.force_encoding('UTF-8')

      # Same-file siblings, in document order, used to find this section's end
      # boundary. Purely-numeric labels are page-list markers, not real
      # section headings — exclude them even if they slipped past the
      # toc-nav scoping in parse_toc_labels.
      siblings = all_toc_entries
        .select { |t| t.file == toc_entry.file && t.label !~ /\A\d+\z/ }
        .sort_by { |t| html.index("id=\"#{t.anchor}\"").to_i rescue 0 }

      if toc_entry.anchor.nil? || siblings.size <= 1
        return { text: html_to_text(html), exact: true, file: file_path }
      end

      start_idx = anchor_index(html, toc_entry.anchor)
      return { text: html_to_text(html), exact: false, file: file_path } unless start_idx

      idx_in_siblings = siblings.index(toc_entry)
      next_entry = siblings[idx_in_siblings + 1]
      end_idx = next_entry && next_entry.anchor ? anchor_index(html, next_entry.anchor) : nil

      slice = end_idx ? html[start_idx...end_idx] : html[start_idx..]
      { text: html_to_text(slice), exact: !!end_idx || next_entry.nil?, file: file_path }
    end
  end

  def self.anchor_index(html, anchor)
    idx = html.index(/id=["']#{Regexp.escape(anchor)}["']/)
    return nil unless idx
    # back up to the start of the enclosing tag
    tag_start = html.rindex('<', idx)
    tag_start || idx
  end
  private_class_method :anchor_index

  def self.find_opf(zip)
    container = zip.read("META-INF/container.xml")
    m = container.match(/full-path="([^"]+)"/)
    raise "Could not find OPF path in container.xml" unless m
    m[1]
  end
  private_class_method :find_opf

  # OPF tag names are sometimes namespace-prefixed (<opf:item>, <opf:spine>)
  # instead of using a default namespace (<item>, <spine>) — both are valid,
  # so tags are matched with an optional prefix throughout.
  NS_PREFIX = /(?:\w+:)?/

  def self.find_toc_doc_path(opf, opf_dir)
    # EPUB3: manifest item with properties="nav"
    if (m = opf.match(/<#{NS_PREFIX}item\b[^>]*\bproperties="[^"]*\bnav\b[^"]*"[^>]*>/) || opf.match(/<#{NS_PREFIX}item\b(?:(?!\/>).)*?properties="[^"]*\bnav\b[^"]*"(?:(?!\/>).)*?\/>/m))
      href = m[0][/href="([^"]+)"/, 1]
      return resolve_path(opf_dir, href) if href
    end

    # EPUB2: spine toc="idref" -> manifest item id -> href
    if (spine_m = opf.match(/<#{NS_PREFIX}spine\b[^>]*\btoc="([^"]+)"/))
      toc_id = spine_m[1]
      if (item_m = opf.match(/<#{NS_PREFIX}item\b(?:(?!\/>).)*?\bid="#{Regexp.escape(toc_id)}"(?:(?!\/>).)*?\/>/m))
        href = item_m[0][/href="([^"]+)"/, 1]
        return resolve_path(opf_dir, href) if href
      end
    end

    nil
  end
  private_class_method :find_toc_doc_path

  def self.resolve_path(base_dir, href)
    return href if base_dir.nil? || base_dir.empty?
    File.join(base_dir, href)
  end
  private_class_method :resolve_path

  # Parses <a href="...">Label</a> (EPUB3 nav) or <navPoint><navLabel><text>Label</text></navLabel><content src="..."/> (EPUB2 NCX)
  #
  # EPUB3 nav documents commonly bundle multiple <nav> blocks in one file:
  # epub:type="toc" (what we want), plus "landmarks" and "page-list" (physical
  # page markers like "292", "293", ...). Scanning the whole document mixes
  # page-list anchors in as if they were TOC siblings, which truncates real
  # sections almost immediately when used as boundary markers. Scope to the
  # toc nav specifically when present.
  def self.parse_toc_labels(content)
    entries = []

    toc_nav = content[/<nav\b[^>]*\bepub:type="[^"]*\btoc\b[^"]*"[^>]*>.*?<\/nav>/m]
    scan_target = toc_nav || content

    scan_target.scan(/<a\b[^>]*\bhref="([^"]+)"[^>]*>(.*?)<\/a>/m) do |href, inner|
      label = CGI.unescapeHTML(inner.gsub(/<[^>]+>/, '')).strip.gsub(/\s+/, ' ')
      next if label.empty?
      file, anchor = href.split('#', 2)
      entries << TocEntry.new(label: label, href: href, file: file, anchor: anchor)
    end

    if entries.empty?
      content.scan(/<navPoint\b.*?<\/navPoint>/m) do |np|
        label = np[/<text>(.*?)<\/text>/m, 1].to_s.strip
        href = np[/<content\b[^>]*\bsrc="([^"]+)"/, 1]
        next if label.empty? || href.nil?
        file, anchor = href.split('#', 2)
        entries << TocEntry.new(label: label, href: href, file: file, anchor: anchor)
      end
    end

    entries
  end
  private_class_method :parse_toc_labels

  def self.normalize(label)
    label.downcase.gsub(/[^a-z0-9\s]/, ' ').gsub(/\s+/, ' ').strip
  end
  private_class_method :normalize

  def self.html_to_text(html)
    text = html.gsub(/<(script|style)\b.*?<\/\1>/mi, ' ')
    text = text.gsub(/<br\s*\/?>/i, "\n")
    text = text.gsub(/<\/(p|div|li|h[1-6])>/i, "\n")
    # Preserve italic emphasis as markdown-style asterisks before stripping
    # tags — bibliography entries almost universally italicize the work
    # title (Chicago/MLA/APA style), and that's the single most useful
    # structural signal for later splitting a citation into author vs title.
    text = text.gsub(/<\/?(i|em)\b[^>]*>/i, '*')
    text = text.gsub(/<[^>]+>/, ' ')
    text = CGI.unescapeHTML(text)
    text.gsub(/[ \t]+/, ' ').gsub(/\n[ \t]+/, "\n").gsub(/\n{3,}/, "\n\n").strip
  end
  private_class_method :html_to_text
end
