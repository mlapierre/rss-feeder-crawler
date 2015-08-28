class StoreEntryHTMLJob
  @queue = :default

  def self.perform(id, url, title)
    log = Log4r::Logger["Feeder Mechanized"]
    log.info "Saving entry: #{title} (#{url})"
    agent = Mechanize.new
    agent.user_agent_alias = 'Windows Chrome'
    agent.log = log
    page_source = agent.get(url)
    if page_source.respond_to?('content') && 
      !page_source.content.to_s.empty? && 
       page_source.respond_to?('content_type') &&
       page_source.content_type.start_with?('text/html') 
      page = Page.new
      page.entry_id = id
      page.url = url
      page.title = title
      page_source.encoding = 'utf-8'
      page.content = page_source.content
      page.retrieved_at = Time.now
      page.save
    else
      log.warn "Unable to retrieve content of: #{url}"
    end
  end
end