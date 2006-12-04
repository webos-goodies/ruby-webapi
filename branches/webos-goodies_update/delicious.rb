# del.icio.us API class

require 'webapi/rest'
require 'webapi/json'

module WebAPI

  class Delicious

    class Post
      def initialize(src = nil)
        set(src)
      end
      def set(src)
        case src
        when Hash
          @title = src['d'].to_s
          @url   = src['u'].to_s
          @note  = src['n'].to_s
          @tags  = src['t'].to_a
          @date  = nil
        when NilClass, FalseClass
          @title = nil
          @url   = nil
          @note  = nil
          @tags  = nil
          @date  = nil
        else
          raise
        end
      end
      attr_accessor :title, :url, :note, :tags, :date
    end

    class Tag
      def initialize(arg1 = nil, arg2 = nil)
        set(arg1, arg2)
      end
      def set(arg1 = nil, arg2 = nil)
        if arg2
          @name  = arg1.to_s
          @count = arg2.to_i
        else
          case arg1
          when Array
            @name  = arg1[0].to_s
            @count = arg2[1].to_i
          when NilClass, FalseClass
            @name  = ''
            @count = 0
          else
            raise
          end
        end
      end
      attr_accessor :name, :count
    end

    def url_escape(src)
      src
    end

    def initialize(username, password = nil)
      if(password)
        protocol  = REST.https('api.del.icio.us')
        auth      = REST.basic_auth(username, password);
      else
        protocol  = REST.http('del.icio.us')
        auth      = nil
      end
      @username = username.to_s
      @rest     = REST.new(protocol, auth)
    end

    def posts(max_length, *tags)
      url = '/feeds/json/' + @rest.urlencode(@username + '/' + tags.join(' '))
      params = { 'count' => max_length, 'raw' => '' }
      response = @rest.get(url, params)
      json = Json.new.parse(response)
      json.map! do |post|
        Post.new(post)
      end
    end

    def tags(threshold = 1, max_length = nil)
      url = '/feeds/json/tags/' + @rest.urlencode(@username)
      params = { 'atleast' => threshold, 'raw' => '' }
      params['count'] = max_length if max_length
      response = @rest.get(url, params)
      json = Json.new.parse(response)
      result = []
      json.each do |key, value|
        result << Tag.new(key, value)
      end
      result
    end

  end

end
