module Builders
  # Books without review content get their own page skipped, but stay in
  # site.collections.books so reading.html can still list them (checking
  # has_review to decide whether to link).
  #
  # data.published = false looked like the obvious equivalent of Jekyll's
  # doc.data['published'] = false, but in Bridgetown that flag is checked
  # by Resource::Base#publishable?, which gates whether a resource is
  # added to the collection at all (Collection#add_resource_from_model) -
  # and that happens at read time, before any post_read hook can run, so
  # it wouldn't even take effect. The actual write-only gate is
  # data.config.output, checked independently by
  # Resource::Base#requires_destination? (aliased to #write?).
  class UnpublishEmptyBooks < SiteBuilder
    def build
      hook :site, :post_read do |site|
        site.collections["books"]&.resources&.each do |resource|
          has_review = !resource.content.to_s.strip.empty?
          resource.data.has_review = has_review
          resource.data.config = { "output" => false } unless has_review
        end
      end
    end
  end
end
