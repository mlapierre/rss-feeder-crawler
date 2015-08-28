require 'resque'

require_relative 'lib/feeder'
require_relative 'feedlist'

desc 'Save feeds'
task :save_feeds do
  feeder = Feeder::Feeder.new
  feedlist = Feedlist.new.Feeds
  feeder.fetch_and_save_all_feeds
  #feeder.fetch_and_save_feeds feedlist
  #feeder.fetch_and_save_feeds feedlist[0,5]
  #feeder.fetch_and_save_feeds ["http://www.androidpolice.com/topics/applications-games/feed/"]
  #feeder.fetch_and_save_feeds ["http://www.bbc.co.uk/programmes/b015sqc7/episodes/downloads.rss"]
  #feeder.fetch_and_save_feed "http://www.engadget.com/rss.xml"
  #feeder.fetch_and_save_feed "https://theconversation.com/articles.atom"
  #feeder.fetch_and_save_feed "http://feeds.feedburner.com/blogspot/hsDu"
  #feeder.fetch_and_save_feed "http://feeds.feedburner.com/alistapart/main"
  feeder.compact('feeder')
  feeder.compact('feeder_html')
  feeder.compact('feeder_user')
end

desc 'Save feedlist'
task :save_feedlist do
  feeder = Feeder::Feeder.new
  feedlist = Feedlist.new.Feeds
  feeder.fetch_and_save_feeds feedlist
  feeder.compact('feeder')
  feeder.compact('feeder_html')
  feeder.compact('feeder_user')
end
