require './config/boot'
require './config/environment'
require 'clockwork'
require_relative '../lib/feeder/feeder'
require_relative '../lib/feeder/jobs/update_feed_job'
require_relative '../lib/feeder/jobs/store_entry_html_job'

module Clockwork
  handler do |job|
    puts "Running #{job}"
  end

  every(1.hour, 'save_feeds') do
    feeder = Feeder::Feeder.new
    feeder.fetch_and_save_all_feeds
    feeder.compact('feeder')
    feeder.compact('feeder_html')
    feeder.compact('feeder_user')
  end
end
