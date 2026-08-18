require 'json'
require 'time'

BUILD_DIR = ARGV[0] || 'output'
NAVIGATION = JSON.parse(File.read('src/_data/navigation.json'))
CURRENT_YEAR = NAVIGATION['book_years'].first

def read(relative_path)
  File.read(File.join(BUILD_DIR, relative_path))
rescue Errno::ENOENT
  nil
end

def unescape(html)
  html.gsub('&#39;', "'").gsub('&quot;', '"').gsub('&amp;', '&')
end

def has?(html, needle)
  needle.is_a?(Regexp) ? html.match?(needle) : unescape(html).include?(needle)
end

# Checks applying to every page that renders through _head.erb - i.e.
# everything except 404.html and sitemap.xml, which don't use that partial.
# Also serves as a regression net for the site-wide SEO fixes: a broken
# <title>/og:site_name would fail 'title ends " | Huw Diprose"', a stale
# generic description would fail 'no leftover "Homepage" text', an author
# attribution regression would fail 'author meta is Huw Diprose', a missing
# og:image default would fail 'twitter card is summary_large_image', etc.
def feed_autodiscovery_check(feed_path)
  ["autodiscovers #{feed_path} via <link rel=\"alternate\">",
   ->(html) {
     has?(html, %r{<link rel="alternate" type="application/atom\+xml" title="[^"]*" href="#{Regexp.escape(feed_path)}" />})
   }]
end

def seo_checks(canonical_path)
  [
    feed_autodiscovery_check('/feed.xml'),
    ['title ends " | Huw Diprose"', ->(html) { has?(html, /<title>[^<]+ \| Huw Diprose<\/title>/) }],
    ['title has no leftover "Homepage" text', ->(html) { !has?(html, /<title>[^<]*Homepage/) }],
    ['canonical link matches this page\'s own URL',
     ->(html) { has?(html, %(<link rel="canonical" href="https://huwdiprose.co.uk#{canonical_path}" />)) }],
    ['og:site_name is "Huw Diprose"', ->(html) { has?(html, '<meta property="og:site_name" content="Huw Diprose" />') }],
    ['author meta is Huw Diprose, not a book\'s own author',
     ->(html) { has?(html, '<meta name="author" content="Huw Diprose" />') }],
    ['twitter:site is wired up', ->(html) { has?(html, '<meta name="twitter:site" content="@huwdiprose" />') }],
    ['twitter:creator is Huw Diprose, not a book\'s own author',
     ->(html) { has?(html, '<meta name="twitter:creator" content="@huwdiprose" />') }],
    ['og:image points at the sitewide default image',
     ->(html) { has?(html, '<meta property="og:image" content="https://huwdiprose.co.uk/images/social-card.png" />') }],
    ['twitter card is summary_large_image (has an image)',
     ->(html) { has?(html, '<meta name="twitter:card" content="summary_large_image" />') }],
    ['meta description is present and non-empty',
     ->(html) { has?(html, /<meta name="description" content="[^"]+"/) }],
  ]
end

# Parses the (first) JSON-LD block's content. Returns nil - rather than
# raising - on missing/invalid JSON, so a check can fail cleanly instead of
# crashing the whole test run.
def json_ld(html)
  match = html.match(%r{<script type="application/ld\+json">\s*(.*?)\s*</script>}m)
  return nil unless match

  JSON.parse(match[1])
rescue JSON::ParserError
  nil
end

# Shared feature checks any "post-like" page (book, review, weeknote) should
# pass. canonical_path derives from the page's own known output file, so it
# can't drift out of sync with what's actually being tested.
def post_checks(canonical_path)
  [
    ['renders an <article class="post">', ->(html) { has?(html, '<article class="post">') }],
    ['renders a title in <h1>', ->(html) { has?(html, /<h1>[^<]+<\/h1>/) }],
    ['renders a dated <time> element', ->(html) { has?(html, /<time datetime="[^"]+">/) }],
    ['meta description is page-specific, not the sitewide fallback',
     ->(html) { !has?(html, /<meta name="description" content="Homepage of Huw Diprose/) }],
  ] + seo_checks(canonical_path)
end

def listing_checks(title_text, canonical_path)
  [
    ["title includes \"#{title_text}\"", ->(html) { has?(html, "<title>") && has?(html, title_text) }],
    ['renders inside <section class="listing">', ->(html) { has?(html, '<section class="listing">') }],
  ] + seo_checks(canonical_path)
end

# Checks for the Atom feeds added in #187 - self_path is this feed's own
# URL (for its <link rel="self"> and root-relative sanity checks).
def atom_feed_checks(title_text, self_path)
  [
    ['is an Atom feed', ->(xml) { has?(xml, '<feed xmlns="http://www.w3.org/2005/Atom">') }],
    ["title includes \"#{title_text}\"", ->(xml) { has?(xml, %r{<title>[^<]*#{Regexp.escape(title_text)}}) }],
    ['self link matches its own URL',
     ->(xml) { has?(xml, %(<link rel="self" type="application/atom+xml" href="https://huwdiprose.co.uk#{self_path}" />)) }],
    ['has a top-level <id>', ->(xml) { has?(xml, %r{<id>https://huwdiprose\.co\.uk[^<]*</id>}) }],
    ['has a top-level <updated>', ->(xml) { has?(xml, %r{<updated>[^<]+</updated>}) }],
    ['entries (if any) are ordered newest first',
     ->(xml) {
       dates = xml.scan(%r{<published>([^<]+)</published>}).flatten.map { |d| Time.parse(d) }
       dates == dates.sort.reverse
     }],
  ]
end

PAGES = [
  {
    name: 'homepage / about',
    file: 'index.html',
    checks: [
      ['title includes "About me"', ->(html) { has?(html, '<title>') && has?(html, 'About me') }],
      ['renders inside <section class="post">', ->(html) { has?(html, '<section class="post">') }],
      ['includes bio content', ->(html) { has?(html, 'Government Digital Service') }],
      ['nav links to About at "/"', ->(html) { has?(html, /<a href="\/"[^>]*>About<\/a>/) }],
    ] + seo_checks('/'),
  },
  {
    name: 'reading index',
    file: 'reading/index.html',
    checks: listing_checks('Reading', '/reading/') + [
      ['shows a running book total', ->(html) { has?(html, /\(\d+ books total/) }],
      ['renders star ratings', ->(html) { has?(html, '★') }],
    ],
  },
  {
    name: "reading/#{CURRENT_YEAR} (current year, from navigation.json)",
    file: "reading/#{CURRENT_YEAR}/index.html",
    checks: listing_checks("What I read in #{CURRENT_YEAR}", "/reading/#{CURRENT_YEAR}/") + [
      ['book-nav marks the current year active', ->(html) { has?(html, /class="active" href="\/reading\/#{CURRENT_YEAR}"/) }],
    ],
  },
  {
    name: 'projects',
    file: 'projects/index.html',
    checks: listing_checks("Things I've made", '/projects/') + [
      ['renders the project box', ->(html) { has?(html, 'class="project-box"') }],
      ['links out to at least one project', ->(html) { has?(html, /class="project"/) }],
    ],
  },
  {
    name: 'blog listing',
    file: 'blog/index.html',
    checks: listing_checks('Blog', '/blog/') + [feed_autodiscovery_check('/blog/feed.xml')],
  },
  {
    name: 'reviews listing',
    file: 'reviews/index.html',
    checks: listing_checks("Things I've reviewed", '/reviews/') + [
      ['lists at least one entry', ->(html) { has?(html, /<time datetime="[^"]+">/) }],
      feed_autodiscovery_check('/reviews/feed.xml'),
    ],
  },
  {
    name: 'book page (Whale)',
    file: 'review/book/2026/08/17/whale/index.html',
    checks: post_checks('/review/book/2026/08/17/whale/') + [
      ['shows the book title', ->(html) { has?(html, 'Whale') }],
      ['shows read/reviewed meta', ->(html) { has?(html, 'Read:') && has?(html, 'Reviewed:') }],
      ['renders book-to-book navigation', ->(html) { has?(html, 'book-nav-group') }],
      ['JSON-LD Review structured data is valid JSON', ->(html) { !json_ld(html).nil? }],
      # Deliberately bypasses has?/unescape, which would decode &quot; back to "
      # and make this check pass either way - checking the raw HTML directly
      # is the point.
      ['JSON-LD is not HTML-escaped (raw quotes, not &quot;)', ->(html) { html.include?('"@type":"Review"') }],
      ['JSON-LD itemReviewed matches the book title',
       ->(html) { json_ld(html)&.dig('itemReviewed', 'name') == 'Whale' }],
      ['JSON-LD reviewRating.ratingValue matches the page\'s rating',
       ->(html) { json_ld(html)&.dig('reviewRating', 'ratingValue') == 4 }],
      ['JSON-LD author is Huw Diprose, not the book\'s author',
       ->(html) { json_ld(html)&.dig('author', 'name') == 'Huw Diprose' }],
      feed_autodiscovery_check('/reviews/feed.xml'),
    ],
  },
  {
    name: 'multi-book review (The Karla Trilogy)',
    file: 'review/book/2025/11/25/the-karla-trilogy/index.html',
    checks: post_checks('/review/book/2025/11/25/the-karla-trilogy/') + [
      ['shows the review title', ->(html) { has?(html, 'Karla Trilogy') }],
      ['renders book-to-book navigation for each reviewed book', ->(html) { has?(html, 'book-nav-group') }],
      feed_autodiscovery_check('/reviews/feed.xml'),
    ],
  },
  {
    name: 'weeknote',
    file: 'weeknotes/2021-04-12-weeknotes-to-recently/index.html',
    checks: post_checks('/weeknotes/2021-04-12-weeknotes-to-recently/') + [
      feed_autodiscovery_check('/weeknotes/feed.xml'),
    ],
  },
  {
    name: '404',
    file: '404.html',
    checks: [
      ['shows a not-found message', ->(html) { has?(html, 'Page Not Found') }],
    ],
  },
  {
    name: 'sitemap.xml',
    file: 'sitemap.xml',
    checks: [
      ['is a urlset document', ->(html) { has?(html, '<urlset') }],
      ['lists a healthy number of urls', ->(html) { html.scan('<url>').size > 50 }],
    ],
  },
  {
    name: 'site-wide feed.xml',
    file: 'feed.xml',
    checks: atom_feed_checks('Huw Diprose', '/feed.xml') + [
      ['combines reviews, weeknotes, and blog entries', ->(xml) { xml.scan('<entry>').size > 90 }],
    ],
  },
  {
    name: 'reviews feed.xml',
    file: 'reviews/feed.xml',
    checks: atom_feed_checks('Reviews', '/reviews/feed.xml') + [
      ['lists at least one entry', ->(xml) { xml.include?('<entry>') }],
    ],
  },
  {
    name: 'weeknotes feed.xml',
    file: 'weeknotes/feed.xml',
    checks: atom_feed_checks('Weeknotes', '/weeknotes/feed.xml') + [
      ['lists at least one entry', ->(xml) { xml.include?('<entry>') }],
    ],
  },
  {
    name: 'blog feed.xml',
    file: 'blog/feed.xml',
    checks: atom_feed_checks('Blog', '/blog/feed.xml'),
  },
].freeze

failures = 0

PAGES.each do |page|
  html = read(page[:file])

  if html.nil?
    puts "MISSING  #{page[:name]} (#{page[:file]})"
    failures += page[:checks].size
    next
  end

  page[:checks].each do |description, test|
    if test.call(html)
      puts "PASS  #{page[:name]}: #{description}"
    else
      puts "FAIL  #{page[:name]}: #{description}"
      failures += 1
    end
  end
end

total = PAGES.sum { |p| p[:checks].size }
puts "\n#{total - failures}/#{total} checks passed against #{BUILD_DIR}"
exit(failures.zero? ? 0 : 1)
