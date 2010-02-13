# -*- coding: utf-8 -*-

require 'webapi/json'

class TC_JsonParser < Test::Unit::TestCase

  def setup
    @parser  = WebAPI::JsonParser.new
    @builder = WebAPI::JsonBuilder.new
  end

  def b(str)
    RUBY_VERSION >= '1.9.0' ? str.dup.force_encoding('ASCII-8BIT') : str
  end

  def c(code)
    RUBY_VERSION >= '1.9.0' ? code.chr('ASCII-8BIT') : code.chr
  end

  def u(str)
    RUBY_VERSION >= '1.9.0' ? str.dup.force_encoding('UTF-8') : str
  end

  def parse(str, options = {})
    @parser.parse(str, options)
  end

  def build(obj, options = {})
    @builder.build(obj, options)
  end

  def test_empty_array
    assert_equal([], parse('[]'))
  end

  def test_empty_hash
    assert_equal({}, parse('{ }'))
  end

  def test_symbols
    assert_equal([true, false, nil], parse("[true, false, null]"))
  end

  def test_integer
    orig   = [15, 1, -10]
    parsed = parse('[15, 1 , -10]')
    assert_equal(orig, parsed)
    parsed.each do |v|
      assert_kind_of(Integer, v)
    end
    assert_raise(RuntimeError) { parse('[-]') }
    assert_raise(RuntimeError) { parse('[1 2]') }
    assert_raise(RuntimeError) { parse('[-]', :compatible => true) }
    assert_raise(RuntimeError) { parse('[1 2]', :compatible => true) }
  end

  def test_float
    assert_equal([0.5, 12.25, -3.75], parse('[0.5, 12.25 , -3.75 ]'))
    assert_equal([0.5e2, 12.25e-3, -3.75e4], parse('[0.5e+2, 12.25e-3 , -3.75e4]'))
    assert_raise(RuntimeError) { parse('[.5]') }
    assert_raise(RuntimeError) { parse('[0 .5]') }
    assert_raise(RuntimeError) { parse('[- 0.5]') }
    assert_raise(RuntimeError) { parse('[0.5 e3]') }
    assert_equal([0.5, +12.25, -3.75], parse('[0.5, +12.25 , -3.75 ]', :compatible => true))
    assert_equal([0.5e2, +12.25e-3, -3.75e4], parse('[0.5e+2, +12.25e-3 , -3.75e4]', :compatible => true))
    assert_raise(RuntimeError) { parse('[.5]', :compatible => true) }
    assert_raise(RuntimeError) { parse('[0 .5]', :compatible => true) }
    assert_raise(RuntimeError) { parse('[- 0.5]', :compatible => true) }
    assert_raise(RuntimeError) { parse('[0.5 e3]', :compatible => true) }
  end

  def test_string
    [
      [ "1abc ABC", "1abc ABC" ],
      [ '2日本語テキスト', '2日本語テキスト'],
      [ "3\\\r\/\b\f\n\r\t", '3\\\\\r\/\b\f\n\r\t' ],
      [ '4日本語テキスト', '4\\u65e5\\u672c\\u8a9e\\u30c6\\u30ad\\u30b9\\u30c8']
    ].each do |data|
      assert_equal([data[0]], parse('["' + data[1] + '"]'))
      assert_equal([data[0]], parse('["' + data[1] + '"]', :compatible => true))
    end
  end

  def test_surrogate_pair
    10.times do
      expect = []
      json   = []
      3.times do
        hi = rand(0x3ff)
        lo = rand(0x3ff)
        expect << [0x10000 + (hi << 10) + lo].pack('U*')
        json << sprintf('\\u%04x\\u%04X', hi+0xd800, lo+0xdc00)
      end
      assert_equal([expect.join(' ')], parse('["' + json.join(' ') + '"]'))
      assert_equal([expect.join(' ')], parse('["' + json.join(' ') + '"]', :compatible => true))
    end
  end

  def test_nonshortest_sequence_detection
    assert_raise(RuntimeError) { parse("[\"\xc0\xbc\"]") }
    assert_raise(RuntimeError) { parse("[\"\xe0\x80\xbc\"]") }
    assert_raise(RuntimeError) { parse("[\"\xf0\x80\x80\xbc\"]") }
    assert_raise(RuntimeError) { parse("[\"\xc0\xbc\"]",         :compatible => true) }
    assert_raise(RuntimeError) { parse("[\"\xe0\x80\xbc\"]",     :compatible => true) }
    assert_raise(RuntimeError) { parse("[\"\xf0\x80\x80\xbc\"]", :compatible => true) }
    assert_equal(['? ? ?'], parse("[\"\xc0\xbc \xe0\x80\xbc \xf0\x80\x80\xbc\"]", :malformed_chr => ?? ))
  end

  def test_incomplete_sequence_detection
    assert_raise(RuntimeError) { parse(u(b('["日')[0..-2]+b('"]'))) }
    assert_raise(RuntimeError) { parse(u(b('["日本語')[0..-2]+b('"]'))) }
    assert_raise(RuntimeError) { parse(u(b('["日本')[0..-2]+b('語"]'))) }
    assert_raise(RuntimeError) { parse(u(b('["日')[0..-2]+b('"]')),    :compatible => true) }
    assert_raise(RuntimeError) { parse(u(b('["日本語')[0..-2]+b('"]')), :compatible => true) }
    assert_raise(RuntimeError) { parse(u(b('["日本')[0..-2]+b('語"]')), :compatible => true) }
    assert_equal(['日本?'], parse(u(b('["日本語')[0..-2]+b('"]')), :malformed_chr => ??))
  end

  def test_unexpected_firstbyte_detection
    assert_raise(RuntimeError) { parse(u(b('["日')[0..-2] + c(0xc0) + b('"]'))) }
    assert_raise(RuntimeError) { parse(u(b('["日')[0..-3] + c(0xc0) + c(0xc0) + b('"]'))) }
    assert_raise(RuntimeError) { parse(u(b('["日')[0..-2] + c(0xc0) + b('"]')), :compatible => true) }
    assert_raise(RuntimeError) { parse(u(b('["日')[0..-3] + c(0xc0) + c(0xc0) + b('"]')), :compatible => true) }
    assert_equal(['日?語'], parse(u(b('["日本')[0..-2] + c(0xc0) + b('語"]')), :malformed_chr => ??))
  end

  def test_unexpected_secondbyte_detection
    assert_raise(RuntimeError) { parse(u(b('["日')[1..-1]+b('"]'))) }
    assert_raise(RuntimeError) { parse(u(b('["日')+b('本語')[1..-1]+b('"]'))) }
    assert_raise(RuntimeError) { parse(u(b('["日')[1..-1]+b('"]')), :compatible => true) }
    assert_raise(RuntimeError) { parse(u(b('["日')+b('本語')[1..-1]+b('"]')), :compatible => true) }
    assert_equal(['日??語'], parse(u(b('["日')+b('本語')[1..-1]+b('"]')), :malformed_chr => ??))
  end

  def test_surrogate_pair_range_detection
    10.times do
      data = []
      3.times do
        data << [rand(0x3ff)+0xd800].pack('U*')
        data << [rand(0x3ff)+0xdc00].pack('U*')
      end
      assert_equal(['? ? ? ? ? ?'], parse('["' + data.join(' ') + '"]', :malformed_chr => ??))
    end
  end

  def test_nan
    assert_raise(RuntimeError) { build([0.0/0]) }
    assert_raise(RuntimeError) { build([1.0/0]) }
    assert_raise(RuntimeError) { build([-1.0/0]) }
    assert_equal('[0]', build([0.0/0], { :nan => 0 }))
    assert_equal('[0]', build([1.0/0], { :nan => 0 }))
    assert_equal('[0]', build([-1.0/0], { :nan => 0 }))
  end

  def test_escape
    source = ["\x01\x02\x03\x04\x05\x06\x07\x08\x09\x0a\x0b\x0c\x0d\x0e\x0f" +
              "\x10\x11\x12\x13\x14\x15\x16\x17\x18\x19\x1a\x1b\x1c\x1d\x1e\x1f" +
              "\x22\x2f\x5c"]
    expect = ('["\u0001\u0002\u0003\u0004\u0005\u0006\u0007\b\t\n\u000b\f\r\u000e\u000f' +
              '\u0010\u0011\u0012\u0013\u0014\u0015\u0016\u0017\u0018' +
              '\u0019\u001a\u001b\u001c\u001d\u001e\u001f\\"\\/\\\\"]')
    assert_equal(expect, build(source).downcase)
    assert_equal(expect, build(source, { :nan => 0 }).downcase)
  end

  def test_generic

    json1 = <<EOS
{
	"Image": {
		"Width":  800,
		"Height": 600,
		"Title":  "View from 15th Floor \x01\\\\\\b\\f\\n\\r\\t",
		"Thumbnail": {
			"Url":    "http://www.example.com/image/481989943",
			"Height": 125,
			"Width":  100
		},
		"IDs": [116, 943, 234, 38793]
	}
}
EOS

    expect1 = {
      "Image" => {
        "Width" => 800,
        "Height" => 600,
        "Title" => "View from 15th Floor \x01\\\b\f\n\r\t",
        "Thumbnail" => {
          "Url" => "http://www.example.com/image/481989943",
          "Height" => 125,
          "Width" => 100
        },
        "IDs" => [116, 943, 234, 38793]
      }
    }

    assert_equal(expect1, parse(json1, :compatible => true))
    assert_equal(expect1, parse(build(expect1), :compatible => true))

json2 = <<EOS
[
	{
		"precision": "zip",
		"Latitude":  37.7668,
		"Longitude": -122.3959,
		"Address":   "",
		"City":      "東京都台東区",
		"State":     "CA",
		"Zip":       "94107",
		"Country":   "US"
	},
	{
		"precision": "zip",
		"Latitude":  37.371991,
		"Longitude": -122.026020,
		"Address":   "",
		"City":      "SUNNYVALE",
		"State":     "CA",
		"Zip":       "94085",
		"Country":   "US"
	}
]
EOS

    expect2 = [
      {
		"precision" => "zip",
		"Latitude" =>  37.7668,
		"Longitude" => -122.3959,
		"Address" =>   "",
		"City" =>      "東京都台東区",
		"State" =>     "CA",
		"Zip" =>       "94107",
		"Country" =>   "US"
      },
      {
		"precision" => "zip",
		"Latitude" =>  37.371991,
		"Longitude" => -122.026020,
		"Address" =>   "",
		"City" =>      "SUNNYVALE",
		"State" =>     "CA",
		"Zip" =>       "94085",
		"Country" =>   "US"
      }
    ]

    assert_equal(expect2, parse(json2))
    assert_equal(expect2, parse(build(expect2)))

  end

end
