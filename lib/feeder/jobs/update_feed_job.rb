class UpdateFeedJob
  @queue = :default

  def self.perform(feed_id)
    feed = Feed.find(feed_id)
    feed_source = FeedsHelper.fetch_feed_source(feed.feed_link)
    return if !feed_source.respond_to? :feed_url #TODO more appropriate error handling

    # TODO don't bother processing the entries if the feed hasn't been updated since last fetched
    EntriesHelper.save_from(feed_source, feed)
  end
end