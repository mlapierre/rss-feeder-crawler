require 'json/ext'
require 'log4r'
require 'log4r/yamlconfigurator'
require 'log4r/outputter/datefileoutputter'
require 'feedjira'
#require "rss"
require 'byebug'
require 'couchrest'
require 'pp'
require 'zlib'
require 'rbzip2'
require 'tempfile'
#require 'msgpack'
require 'chronic'
require 'digest'
require 'base64'

require_relative 'feedjira/feed'
require_relative 'feeder/userfeed'
require_relative 'feeder/jobs/update_feed_job'
require_relative 'feeder/jobs/store_entry_html_job'

include Log4r

module Feeder
  class Feeder

    def initialize
      Log4r::YamlConfigurator.load_yaml_file("#{Dir.pwd}/config/log4r.yml")
      @log = Log4r::Logger["Feeder"]
      # FeedsHelper.log = @log
      # EntriesHelper.log = mech_log

      couch = CouchRest.new("http://#{ENV["FEEDERDB_1_PORT_5984_TCP_ADDR"]}:5984")
      @db = couch.database!('feeder')
      @userdb = couch.database!('feeder_user')
      @htmldb = couch.database!('feeder_html') # plain
      @feed_metadata = get_feed_metadata
    end

    def fetch_and_save_all_feeds
      @feed_metadata['feeds'].each do |feed|
        fetch_and_save_feed feed[0]
      end
    end

    def fetch_and_save_feed(link)
      # byebug
      # if @feed_metadata['feeds'][link]
      #   if Time.parse(@feed_metadata['feeds'][link]['last_modified']).utc >= Time.now.utc - 1*60*60
      #     @log.debug "Updated within an hour (at #{@feed_metadata['feeds'][link]['last_modified']}). Skipping #{link}"
      #     return
      #   end
      # end

      feed = fetch_feed link
      if !@feed_metadata['feeds'][link]
        @feed_metadata['feeds'][link] = {
          'last_modified' => (feed['last_modified'].is_a? String) ? Time.parse(feed['last_modified']).utc.iso8601 : feed['last_modified'].utc.iso8601
        }
      end

      articles = feed['articles']
      feed.delete('articles')
      save_feed feed
      articles.each do |article|
        save_article article, feed
        save_page article.url, @feed_metadata['feeds'][link] if should_save_article article
      end
      update_unread_count feed

      @db.save_doc(@feed_metadata)
    rescue Feedjira::NoParserAvailable => err
      @log.error err.message
      @log.error link
    end

    def fetch_and_save_page_from(link)
      feed = fetch_feed link
      articles = feed['articles']

      articles.each do |article|
        save_page article.url, @feed_metadata['feeds'][link]
      end
    end

    def fetch_and_save_feeds(feeds)
      feeds.each do |feed|
        fetch_and_save_feed(feed)
      end
    end

    def fetch_and_save_pages(feeds)
      feeds.each do |feed|
        fetch_and_save_page_from(feed)
      end
    end

    def fetch_feed(link)
      @log.info "Fetching: #{link}"
      feed = Feedjira::Feed.fetch_and_parse link
      @log.warn "Invalid feed. Request returned: #{feed.to_s}" if !feed.respond_to? :feed_url

      feed_id = 'feed_' + toPlainStr(feed.title) + '_' + feed.feed_url;
      feedref = toPlainStr(feed.title);

      doc = {
        '_id' => feed_id,
        'ref' => feedref,
        'type' => 'feed',
        'title' => feed.title,
        'description' => feed.description,
        'last_modified' => feed.last_modified,
        'feed_link' => feed.feed_url, #TODO check if the link found in the xml doesn't match the url
        'website_link' => feed.url,
        'articles' => feed.entries
      }
    rescue Feedjira::NoParserAvailable => err
      raise err
    end

    def get_feed_metadata
      tries ||= 0
      @db.get("feedmetadata")
    rescue RestClient::ResourceNotFound => err
      tries += 1
      doc = {
        '_id' => "feedmetadata",
        feeds: {}
      }
      @log.debug "Creating feed metadata doc"
      @db.save_doc(doc)
      retry unless tries >= 3
      raise err
    end

    def get_rand_str(num)
      range = [*'0'..'9',*'A'..'Z',*'a'..'z']
      Array.new(num){ range.sample }.join
    end

    def get_article_id(article)
      id = "article_#{article.url}"
      if id.length == 8
        id = "#{id}_#{article.title}"
      end
      if id.length == 8
        id+= "#{id}_#{article.summary[0,200]}"
      end
      id
    end

    def get_unread_count(feedref)
      read = @userdb.view('feeder/article_read_count', {startkey: "article_#{feedref}", endkey: "article_#{feedref}\uffff"})['rows']
      read_count = (read.size > 0) ? read.first['value'] : 0
      articles = @db.view('feeder/article_count', {startkey: [feedref, "article_"], endkey: [feedref, "article_\uffff"]})['rows']
      article_count = (articles.size > 0) ? articles.first['value'] : 0
      article_count - read_count
    end

    def save_article(article, feed)
      tries ||= 0
      doc = @db.get(get_article_id(article))
      doc_last_modified = Chronic.parse(doc['last_modified'] || Time.at(0).iso8601).utc
      article_last_modified = (article['updated'] || article['published']).utc
      if article_last_modified <= doc_last_modified
        @log.debug "Article up to date: #{article.title}"
        return
      end

      # if Time.parse(doc['last_modified'] || Time.at(0).iso8601).utc + 1*60*60 > Time.now.utc
      #   @log.debug "Updated within an hour (at #{doc['last_modified']}). Skipping article: #{article.url}"
      #   return
      # end
      if Time.parse(doc['last_fetched'] || Time.at(0).iso8601).utc + 1*60*60 > Time.now.utc
        @log.debug "Updated within an hour (at #{doc['last_fetched']}). Skipping article: #{article.url}"
        return
      end

      doc['title'] = article.title
      doc['summary'] = article.summary
      doc['content'] = article.content
      doc['published_at'] = article.published.utc.iso8601
      doc['last_modified'] = article_last_modified.iso8601
      doc['last_fetched'] = Time.now.utc.iso8601
      doc['link'] = article.url
      doc['guid'] = article.entry_id
      doc['author'] = article.author
      doc['image'] = article.image
      doc['categories'] = article.categories

      response = @db.save_doc(doc)
      @log.debug "#{'Update ok' if response['ok']} Article: #{doc['title']}"
    rescue RestClient::ResourceNotFound => err
      tries += 1
      doc = {
        '_id' => get_article_id(article),
        'id' => get_rand_str(32),
        'feed_id' => feed['_id'],
        'feed_ref' => feed['ref'],
        'type' => 'article'
      }
      doc = @db.save_doc(doc)
      @log.debug "Insert ok" if doc['ok']
      retry unless tries >= 3
      raise err
    end

    def save_feed(feed)
      #CouchRest.put("http://#{ENV["FEEDERDB_1_PORT_5984_TCP_ADDR"]}:5984/feeder/_design/feeder/_update/in_place/#{id}", feed, {raw: true})
      response = update(feed)
      @log.info "#{response.body} Feed: #{feed['title']}"
    end

    def save_page(link, metadata)
      tries ||= 0
      page = @htmldb.get(link)

      if page['last_fetched'] && Time.parse(page['last_fetched']).utc + 1*60*60 > Time.now.utc
        @log.debug "Updated within an hour (at #{page['last_fetched']}). Skipping page: #{link}"
        return
      end

      if metadata['disallow'].to_s.empty?
        metadata['disallow'] = []
      end

      method = (metadata['disallow'].include? 'HEAD') ? :get : :head
      headers = { "User-Agent" => "Mozilla/5.0 (Windows NT 10.0; WOW64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/44.0.2403.155 Safari/537.36" }
      response = RestClient::Request.execute(method: method, url: link, headers: headers)

      saved_page_last_modified = parse_utc(page['last_modified'])
      page_last_modified = parse_utc(response.headers[:last_modified] || response.headers[:expires] || Time.now.to_s)

      if saved_page_last_modified && page_last_modified <= saved_page_last_modified
        @log.debug "Page up to date: #{link}"
        return
      end

      response = RestClient::Request.execute(method: :get, url: link, headers: headers) if method == :head
      page['last_modified'] = page_last_modified.iso8601
      page['last_fetched'] = Time.now.utc.iso8601
      @log.debug "Saving page metadata: #{link}"
      @htmldb.save_doc(page)

      attachment = @htmldb.fetch_attachment(page, link) if page['_attachments']

      if !attachment || Digest::MD5.base64digest(attachment) != Digest::MD5.base64digest(response.body)
        @log.debug "Saving page content: #{link}"
        @htmldb.put_attachment(page, link, response.body, content_type: "text/html")
      end

    rescue RestClient::ResourceNotFound => err
      tries += 1
      doc = {
        '_id' => link,
        'type' => 'webpage'
      }
      @htmldb.save_doc(doc)
      retry unless tries >= 3
      @log.error err.message
    rescue RestClient::MethodNotAllowed, RestClient::Forbidden, RestClient::ServerBrokeConnection, RestClient::Unauthorized => err
      tries += 1
      @log.warn err.message
      @log.warn "Method: #{method}, url: #{link}"
      metadata['disallow'] << method.to_s.upcase
      #method = :get
      retry unless tries >= 3
      @log.error err.message
    rescue StandardError => err
      @log.error err.class.to_s
      @log.error err.message
    end

    def add_untagged(feed, unread_count)
      tries ||= 0
      untagged = @userdb.get("tag_untagged")
      feed['unread_count'] = unread_count
      untagged['feeds'] << feed
      @userdb.save_doc(untagged)
    rescue RestClient::ResourceNotFound => err
      tries += 1
      untagged = {
        '_id' => 'tag_untagged',
        'feeds' => []
      }
      @userdb.save_doc(untagged)
      retry unless tries >= 3
      raise err
    end

    def update_unread_count(feed)
      unread_count = get_unread_count feed['ref'] #user
      tagged = false
      data = @userdb.view('feeder/tags', include_docs: true)
      data['rows'].each do |row|
         row['doc']['feeds'].each do |_feed|
           if feed['ref'] == _feed['ref']
             tagged = true
             _feed['unread_count'] = unread_count
             @userdb.save_doc(row['doc'])
           end
         end
      end
      add_untagged feed, unread_count if !tagged
    end

    def compact(db)
      response = RestClient::Request.execute({
        url: "http://#{ENV["FEEDERDB_1_PORT_5984_TCP_ADDR"]}:5984/#{db}/_compact",
        method: :post,
        headers: {
          content_type: :json,
          accept: :json
        }
      })
      if !JSON.parse(response)['ok']
        @log.error response
      else
        @log.info "Database '#{db}' compacted"
      end
    end

    def parse_time(time)
      Time.parse(time)
    rescue ArgumentError, TypeError
      Chronic.parse(time)
    end

    def parse_utc(time)
      time = parse_time(time)
      return time.utc if time
      return nil
    end

    def should_save_article(article)
      true unless /\.mp3$/ =~ article.url
    end

    def toPlainStr(str)
      #encodeURIComponent(str.replace(/[\s\W]/g, '').toLowerCase());
      encode_uri_component(str).gsub(/[\s\W]/, '').downcase
    end

    def update(doc)
      id = URI.escape(doc['_id'], Regexp.new("[^#{URI::PATTERN::UNRESERVED}]"))
      RestClient::Request.execute({
        url: "http://#{ENV["FEEDERDB_1_PORT_5984_TCP_ADDR"]}:5984/feeder/_design/feeder/_update/in_place/#{id}",
        method: :put,
        payload: MultiJson.encode(doc),
        headers: {
          content_type: :json,
          accept: :json
        }
      })
    end

    def update_feeds
      # TODO allow update frequency to be restricted
      @log.info "Queuing feeds..."
      Feed.find_each.with_index do |feed, index|
        @log.debug "Queuing: #{feed.title} [#{index+1}/#{Feed.count}]"
        async_update_feed(feed.id)
      end
      @log.info "All feeds queued"
    end

    def async_update_feed(feed_id)
      Resque.enqueue(UpdateFeedJob, feed_id)
    end

    def encode_uri_component(str)
      URI.escape(str, Regexp.new("[^#{URI::PATTERN::UNRESERVED}]"))
    end

    def import_opml_from(file)
      @log.info "Importing opml: #{file}"
      FeedsHelper.import_opml_from(file)
    end

  end
end
