require 'resque'
require_relative '../../lib/feeder/feeder'

desc 'Update all subscribed feeds'
task :update_feeder => :environment do
  feeder = Feeder.new
  feeder.update_feeds
end