#! /usr/bin/ruby

require 'SimpleJson'
require 'nkf'

data1 = <<EOS
{
	"Image": {
		"Width":  800,
		"Height": 600,
		"Title":  "View from 15th Floor",
		"Thumbnail": {
			"Url":    "http://www.example.com/image/481989943",
			"Height": 125,
			"Width":  "100"
		},
		"IDs": [116, 943, 234, 38793]
	}
}
EOS

data2 = <<EOS
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

data3 = <<EOS
{
	"true" : true,
	"false" : false,
	"null" : null,
	"ABC" : "\\u0041\\u0042\\u0043\\u3042\\u3044\\u3046\xc0\xa0\r\n",
	"" : [ [], {}, "" ]
}
EOS

def test(data)
  obj = JsonParser.new.parse(data, :malformed_chr => "?")
  p obj
  print NKF.nkf('-sW', JsonBuilder.new.build(obj)), "\n\n"
end

test(data1)
test(data2)
test(data3)
