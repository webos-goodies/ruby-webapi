# json API

module WebAPI

  class JsonParser

    # error codes
    ParseError = :parse_error
    IllegalUnicode = :illegal_unicode

    # escape sequence
    EscapeSrc = '"\\/bfnrt'
    EscapeDst = "\"\\/\b\f\n\r\t"

    # regexp
    StringPattern = /^\"((\\.|[^\"\\])*)\"/m
    IntPattern    = /^[-+]?\d+$/
    FloatPattern  = /^[-+]?\d*([.eE][-+]?\d+|\.\d+[eE][-+]?\d+)$/
    EscapePattern = /\\([\"\\\/bfnrt]|u[0-9a-fA-F]{4})/
    TokenPattern  = /\S+/

    # single character tokens
    TokenLetters = '{}[],:'

    # Override this method if you'd like to handle parse errors by yourself.
    def handle_error(err)
      raise
    end

    def initialize
      @tokens = nil
      @token_index = 0
      @values = nil
      @value_index = 0
    end

    def add_value(value)
      @tokens << 'v'[0]
      @values << value
    end

    def next_token(str)
      match = TokenPattern.match str
      if !match || !match.pre_match.empty?
        handle_error(ParseError)
      else
        [match[0], match.post_match]
      end
    end

    def unescape(str)
      str.gsub(EscapePattern) do
        if $1.length == 1
          $1.tr(EscapeSrc, EscapeDst)
        else
          utf16to8($1[1,4].hex)
        end
      end
    end

    def utf16to8(code)
      str = ''
      case code
      when 0 .. 0x7f
        str << code
      when 0x80 .. 0x7ff
        str << 0xc0 + (code >> 6 & 0x1f)
        str << 0x80 + (code & 0x3f)
      when 0x800 .. 0xffff
        str << 0xe0 + (code >> 12 & 0x0f)
        str << 0x80 + (code >>  6 & 0x3f)
        str << 0x80 + (code       & 0x3f)
      when 0x10000 .. 0x1fffff  # It may be unneeded
        str << 0xf0 + (code >> 18 & 0x07)
        str << 0x80 + (code >> 12 & 0x3f)
        str << 0x80 + (code >>  6 & 0x3f)
        str << 0x80 + (code       & 0x3f)
      else
        handle_error(IllegalUnicode)
      end
      str
    end

    def lex(str)
      @tokens = ''
      @values = []
      str = str.clone
      until (str = str.lstrip).empty?
        if token = TokenLetters[str[0,1]]
          @tokens << token[0]
          str = str[1, str.length]
        elsif str[0] ==  '"'[0]
          match = StringPattern.match str
          handle_error(ParseError) if !match || !match.pre_match.empty?
          @tokens << 's'[0]
          @values << unescape(match[1])
          str = match.post_match
        else
          token, str = next_token(str)
          if token == 'true'
            add_value(true)
          elsif token == 'false'
            add_value(false)
          elsif token == 'null'
            add_value(null)
          elsif IntPattern === token
            add_value($0.to_i)
          elsif FloatPattern === token
            add_value($0.to_f)
          else
            handle_error(ParseError)
          end
        end
      end
    end

    def peek_token()
      handle_error(ParseError) unless token = @tokens[@token_index]
      token
    end

    def get_token()
      handle_error(ParseError) unless token = @tokens[@token_index]
      @token_index += 1
      token
    end

    def build_value()
      case get_token()
      when '{'[0]
        build_object()
      when '['[0]
        build_array()
      when 'v'[0], 's'[0]
        value = @values[@value_index]
        @value_index += 1
        value
      else
        handle_error(ParseError)
      end
    end

    def build_array()
      value = []
      if peek_token() != ']'[0]
        while true
          value << build_value()
          break if peek_token() == ']'[0]
          handle_error(ParseError) if get_token() != ','[0]
        end
      end
      @token_index += 1
      value
    end

    def build_object()
      value = {}
      if peek_token() != '}'[0]
        while true
          handle_error(ParseError) if get_token() != 's'[0]
          label = @values[@value_index]
          @value_index += 1
          handle_error(ParseError) if get_token() != ':'[0]
          value[label] = build_value()
          break if peek_token() == '}'[0]
          handle_error(ParseError) if get_token() != ','[0]
        end
      end
      @token_index += 1
      value
    end

    def build()
      @token_index = 0
      @value_index = 0
      token = get_token()
      if token == '['[0]
        build_array()
      elsif token == '{'[0]
        build_object()
      else
        handle_error(ParseError)
      end
    end

    def parse(str)
      lex(str)
      result = build()
      @tokens = nil
      @token_index = 0
      @values = nil
      @value_index = 0
      result
    end

  end

end

require 'open-uri'
require 'nkf'

src = ''
open('http://del.icio.us/feeds/json/hokousya?raw') do |file|
  src = file.read
end

parser = WebAPI::JsonParser.new
json = parser.parse(src)

out = ''
json.each do |item|
  out += "name : #{item['d']}\n"
  out += "url : #{item['u']}\n\n"
end

print NKF.nkf('-s', out)
