Jekyll::Hooks.register :site, :post_read do |site|
  site.collections['books']&.docs&.each do |doc|
    has_review = !doc.content.strip.empty?
    doc.data['has_review'] = has_review
    doc.data['published']  = false unless has_review
  end
end
