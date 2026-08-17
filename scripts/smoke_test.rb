require 'json'

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

# Shared feature checks any "post-like" page (book, review, weeknote) should pass.
def post_checks
  [
    ['renders an <article class="post">', ->(html) { has?(html, '<article class="post">') }],
    ['renders a title in <h1>', ->(html) { has?(html, /<h1>[^<]+<\/h1>/) }],
    ['renders a dated <time> element', ->(html) { has?(html, /<time datetime="[^"]+">/) }],
    ['includes SEO canonical link', ->(html) { has?(html, /<link rel="canonical" href="[^"]+"\s*\/>/) }],
  ]
end

def listing_checks(title_text)
  [
    ["title includes \"#{title_text}\"", ->(html) { has?(html, "<title>") && has?(html, title_text) }],
    ['renders inside <section class="listing">', ->(html) { has?(html, '<section class="listing">') }],
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
    ],
  },
  {
    name: 'reading index',
    file: 'reading/index.html',
    checks: listing_checks('Reading') + [
      ['shows a running book total', ->(html) { has?(html, /\(\d+ books total/) }],
      ['renders star ratings', ->(html) { has?(html, '★') }],
    ],
  },
  {
    name: "reading/#{CURRENT_YEAR} (current year, from navigation.json)",
    file: "reading/#{CURRENT_YEAR}/index.html",
    checks: listing_checks("What I read in #{CURRENT_YEAR}") + [
      ['book-nav marks the current year active', ->(html) { has?(html, /class="active" href="\/reading\/#{CURRENT_YEAR}"/) }],
    ],
  },
  {
    name: 'projects',
    file: 'projects/index.html',
    checks: listing_checks("Things I've made") + [
      ['renders the project box', ->(html) { has?(html, 'class="project-box"') }],
      ['links out to at least one project', ->(html) { has?(html, /class="project"/) }],
    ],
  },
  {
    name: 'blog listing',
    file: 'blog/index.html',
    checks: listing_checks('Blog'),
  },
  {
    name: 'reviews listing',
    file: 'reviews/index.html',
    checks: listing_checks("Things I've reviewed") + [
      ['lists at least one entry', ->(html) { has?(html, /<time datetime="[^"]+">/) }],
    ],
  },
  {
    name: 'book page (Whale)',
    file: 'review/book/2026/08/17/whale/index.html',
    checks: post_checks + [
      ['shows the book title', ->(html) { has?(html, 'Whale') }],
      ['shows read/reviewed meta', ->(html) { has?(html, 'Read:') && has?(html, 'Reviewed:') }],
      ['renders book-to-book navigation', ->(html) { has?(html, 'book-nav-group') }],
    ],
  },
  {
    name: 'multi-book review (The Karla Trilogy)',
    file: 'review/book/2025/11/25/the-karla-trilogy/index.html',
    checks: post_checks + [
      ['shows the review title', ->(html) { has?(html, 'Karla Trilogy') }],
      ['renders book-to-book navigation for each reviewed book', ->(html) { has?(html, 'book-nav-group') }],
    ],
  },
  {
    name: 'weeknote',
    file: 'weeknotes/2021-04-12-weeknotes-to-recently/index.html',
    checks: post_checks,
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
