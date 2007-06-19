require 'webapi/json'

class TC_JsonParser < Test::Unit::TestCase

  def setup
    @parser = WebAPI::JsonParser.new
  end

  def parse(str, options = {})
    @parser.parse(str, options)
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
    assert_equal([15, +1, -10], parse('[15, +1 , -10]'))
    assert_raise(RuntimeError) { parse('[-]') }
    assert_raise(RuntimeError) { parse('[1 2]') }
  end

  def test_float
    assert_equal([0.5, +12.25, -3.75], parse('[0.5, +12.25 , -3.75 ]'))
    assert_equal([0.5e2, +12.25e-3, -3.75e4], parse('[0.5e2, +12.25e-3 , -3.75e4]'))
    assert_raise(RuntimeError) { parse('[.5]') }
    assert_raise(RuntimeError) { parse('[0 .5]') }
    assert_raise(RuntimeError) { parse('[- 0.5]') }
    assert_raise(RuntimeError) { parse('[0.5 e3]') }
  end

  def test_string
    [
      [ "abc ABC", "abc ABC" ],
      [ '日本語テキスト', '日本語テキスト'],
      [ "\\\r\/\b\f\n\r\t", '\\\\\r\/\b\f\n\r\t' ],
      [ '日本語テキスト', '\u65e5\u672c\u8a9e\u30c6\u30ad\u30b9\u30c8']
    ].each do |data|
      assert_equal([data[0]], parse('["' + data[1] + '"]'))
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
    end
  end

  def test_nonshortest_sequence_detection
    assert_raise(RuntimeError) { parse("[\"\xc0\xbc\"]") }
    assert_raise(RuntimeError) { parse("[\"\xe0\x80\xbc\"]") }
    assert_raise(RuntimeError) { parse("[\"\xf0\x80\x80\xbc\"]") }
    assert_equal(['? ? ?'], parse("[\"\xc0\xbc \xe0\x80\xbc \xf0\x80\x80\xbc\"]", :malformed_chr => ?? ))
  end

  def test_incomplete_sequence_detection
    assert_raise(RuntimeError) { parse('["日'[0..-2]+'"]') }
    assert_raise(RuntimeError) { parse('["日本語'[0..-2]+'"]') }
    assert_raise(RuntimeError) { parse('["日本'[0..-2]+'語"]') }
    assert_equal(['日本?'], parse('["日本語'[0..-2]+'"]', :malformed_chr => ??))
  end

  def test_unexpected_secondbyte_detection
    assert_raise(RuntimeError) { parse('["日'[1..-1]+'"]') }
    assert_raise(RuntimeError) { parse('["日'+'本語'[1..-1]+'"]') }
    assert_equal(['日??語'], parse('["日'+'本語'[1..-1]+'"]', :malformed_chr => ??))
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

  def test_generic

    json1 = <<EOS
{
	"Image": {
		"Width":  800,
		"Height": 600,
		"Title":  "View from 15th Floor",
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
        "Title" => "View from 15th Floor",
        "Thumbnail" => {
          "Url" => "http://www.example.com/image/481989943",
          "Height" => 125,
          "Width" => 100
        },
        "IDs" => [116, 943, 234, 38793]
      }
    }

    assert_equal(expect1, parse(json1))

json2 = <<EOS
[
	{
		"precision": "zip",
		"Latitude":  37.7668,
		"Longitude": -122.3959,
		"Address":   "",
		"City":      "SAN FRANCISCO",
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
		"City" =>      "SAN FRANCISCO",
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

  end

end
