require 'net/http'
require 'json'
require 'uri'
require 'date'

ABSRecord = Struct.new(
  :abs_id,
  :title,
  :subtitle,
  :authors,           # Array<String>
  :narrators,         # Array<String>
  :publisher,
  :published_date,    # Date or nil (note: ABS field is named publishedYear but contains full ISO date)
  :asin,
  :duration_seconds,  # Integer or nil — media.duration from ABS
  :genres,            # Array<String> — colon-delimited category paths from Audible
  :series,            # Array<String>
  keyword_init: true
)

ABSInProgressItem = Struct.new(
  :record,       # ABSRecord
  :progress,     # Float 0.0–1.0
  :started_at,   # Time or nil
  :last_update,  # Time or nil
  keyword_init: true
)

class ABSClient
  def initialize
    # ABS_TOKEN_FILE env var contains the JWT directly (not a file path — naming quirk)
    @token   = ENV.fetch("ABS_TOKEN_FILE")
    @base    = ENV.fetch("ABS_URL")
    @lib_id  = ENV.fetch("ABS_LIBRARY_ID")
  end

  # Returns all library items with progress > 0 and isFinished = false.
  def in_progress
    uri = URI("#{@base}/api/me/items-in-progress")
    res = Net::HTTP.start(uri.host, uri.port) do |http|
      req = Net::HTTP::Get.new(uri)
      req["Authorization"] = "Bearer #{@token}"
      http.request(req)
    end
    raise "ABS error #{res.code}: #{res.body[0, 200]}" unless res.is_a?(Net::HTTPSuccess)

    items = JSON.parse(res.body).fetch("libraryItems", [])
    items.filter_map { |item| parse_in_progress_item(item) }
  end

  # Search the ABS library and return all hits that pass author filtering.
  # Returns nil when nothing matches, an ABSRecord when confident.
  def find(title, authors: [])
    candidates = search(title)
    return nil if candidates.empty?

    if authors.any?
      scored = candidates.map { |c| [c, author_overlap(c.authors, authors)] }
                         .select { |_, score| score > 0 }
                         .sort_by { |_, score| -score }
      return nil if scored.empty?
      # Ambiguous only if two candidates have identical overlap AND titles are close
      scored.first.first
    else
      candidates.first
    end
  end

  private

  def search(query, limit: 5)
    uri = URI("#{@base}/api/libraries/#{@lib_id}/search")
    uri.query = URI.encode_www_form(q: query, limit: limit)

    res = Net::HTTP.start(uri.host, uri.port) do |http|
      req = Net::HTTP::Get.new(uri)
      req["Authorization"] = "Bearer #{@token}"
      http.request(req)
    end

    raise "ABS error #{res.code}: #{res.body[0, 200]}" unless res.is_a?(Net::HTTPSuccess)

    JSON.parse(res.body).fetch("book", []).map { |item| parse_item(item) }
  end

  def parse_in_progress_item(item)
    media = item["media"] || {}
    meta  = media["metadata"] || {}
    return nil if meta.empty?

    last_update   = ms_to_time(item["progressLastUpdate"])
    progress_data = fetch_progress(item["id"]) || {}
    return nil if progress_data["isFinished"]

    record = ABSRecord.new(
      abs_id:           item["id"],
      title:            meta["title"],
      subtitle:         meta["subtitle"],
      authors:          split_names(meta["authorName"]),
      narrators:        split_names(meta["narratorName"]),
      publisher:        meta["publisher"],
      published_date:   parse_date(meta["publishedYear"] || meta["publishedDate"]),
      asin:             meta["asin"],
      duration_seconds: media["duration"]&.to_i,
      genres:           Array(meta["genres"]),
      series:           meta["seriesName"].to_s.strip.empty? ? [] : [meta["seriesName"].strip]
    )

    ABSInProgressItem.new(
      record:      record,
      progress:    progress_data["progress"].to_f,
      started_at:  ms_to_time(progress_data["startedAt"]) || last_update,
      last_update: last_update
    )
  end

  def fetch_progress(item_id)
    uri = URI("#{@base}/api/me/progress/#{item_id}")
    res = Net::HTTP.start(uri.host, uri.port) do |http|
      req = Net::HTTP::Get.new(uri)
      req["Authorization"] = "Bearer #{@token}"
      http.request(req)
    end
    return nil unless res.is_a?(Net::HTTPSuccess)
    JSON.parse(res.body)
  rescue StandardError
    nil
  end

  def split_names(str)
    return [] if str.nil? || str.strip.empty?
    str.split(/,\s*/).map(&:strip).reject(&:empty?)
  end

  def ms_to_time(ms)
    return nil unless ms
    Time.at(ms / 1000.0).utc
  end

  def parse_item(item)
    meta = item.dig("libraryItem", "media", "metadata")
    ABSRecord.new(
      abs_id:           item.dig("libraryItem", "id"),
      title:            meta["title"],
      subtitle:         meta["subtitle"],
      authors:          Array(meta["authors"]).map { |a| a["name"] },
      narrators:        Array(meta["narrators"]),
      publisher:        meta["publisher"],
      published_date:   parse_date(meta["publishedYear"]),
      asin:             meta["asin"],
      duration_seconds: item.dig("libraryItem", "media", "duration")&.to_i,
      genres:           Array(meta["genres"]),
      series:           Array(meta["series"]).filter_map { |s| s["name"] }
    )
  end

  def parse_date(val)
    return nil if val.nil? || val.strip.empty?
    Date.parse(val)
  rescue ArgumentError
    year = val.strip.to_i
    year > 0 ? Date.new(year, 1, 1) : nil
  end

  def author_overlap(abs_authors, query_authors)
    norm   = ->(s) { s.to_s.unicode_normalize(:nfd).gsub(/\p{Mn}/, '').downcase.gsub(/[^a-z0-9]/, '') }
    abs_n  = abs_authors.map(&norm).to_set
    query_n = query_authors.map(&norm)
    query_n.count { |a| abs_n.include?(a) }
  end
end
