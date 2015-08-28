require_relative '../../lib/feeder/feeder'

desc 'Import inoreader.xml'
task :import_opml => :environment do
  feeder = Feeder.new
  feeder.import_opml_from("spec/fixtures/inoreader.xml")
end