#! /usr/bin/ruby

require 'webapi/delicious'

class TC_DeliciousPostsApi < Test::Unit::TestCase
  include FlexMock::TestCase

  USERNAME='hokousya'
  PASSWORD='password'

  def load_file(fname)
    IO.read(File.dirname(__FILE__) + '/delicious/posts_api/' + fname)
  end

  def initialize(name)
    super
    @add_success    = load_file('add_success')
    @add_failure    = load_file('add_failure')
    @get_with_url   = load_file('get_with_url')
    @get_with_tag1  = load_file('get_with_tag1')
    @get_with_tag2  = load_file('get_with_tag2')
    @delete_success = load_file('delete_success')
    @delete_failure = load_file('delete_failure')
  end

  def setup
    flexstub(WebAPI::REST) do |s|
      s.should_receive(:https).with('api.del.icio.us').and_return(:https)
      s.should_receive(:basic_auth).with(USERNAME, PASSWORD).and_return(:auth)
      @stub = s;
    end
  end

  # Adding a post ----------------------------------------------------

  def add_post(args, replace = true, shared = true, result = nil,
               limiter = WebAPI::Delicious::NullLimiter)
    map  = { :title => 'description', :notes => 'extended', :date => 'dt' }

    params = {}
    args.each do |key, value|
      params[map[key] ? map[key] : key.to_s] = value
    end

    params['dt']      = params['dt'].iso8601     if Time === params['dt']
    params['tags']    = params['tags'].join(' ') if Array === params['tags']
    params['replace'] = 'no' unless replace
    params['shared']  = 'no' unless shared

    @stub.should_receive(:new).with(:https, :auth).and_return {
      flexmock('rest') do |m|
        m.should_receive(:post).
          with('/v1/posts/add', params).
          and_return(result ? result : @add_success)
      end
    }

    obj = WebAPI::Delicious.new(USERNAME, PASSWORD, limiter)
    obj.add_post(args, replace, shared)
  end

  def test_add1
    add_post({ :url => 'http://webos-goodies.jp/',
               :title => 'It is my blog.' })
  end

  def test_add2
    add_post({ :url => 'http://webos-goodies.jp/',
               :title => 'It is my blog.',
               :notes => 'more description.'})
  end

  def test_add3
    add_post({ :url => 'http://webos-goodies.jp/',
               :title => 'It is my blog.',
               :date => Time.now })
  end

  def test_add4
    add_post({ :url => 'http://webos-goodies.jp/',
               :title => 'It is my blog.',
               :date => Time.now.iso8601 })
  end

  def test_add5
    add_post({ :url => 'http://webos-goodies.jp/',
               :title => 'It is my blog.',
               :tags => 'tag1' })
  end

  def test_add6
    add_post({ :url => 'http://webos-goodies.jp/',
               :title => 'It is my blog.',
               :tags => ['tag1', 'tag2'] })
  end

  def test_add_with_default_limiter
    add_post({ :url => 'http://webos-goodies.jp/',
               :title => 'It is my blog.' },
             true, true, nil, WebAPI::Delicious::DefaultLimiter)
    time = Time.now
    add_post({ :url => 'http://webos-goodies.jp/',
               :title => 'It is my blog.' },
             true, true, nil, WebAPI::Delicious::DefaultLimiter)
    assert(Time.now - time > 1.0)
  end

  def test_add_without_replace_and_shared
    add_post({ :url => 'http://webos-goodies.jp/',
               :title => 'It is my blog.' }, false, false)
  end

  def test_fail_to_add
    assert_raise(RuntimeError) {
      add_post({ :url => 'http://webos-goodies.jp/',
                 :title => 'It is my blog.' },
               false, false, @add_failure)
    }
  end

  # Getting posts ----------------------------------------------------

  def template_posts(xml)
    posts = []
    doc = REXML::Document.new(xml)
    doc.elements.each('posts/post') do |e|
      url   = e.attributes['href']
      title = e.attributes['description']
      notes = e.attributes['extended']
      date  = e.attributes['time']
      tags  = e.attributes['tag']
      posts << {
        :url   => url ? url.to_s : nil,
        :title => title ? title.to_s : nil,
        :notes => notes ? notes.to_s : nil,
        :date  => date ? Time.iso8601(date) : nil,
        :tags  => tags ? tags.split(' ') : nil
      }.delete_if do |key, value| NilClass === value end
    end
    posts
  end

  def get_posts(opt, result, limiter = WebAPI::Delicious::NullLimiter)
    params = {}
    params['url'] = opt[:url] if opt.has_key?(:url)
    params['tag'] = [opt[:tags]].flatten.join(' ') if opt.has_key?(:tags)

    request_url = opt.has_key?(:url) ? '/v1/posts/get' : '/v1/posts/all'

    @stub.should_receive(:new).with(:https, :auth).and_return {
      flexmock('rest') do |m|
        m.should_receive(:get).with(request_url, params).and_return(result)
      end
    }

    obj = WebAPI::Delicious.new(USERNAME, PASSWORD, limiter)
    obj.get_posts(opt)
  end

  def test_get_with_url
    opt = { :url => 'http://webos-goodies.jp/archives/51097336.html'}
    result = @get_with_url
    posts = get_posts(opt, result)
    assert_equal(template_posts(result), posts)
  end

  def test_get_with_single_tag
    opt = { :tags => 'sitebar' }
    result = @get_with_tag1
    posts = get_posts(opt, result)
    assert_equal(template_posts(result), posts)
  end

  def test_get_with_two_tags
    opt = { :tags => ['webapps-tips', 'browser-tips'] }
    result = @get_with_tag2
    posts = get_posts(opt, result)
    assert_equal(template_posts(result), posts)
  end

  def test_get_with_default_limiter
    opt = { :tags => 'sitebar' }
    result = @get_with_tag1
    get_posts(opt, result, WebAPI::Delicious::DefaultLimiter)
    time = Time.now
    get_posts(opt, result, WebAPI::Delicious::DefaultLimiter)
    assert(Time.now - time > 1.0)
  end

  # Deleting a post --------------------------------------------------

  def delete_post(opt, result, limiter = WebAPI::Delicious::NullLimiter)
    params = {}
    params['url'] = opt[:url] if opt.has_key?(:url)

    @stub.should_receive(:new).with(:https, :auth).and_return {
      flexmock('rest') do |m|
        m.should_receive(:get).
          with('/v1/posts/delete', params).and_return(result)
      end
    }

    obj = WebAPI::Delicious.new(USERNAME, PASSWORD, limiter)
    obj.delete_post(opt)
  end

  def test_delete
    delete_post({ :url => 'http://webos-goodies.jp/' }, @delete_success)
  end

  def test_fail_to_delete
    assert_raise(RuntimeError) {
      delete_post({ }, @delete_failure)
    }
  end

  def test_delete_with_default_limiter
    opt = { :url => 'http://webos-goodies.jp/' }
    result = @delete_success
    delete_post(opt, result, WebAPI::Delicious::DefaultLimiter)
    time = Time.now
    delete_post(opt, result, WebAPI::Delicious::DefaultLimiter)
    assert(Time.now - time > 1.0)
  end

end

class TC_DeliciousTagsApi < Test::Unit::TestCase
  include FlexMock::TestCase

  USERNAME='hokousya'
  PASSWORD='password'

  def load_file(fname)
    IO.read(File.dirname(__FILE__) + '/delicious/tags_api/' + fname)
  end

  def initialize(name)
    super
    @get_success = load_file('get_success')
  end

  def setup
    flexstub(WebAPI::REST) do |s|
      s.should_receive(:https).with('api.del.icio.us').and_return(:https)
      s.should_receive(:basic_auth).with(USERNAME, PASSWORD).and_return(:auth)
      @stub = s;
    end
  end

  def template_tags(xml)
    doc = REXML::Document.new(xml)
    tags = {}
    doc.elements.each('tags/tag') do |e|
      tag = e.attributes['tag']
      tags[tag.to_s] = e.attributes['count'].to_s.to_i if tag
    end
    tags
  end

  def get_tags(result, limiter = WebAPI::Delicious::NullLimiter)
    @stub.should_receive(:new).with(:https, :auth).and_return {
      flexmock('rest') do |m|
        m.should_receive(:get).with('/v1/tags/get', {}).and_return(result)
      end
    }

    obj = WebAPI::Delicious.new(USERNAME, PASSWORD, limiter)
    obj.get_tags()
  end

  def test_get
    result = @get_success
    tags = get_tags(result)
    assert_equal(template_tags(result), tags)
  end

  def test_get_with_default_limiter
    result = @get_success
    get_tags(result, WebAPI::Delicious::DefaultLimiter)
    time = Time.now
    get_tags(result, WebAPI::Delicious::DefaultLimiter)
    assert(Time.now - time > 1.0)
  end

end

class TC_DeliciousBundlesApi < Test::Unit::TestCase
  include FlexMock::TestCase

  USERNAME='hokousya'
  PASSWORD='password'

  def load_file(fname)
    IO.read(File.dirname(__FILE__) + '/delicious/bundles_api/' + fname)
  end

  def initialize(name)
    super
    @get_success = load_file('get_success')
  end

  def setup
    flexstub(WebAPI::REST) do |s|
      s.should_receive(:https).with('api.del.icio.us').and_return(:https)
      s.should_receive(:basic_auth).with(USERNAME, PASSWORD).and_return(:auth)
      @stub = s;
    end
  end

  def template_bundles(xml)
    doc = REXML::Document.new(xml)
    bundles = {}
    doc.elements.each('bundles/bundle') do |e|
      name = e.attributes['name']
      bundles[name.to_s] = e.attributes['tags'].to_s.split(' ') if name
    end
    bundles
  end

  def get_bundles(result, limiter = WebAPI::Delicious::NullLimiter)
    @stub.should_receive(:new).with(:https, :auth).and_return {
      flexmock('rest') do |m|
        m.should_receive(:get).
          with('/v1/tags/bundles/all', {}).and_return(result)
      end
    }

    obj = WebAPI::Delicious.new(USERNAME, PASSWORD, limiter)
    obj.get_bundles()
  end

  def test_get
    result = @get_success
    bundles = get_bundles(result)
    assert_equal(template_bundles(result), bundles)
  end

  def test_get_with_default_limiter
    result = @get_success
    get_bundles(result, WebAPI::Delicious::DefaultLimiter)
    time = Time.now
    get_bundles(result, WebAPI::Delicious::DefaultLimiter)
    assert(Time.now - time > 1.0)
  end

end

class TC_DeliciousPostsJson < Test::Unit::TestCase
  include FlexMock::TestCase

  USERNAME='hokousya'

  def load_file(fname)
    IO.read(File.dirname(__FILE__) + '/delicious/posts_json/' + fname)
  end

  def initialize(name)
    super
    @get_with_tag1 = load_file('get_with_tag1')
    @get_with_tag2 = load_file('get_with_tag2')
  end

  def setup
    flexstub(WebAPI::REST) do |s|
      s.should_receive(:http).with('del.icio.us').and_return(:http)
      @stub = s;
    end
  end

  def template_posts(json)
    posts = []
    WebAPI::JsonParser.new.parse(json).each do |e|
      posts << {
        :url   => e['u'],
        :title => e['d'],
        :notes => e['n'],
        :tags  => e['t']
      }.delete_if do |key, value| NilClass === value end
    end
    posts
  end

  def get_posts(opt, result)
    request_url = ("/feeds/json/#{USERNAME}" +
                     (opt[:tags] ? '/' + [opt[:tags]].flatten.join('+') : ''))
    params      = { 'raw' => '', 'count' => 100 }

    @stub.should_receive(:new).with(:http, nil).and_return {
      flexmock('rest') do |m|
        m.should_receive(:get).with(request_url, params).and_return(result)
      end
    }

    obj = WebAPI::Delicious.new(USERNAME)
    obj.get_posts(opt)
  end

  def test_get_with_url
    opt = { :url => 'http://webos-goodies.jp/archives/51097336.html'}
    result = @get_with_url
    assert_raise(RuntimeError) {
      get_posts(opt, result)
    }
  end

  def test_get_with_single_tag
    opt = { :tags => 'sitebar' }
    result = @get_with_tag1
    posts = get_posts(opt, result)
    assert_equal(template_posts(result), posts)
  end

  def test_get_with_two_tags
    opt = { :tags => ['webapps-tips', 'browser-tips'] }
    result = @get_with_tag2
    posts = get_posts(opt, result)
    assert_equal(template_posts(result), posts)
  end

end

class TC_DeliciousTagsJson < Test::Unit::TestCase
  include FlexMock::TestCase

  USERNAME='hokousya'
  PASSWORD='password'

  def load_file(fname)
    IO.read(File.dirname(__FILE__) + '/delicious/tags_json/' + fname)
  end

  def initialize(name)
    super
    @get_success = load_file('get_success')
  end

  def setup
    flexstub(WebAPI::REST) do |s|
      s.should_receive(:http).with('del.icio.us').and_return(:http)
      @stub = s;
    end
  end

  def template_tags(json)
    WebAPI::JsonParser.new.parse(json)
  end

  def get_tags(result)
    request_url = "/feeds/json/tags/#{USERNAME}"
    params      = { 'raw' => '' }

    @stub.should_receive(:new).with(:http, nil).and_return {
      flexmock('rest') do |m|
        m.should_receive(:get).with(request_url, params).and_return(result)
      end
    }

    obj = WebAPI::Delicious.new(USERNAME)
    obj.get_tags()
  end

  def test_get
    result = @get_success
    tags = get_tags(result)
    assert_equal(template_tags(result), tags)
  end

end
