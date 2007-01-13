# json API

module WebAPI

  class Json

    # error codes
    ParseError = :parse_error

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
      @tokens << ?v
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
          [$1[1,4].hex].pack('U')
        end
      end
    end

    def lex(str)
      @tokens = ''
      @values = []
      until (str = str.lstrip).empty?
        if token = TokenLetters[str[0,1]]
          @tokens << token[0]
          str = str[1, str.length]
        elsif str[0] ==  ?"
          match = StringPattern.match str
          handle_error(ParseError) if !match || !match.pre_match.empty?
          @tokens << ?s
          @values << unescape(match[1])
          str = match.post_match
        else
          token, str = next_token(str)
          case token
          when 'true'
            add_value(true)
          when 'false'
            add_value(false)
          when 'null'
            add_value(nil)
          when IntPattern
            add_value($&.to_i)
          when FloatPattern
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
      when ?{
        parse_object()
      when ?[
        parse_array()
      when ?v, ?s
        value = @values[@value_index]
        @value_index += 1
        value
      else
        handle_error(ParseError)
      end
    end

    def parse_array()
      value = []
      if peek_token() != ?]
        while true
          value << parse_value()
          break if peek_token() == ?]
          handle_error(ParseError) if get_token() != ?,
        end
      end
      @token_index += 1
      value
    end

    def parse_object()
      value = {}
      if peek_token() != ?}
        while true
          handle_error(ParseError) if get_token() != ?s
          label = @values[@value_index]
          @value_index += 1
          handle_error(ParseError) if get_token() != ?:
          value[label] = parse_value()
          break if peek_token() == ?}
          handle_error(ParseError) if get_token() != ?,
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
      result = ''
      case get_token()
      when ?[
        result = parse_array()
      when ?{
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
      case obj
      when Numeric
        obj.to_s
      when Array
        build_array(obj)
      when Hash
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
      case obj
      when Array
        build_array(obj)
      when Hash
        build_object(obj)
      else
        build_array([obj])
      end
    end

  end

end
