# json API

module WebAPI

  class Json

    # error codes
    ParseError = :parse_error
    IllegalUnicode = :illegal_unicode

    # escape sequence
    EscapeSrc = '"\\/bfnrt'
    EscapeDst = "\"\\/\b\f\n\r\t"

    # single character tokens
    TokenLetters = '{}[],:'

    # regexp
    StringPattern = /^\"((\\.|[^\"\\])*)\"/m
    IntPattern    = /^[-+]?\d+/
    FloatPattern  = /^[-+]?\d*([.eE][-+]?\d+|\.\d+[eE][-+]?\d+)/
    EscSeqPattern = /\\([\"\\\/bfnrt]|u[0-9a-fA-F]{4})/
    TokenPattern  = /^[^#{TokenLetters.gsub(/./) do |s| '\\'+s end}\s]+/
    EscapePattern = /[^\x20-\x21\x23-\x5b\x5d-\xff]/

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

    # JSON Parser
    def add_value(value)
      @tokens << 'v'[0]
      @values << value
    end

    def next_token(str)
      match = TokenPattern.match str
      if match
        [match[0], match.post_match]
      else
        handle_error(ParseError)
      end
    end

    def unescape(str)
      str.gsub(EscSeqPattern) do
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
            add_value(nil)
          elsif IntPattern === token
            add_value($&.to_i)
          elsif FloatPattern === token
            add_value($&.to_f)
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

    def parse_value()
      case get_token()
      when '{'[0]
        parse_object()
      when '['[0]
        parse_array()
      when 'v'[0], 's'[0]
        value = @values[@value_index]
        @value_index += 1
        value
      else
        handle_error(ParseError)
      end
    end

    def parse_array()
      value = []
      if peek_token() != ']'[0]
        while true
          value << parse_value()
          break if peek_token() == ']'[0]
          handle_error(ParseError) if get_token() != ','[0]
        end
      end
      @token_index += 1
      value
    end

    def parse_object()
      value = {}
      if peek_token() != '}'[0]
        while true
          handle_error(ParseError) if get_token() != 's'[0]
          label = @values[@value_index]
          @value_index += 1
          handle_error(ParseError) if get_token() != ':'[0]
          value[label] = parse_value()
          break if peek_token() == '}'[0]
          handle_error(ParseError) if get_token() != ','[0]
        end
      end
      @token_index += 1
      value
    end

    def parse(str)
      s = str.to_s
      lex(s.equal?(str) ? s.clone : s)
      @token_index = 0
      @value_index = 0
      token  = get_token()
      result = ''
      if token == '['[0]
        result = parse_array()
      elsif token == '{'[0]
        result = parse_object()
      else
        handle_error(ParseError)
      end
      @tokens = nil
      @token_index = 0
      @values = nil
      @value_index = 0
      result
    end

    # JSON Builder
    def escape(str)
      str.gsub(EscapePattern) do |chr|
        if chr[0] != 0 && (index = EscapeDst.index(chr[0]))
          "\\" + EscapeSrc[index, 1]
        else
          sprintf("\\u%04x", chr[0])
        end
      end
    end

    def build_value(obj)
      if obj.is_a?(Numeric)
        obj.to_s
      elsif obj.is_a?(Array)
        build_array(obj)
      elsif obj.is_a?(Hash)
        build_object(obj)
      else
        '"' + escape(obj.to_s) + '"'
      end
    end

    def build_array(obj)
      '[' + obj.map { |item| build_value(item) }.join(',') + ']'
    end

    def build_object(obj)
      '{' + obj.map do |item|
        "#{build_value(item[0].to_s)}:#{build_value(item[1])}"
      end.join(',') + '}'
    end

    def build(obj)
      if obj.is_a?(Array)
        build_array(obj)
      elsif obj.is_a?(Hash)
        build_object(obj)
      else
        build_array([obj])
      end
    end

  end

end
