desc 'Update the unread count for each feed'
task :update_unread => :environment do
  FeedsHelper.updateUnreadCount
end

