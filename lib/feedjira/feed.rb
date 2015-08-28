module Feedjira
  class Feed
    def self.feed_classes
      @feed_classes ||= [
        Feedjira::Parser::RSSFeedBurner,
        Feedjira::Parser::GoogleDocsAtom,
        Feedjira::Parser::AtomFeedBurner,
        Feedjira::Parser::Atom,
        Feedjira::Parser::RSS
      ]
    end
  end
end
