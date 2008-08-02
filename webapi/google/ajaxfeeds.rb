# = Google AJAX Feeds API class
#
# Author::  Chihiro Ito
# License:: New BSD License
# Support:: http://groups.google.com/group/webos-goodies/
#
# This file contains WebAPI::Google::AjaxFeeds class which allows you to
# get / find any RSS / ATOM feeds easily.

require 'webapi/rest'
require 'webapi/json'

module WebAPI
  module Google
    class AjaxFeeds

      class LoadResponse

        class FeedEntry
          def initialize(data)
            @data  = data
            @title = (@data['title']||'').to_s
            @link  = (@data['link']||'').to_s
          end
          def published_date()  @date||(@date=Util.parse_time_rfc2822(@date['publishedDate']))  end
          def content()         @content        ||(@content        =(@data['content']       ||'').to_s) end
          def content_snippet() @content_snippet||(@content_snippet=(@data['contentSnippet']||'').to_s) end
          def categories()      @categories     ||(@categories     = @data['categories']    ||[])       end
          attr_reader :title, :link
        end

        include Enumerable

        def initialize(data)
          @response_details = (data['responseDetails']||'').to_s
          @response_status  = data['responseStatus']
          @title            = ''
          @link             = ''
          @description      = ''
          @author           = ''
          @entries          = []
          response_data     = data['responseData']
          if @response_status == 200 && Hash === response_data
            feed = response_data['feed']
            if Hash === feed
              @title       = (feed['title']      ||'').to_s
              @link        = (feed['link']       ||'').to_s
              @description = (feed['description']||'').to_s
              @author      = (feed['author']     ||'').to_s
              entries      = feed['entries']
              entries.each{|e|
                @entries << FeedEntry.new(e)
              } if Array === entries
            end
          end
        end
        def each(&block) if @entries then @entries.each(&block) end ; self end
        def valid?() @response_status==200 end
        def empty?() @entries.empty? end
      end

      def self.load(url, params = {})
        raise ArgumentError.new('The second argument must be a hash.') if params && !(Hash === params)
        params   = { 'q' => url, 'v' => '1.0' }.update(params||{})
        json     = REST.new(REST.http('ajax.googleapis.com')).get('/ajax/services/feed/load', params)
        LoadResponse.new(JsonParser.new.parse(json))
      end

    end
  end
end
