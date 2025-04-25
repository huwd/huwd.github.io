require 'json'
require 'fileutils'
require 'yaml'

SRC  = '_data/books.json'
DEST = '_books'

def slugify(str)
  str.to_s.downcase.gsub(/['`]/, '').gsub(/\W+/, '-').gsub(/^-|-$/, '')
end

FileUtils.mkdir_p(DEST)
entries = JSON.parse(File.read(SRC))['entries'] || []

entries.each do |book|
  date = (book['date_started'].to_s.empty? ? '0000-00-00' : book['date_started'])[0,10]
  slug = slugify(book['title'])
  filename = "#{date}-#{slug}.md"
  path = File.join(DEST, filename)

  yaml = book.to_yaml.sub(/\A---\s*\n/, '')  # strip one leading --- if present
  File.write(path, +"---\n#{yaml}---\n\n")
  puts "→ wrote #{path}"
end
