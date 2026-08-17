require "time"

module Builders
  # Restores two Jekyll filename conventions this content relies on that
  # Bridgetown doesn't replicate by default:
  #
  # - Resource::Base#date defaults to site.time (build time) when there's
  #   no explicit `date:` front matter, instead of falling back to the
  #   filename's date prefix like Jekyll does. 228 of 302 books have no
  #   date: field, so left alone every one of those would get today's
  #   date baked into its :year/:month/:day permalink - wrong URLs, and
  #   broken book_links/reading-list cross-links for anything that
  #   references the correct one.
  #
  # - The :title permalink placeholder slugifies data.title (the
  #   front-matter field), not the filename - Jekyll's :title placeholder
  #   is filename-based. Since every book has a title:, Bridgetown would
  #   always prefer it over the filename's hand-picked slug, and they
  #   often disagree (subtitles, punctuation, even a filename typo like
  #   "crack-up-captialism" vs the corrected title "Crack-Up Capitalism")
  #   - confirmed 9+ books would silently get different URLs. Setting
  #   data.slug explicitly makes the :slug placeholder (which :title falls
  #   back to, but only when data.title is absent) resolve to the
  #   filename instead; config/initializers.rb uses :slug, not :title,
  #   in the affected collections' permalinks.
  #
  # Runs before anything reads resource.date, since that method memoizes
  # data["date"] = site.time the first time it's called if unset -
  # checking data.key?("date") directly (not calling .date) avoids
  # triggering that fallback ourselves.
  class FilenameDerivedDefaults < SiteBuilder
    FILENAME_PATTERN = %r{(?:^|/)(\d{4}-\d{2}-\d{2})-([^/]*)\.[^.]+\z}

    def build
      hook :site, :post_read do |site|
        site.resources.each do |resource|
          match = FILENAME_PATTERN.match(resource.relative_path.to_s)
          next unless match

          resource.data.date = Time.parse(match[1]) unless resource.data.key?("date")
          resource.data.slug = match[2] unless resource.data.key?("slug")
        end
      end
    end
  end
end
