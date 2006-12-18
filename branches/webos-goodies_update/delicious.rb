# del.icio.us API class

require 'time'
require 'rexml/document'
require 'webapi/rest'
require 'webapi/json'

module WebAPI

  class Delicious

    module Util
      private
      def str(s)
        s ? s.to_s : ''
      end
      def array(a)
        case a
        when String
          a.split(' ')
        when NilClass
          []
        else
          a.to_a
        end
      end
      def integer(n)
        n ? n.to_i : 0
      end
    end

    class Post
      include Util
      def initialize(src = nil)
        set(src)
      end
      def set(src)
        case src
        when Hash
          @title = str(src['d'])
          @url   = str(src['u'])
          @note  = str(src['n'])
          @tags  = array(src['t'])
          @date  = nil
        when REXML::Element
          @title = str(src.attributes['description'])
          @url   = str(src.attributes['href'])
          @note  = str(src.attributes['extended'])
          @tags  = array(src.attributes['tag'])
          @date  = nil
          if src.attributes['time']
            @date = Time.iso8601(src.attributes['time'])
          end
        when NilClass
          @title = @url = @note = @tags = @date  = nil
        else
          raise
        end
      end
      attr_accessor :title, :url, :note, :tags, :date
    end

    class Tag
      include Util
      def initialize(arg1 = nil, arg2 = nil)
        set(arg1, arg2)
      end
      def set(arg1 = nil, arg2 = nil)
        if arg2
          @name  = str(arg1)
          @count = integer(arg2)
        else
          case arg1
          when Array
            @name  = str(arg1[0])
            @count = integer(arg2[1])
          when REXML::Element
            @name  = str(arg1.attributes['tag'])
            @count = integer(arg1.attributes['count'])
          when NilClass
            @name  = ''
            @count = 0
          else
            raise
          end
        end
      end
      attr_accessor :name, :count
    end

    class LimiterBase
      def execute()
        yield
      end
    end

    class ApiLimitter < LimiterBase
      def initialize(interval = 1.5)
        @interval = interval
        @release_time = Time.now
      end
      def execute()
        now = Time.now
        sleep(@release_time - now) if now < @release_time
        result = super
        @release_time = Time.now + @interval
        result
      end
    end

    DefaultLimiter = ApiLimitter.new
    NullLimiter    = LimiterBase.new

    def initialize(username, password = nil, limiter = nil)
      @limiter  = limiter
      @username = username.to_s
      if password
        protocol  = REST.https('api.del.icio.us')
        auth      = REST.basic_auth(username, password);
        @api_mode = true
        @limiter  = DefaultLimiter unless @limiter
      else
        protocol  = REST.http('del.icio.us')
        auth      = nil
        @api_mode = false
        @limiter  = NullLimiter unless @limiter
      end
      @rest     = REST.new(protocol, auth)
    end

    def get_posts(opt = {})
      @api_mode ? get_posts_api(opt) : get_posts_json(opt)
    end

    def get_tags()
      @api_mode ? get_tags_api() : get_tags_json()
    end

    private #---------------------------------------------------------

    def http_get(url, params = {})
      @limiter.execute do @rest.get(url, params) end
    end

    def get_posts_api(opt = {})
      params = {}
      params['tag'] = opt['tags'].join(' ') if opt['tags']
      doc = REXML::Document.new(http_get('/v1/posts/all', params))
      posts = []
      doc.elements.each('posts/post') do |element|
        posts << Post.new(element)
      end
      posts
    end

    def get_posts_json(opt)
      tags = opt['tags'] ? '/' + opt['tags'].join(' ') : ''
      count = opt['count'] ? opt['count'] : 100
      url = '/feeds/json/' + @rest.urlencode(@username + tags)
      params = { 'count' => count, 'raw' => '' }
      Json.new.parse(http_get(url, params)).map! do |post|
        Post.new(post)
      end
    end

    def get_tags_api()
      doc = REXML::Document.new(http_get('/v1/tags/get'))
      tags = []
      doc.elements.each('tags/tag') do |element|
        tags << Tag.new(element)
      end
      tags
    end

    def get_tags_json()
      url = '/feeds/json/tags/' + @rest.urlencode(@username)
      params = { 'atleast' => 1, 'raw' => '' }
      json = Json.new.parse(http_get(url, params))
      result = []
      json.each do |key, value|
        result << Tag.new(key, value)
      end
      result
    end

  end

end
