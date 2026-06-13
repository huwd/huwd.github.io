Jekyll::Hooks.register :site, :post_read do |site|
  site.collections['books']&.docs&.each do |doc|
    doc.data['published'] = false if doc.content.strip.empty?
  end
end
