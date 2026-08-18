require 'yaml'
require 'time'

COLLECTION_DIRS = %w[src/_books src/_reviews src/_blogs src/_weeknotes].freeze

# :year/:month/:day permalinks (books/reviews/blogs) are built from
# resource.date, which resolves front matter `date:` if present - NOT the
# filename - falling back to the filename-derived date only when `date:` is
# absent (see plugins/builders/filename_derived_defaults.rb, which applies
# that exact fallback before anything else reads resource.date). Using the
# filename unconditionally here silently drifts out of sync with the real
# permalink whenever a book's `date:` differs from its filename (e.g. it was
# updated after the file was created) - confirmed against production: 3 of
# 5 existing redirects pointed at a destination that 404s, because the real
# page had moved to a different date than its filename implied.
def new_path_for(dir, filename, data)
  base = filename.sub(/\.md\z/, "")
  match = base.match(/\A(\d{4})-(\d{2})-(\d{2})-(.+)\z/)
  filename_year, filename_month, filename_day, title = match ? match.captures : [nil, nil, nil, base]

  if data["date"]
    date = data["date"].is_a?(String) ? Time.parse(data["date"]) : data["date"]
    year, month, day = date.strftime("%Y-%m-%d").split("-")
  else
    year, month, day = filename_year, filename_month, filename_day
  end

  case dir
  when "src/_books", "src/_reviews"
    "/review/book/#{year}/#{month}/#{day}/#{title}/"
  when "src/_blogs"
    "/blog/#{year}/#{month}/#{day}/#{title}/"
  when "src/_weeknotes"
    "/weeknotes/#{base}/"
  end
end

redirects = COLLECTION_DIRS.flat_map do |dir|
  Dir.glob("#{dir}/*.md").flat_map do |file|
    frontmatter = File.read(file)[/\A---\s*\n(.*?)\n---/m, 1]
    data = YAML.safe_load(frontmatter || "", permitted_classes: [Time, Date], aliases: true) || {}
    old_paths = data["redirect_from"]
    next [] if old_paths.nil? || old_paths.empty?

    new_path = new_path_for(dir, File.basename(file), data)
    old_paths.map { |old_path| "#{old_path} #{new_path} 301" }
  end
end

OUTPUT_PATH = File.exist?("src") ? "src/_redirects" : "_redirects"

File.write(OUTPUT_PATH, redirects.join("\n") + "\n")
puts "Wrote #{redirects.size} redirects to #{OUTPUT_PATH}"
