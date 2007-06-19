# = del.icio.us API class
#
# Author::  Chihiro Ito
# License:: New BSD License
# Support:: http://groups.google.com/group/webos-goodies/
#
# This file contains WebAPI::Delicious class which allows you to access and
# manipulate your del.icio.us bookmarks easily.

require 'time'
require 'rexml/document'
require 'webapi/rest'
require 'webapi/json'

module WebAPI

  # This class allows you to access and manipulate your del.icio.us
  # bookmarks through JSON feed or del.icio.us API. If you provides
  # your password to constructor, WebAPI::Delicious uses del.icio.us
  # API to get full access to your all bookmarks. otherwise, It  uses
  # JSON feed to obtain your public bookmarks.
  class Delicious

    include Util

    #:stopdoc:
    class LimiterBase
      def execute()
        yield
      end
    end

    class ApiLimiter < LimiterBase
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

    DefaultLimiter = ApiLimiter.new
    NullLimiter    = LimiterBase.new
    #:startdoc:

    # Create an instance of WebAPI::Delicious.
    # [username]
    #     Required. The login name of your del.icio.us account.
    # [password]
    #     Optional. The password of your del.icio.us account.
    #     If you omit this argument, WebAPI::Delicious will use
    #     JSON feed for query. In this case, you can access only
    #     your public bookmarks, and some methods are not available.
    # [limiter]
    #     Optional. An object for managing interval of each request.
    #     del.icio.us API client must wait at least one second
    #     between queries or your IP address is going to be banned.
    #     If you omit this argument, an appropriate object would be
    #     selected automatically. See LimiterBase for details.
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

    def add_post(post, replace = true, shared = true)
      raise unless @api_mode
      params = {
        'url'         => string_param(post, :url),
        'description' => string_param(post, :title),
        'extended'    => string_param(post, :notes),
        'dt'          => date_param(post, :date),
        'tags'        => tags_param(post, :tags),
        'replace'     => replace ? nil : 'no',
        'shared'      => shared ? nil : 'no'
      }.delete_if do |key, value| NilClass === value end
      doc = REXML::Document.new(http_post('/v1/posts/add', params))
      raise unless doc.root.attributes['code'] == 'done'
      nil
    end

    def get_posts(opt = {})
      @api_mode ? get_posts_api(opt) : get_posts_json(opt)
    end

    def delete_post(opt = {})
      raise unless @api_mode
      url = string_param(opt, :url)
      params = {}
      params['url'] = url if url
      doc = REXML::Document.new(http_get('/v1/posts/delete', params))
      raise unless doc.root.attributes['code'] == 'done'
      nil
    end

    def get_tags
      @api_mode ? get_tags_api() : get_tags_json()
    end

    def get_bundles
      raise unless @api_mode
      doc = REXML::Document.new(http_get('/v1/tags/bundles/all', {}))
      bundles = {}
      doc.elements.each('bundles/bundle') do |e|
        name = string_result(e.attributes['name'])
        bundles[name] = tags_result(e.attributes['tags']) if name
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

    def string_param(hash, index)
      NilClass === hash[index] ? nil : hash[index].to_s
    end

    def date_param(hash, index)
      case hash[index]
      when NilClass then nil
      when Time     then hash[index].iso8601
      else               hash[index].to_s
      end
    end

    def tags_param(hash, index)
      case hash[index]
      when NilClass then nil
      when Array    then hash[index].join(' ')
      else               hash[index].to_s
      end
    end

    def string_result(str)
      str ? str.to_s : nil
    end

    def date_result(str)
      str ? (Time === str ? str : Time.iso8601(str)) : nil
    end

    def tags_result(str)
      str ? (Array === str ? str : str.split(' ')) : nil
    end

    def get_posts_api(opt = {})
      params = {
        'url' => string_param(opt, :url),
        'tag' => tags_param(opt, :tags)
      }.delete_if do |key, value| NilClass === value end
      response = (params['url'] ?
                  http_get('/v1/posts/get', params) :
                    http_get('/v1/posts/all', params))
      doc = REXML::Document.new(response)
      posts = []
      doc.elements.each('posts/post') do |e|
        posts << {
          :url   => string_result(e.attributes['href']),
          :title => string_result(e.attributes['description']),
          :notes => string_result(e.attributes['extended']),
          :date  => date_result(e.attributes['time']),
          :tags  => tags_result(e.attributes['tag'])
        }.delete_if do |key, value| NilClass === value end
      end
      posts
    end

    def get_posts_json(opt = {})
      if opt.has_key?(:url)
        raise "Getting posts with URL using JSON feed isn't supported yet."
      end
      params  = { 'count' => 100, 'raw' => '' }
      uname   = urlencode(@username)
      tags    = tags_param(opt, :tags)
      request = "/feeds/json/#{uname}#{tags ? '/' + urlencode(tags) : ''}"
      JsonParser.new.parse(http_get(request, params)).map! do |e|
        {
          :url   => string_result(e['u']),
          :title => string_result(e['d']),
          :notes => string_result(e['n']),
          :tags  => tags_result(e['t'])
        }.delete_if do |key, value| NilClass === value end
      end
    end

    def get_tags_api
      doc = REXML::Document.new(http_get('/v1/tags/get'))
      tags = {}
      doc.elements.each('tags/tag') do |e|
        tag = string_result(e.attributes['tag'])
        tags[tag] = string_result(e.attributes['count']).to_i if tag
      end
      tags
    end

    def get_tags_json
      request = "/feeds/json/tags/#{urlencode(@username)}"
      JsonParser.new.parse(http_get(request, { 'raw' => '' }))
    end

  end

end
