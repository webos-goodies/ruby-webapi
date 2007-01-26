# del.icio.us API class

require 'time'
require 'rexml/document'
require 'webapi/rest'
require 'webapi/json'

module WebAPI

  class Delicious

    module Util
      private
      def to_str(s)
        s ? s.to_s : ''
      end
      def to_tags(a)
        case a
        when String
          a.split(' ')
        when NilClass
          []
        else
          a.to_a
        end
      end
      def to_integer(n)
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
          @title = src['d']
          @url   = src['u']
          @notes = src['n']
          @tags  = src['t']
          @date  = nil
        when REXML::Element
          @title = src.attributes['description']
          @url   = src.attributes['href']
          @notes = src.attributes['extended']
          @tags  = src.attributes['tag']
          @date  = src.attributes['time']
        when NilClass
          @title = @url = @notes = @tags = @date  = nil
        else
          raise
        end
        normalize!
      end
      def normalize!
        @title = to_str(@title)
        @url   = to_str(@url)
        @notes = to_str(@notes)
        @tags  = to_tags(@tags)
        @date = case @date
                when Time
                  @date
                when NilClass
                  Time.now
                else
                  Time.iso8601(@date.to_s)
                end
        self
      end
      def normalize
        clone.normalize!
      end
      attr_accessor :title, :url, :notes, :tags, :date
    end

    class Tag
      include Util
      def initialize(arg1 = nil, arg2 = nil)
        set(arg1, arg2)
      end
      def set(arg1, arg2 = nil)
        if arg2
          @name  = to_str(arg1)
          @count = to_integer(arg2)
        else
          case arg1
          when Array
            @name  = to_str(arg1[0])
            @count = to_integer(arg2[1])
          when REXML::Element
            @name  = to_str(arg1.attributes['tag'])
            @count = to_integer(arg1.attributes['count'])
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

    class Bundle
      include Util
      def initialize(src = nil)
        set(src)
      end
      def set(src)
        if src
          @name = src.attributes['name']
          @tags = src.attributes['tags']
        else
          @name = @tags = nil
        end
        normalize!
      end
      def normalize!
        @name = to_str(@name)
        @tags = to_tags(@tags)
        self
      end
      def normalize
        clone.normalize!
      end
      attr_accessor :name, :tags
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

    def add_post(post, replace = true, shared = true)
      raise unless @api_mode
      post = post.normalize
      params = {
        'url' => post.url,
        'description' => post.title,
        'extended' => post.notes,
        'dt' => post.date.iso8601 }
      params['tags'] = post.tags.join(' ') if post.tags.size > 0
      params['replace'] = 'no' unless replace
      params['shared'] = 'no' unless shared
      doc = REXML::Document.new(http_post('/v1/posts/add', params))
      doc.root.attributes['code']
    end

    def delete_post(url)
      raise unless @api_mode
      params = { 'url' => (url.is_a?(Post) ? url.url : url.to_s) }
      doc = REXML::Document.new(http_post('/v1/posts/delete', params))
      doc.root.attributes['code']
    end

    def get_tags()
      @api_mode ? get_tags_api() : get_tags_json()
    end

    def get_bundles()
      raise unless @api_mode
      doc = REXML::Document.new(http_get('/v1/tags/bundles/all'))
      bundles = []
      doc.elements.each('bundles/bundle') do |element|
        bundles << Bundle.new(element)
      end
      bundles
    end

    private #---------------------------------------------------------

    def http_get(url, params = {})
      @limiter.execute { @rest.get(url, params) }
    end

    def http_post(url, params = {})
      @limiter.execute { @rest.post(url, params) }
    end

    def get_posts_api(opt = {})
      params = {}
      params['tag'] = opt['tags'].join(' ') if opt['tags']
      params['url'] = opt['url']
      response =
        if params['url']
          http_get('/v1/posts/get', params)
        else
          http_get('/v1/posts/all', params)
        end
      doc = REXML::Document.new(response)
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
