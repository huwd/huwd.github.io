require 'yaml'

COLLECTION_DIRS = %w[_books _reviews _blogs _weeknotes].freeze

def new_path_for(dir, filename)
  base = filename.sub(/\.md\z/, "")
  match = base.match(/\A(\d{4})-(\d{2})-(\d{2})-(.+)\z/)
  year, month, day, title = match ? match.captures : [nil, nil, nil, base]

  case dir
  when "_books", "_reviews"
    "/review/book/#{year}/#{month}/#{day}/#{title}/"
  when "_blogs"
    "/blog/#{year}/#{month}/#{day}/#{title}/"
  when "_weeknotes"
    "/weeknotes/#{base}/"
  end
end

redirects = COLLECTION_DIRS.flat_map do |dir|
  Dir.glob("#{dir}/*.md").flat_map do |file|
    frontmatter = File.read(file)[/\A---\s*\n(.*?)\n---/m, 1]
    data = YAML.safe_load(frontmatter || "", permitted_classes: [Time, Date], aliases: true) || {}
    old_paths = data["redirect_from"]
    next [] if old_paths.nil? || old_paths.empty?

    new_path = new_path_for(dir, File.basename(file))
    old_paths.map { |old_path| "#{old_path} #{new_path} 301" }
  end
end

OUTPUT_PATH = File.exist?("src") ? "src/_redirects" : "_redirects"

File.write(OUTPUT_PATH, redirects.join("\n") + "\n")
puts "Wrote #{redirects.size} redirects to #{OUTPUT_PATH}"
