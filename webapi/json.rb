# json API

require 'strscan'

module WebAPI

  class JsonParser

    Name               = 'WebAPI::JsonParser'
    ERR_IllegalSyntax  = "[#{Name}] Syntax error"
    ERR_IllegalUnicode = "[#{Name}] Illegal unicode sequence"

    StringRegex = /\s*"((?:\\.|[^"\\])*)"/
    ValueRegex  = /\s*(?:
		(true)|(false)|(null)|                          # 1:true, 2:false, 3:null
		(?:\"((?:\\.|[^\"\\])*)\")|                     # 4:String
		([-+]?\d*(?:[.eE][-+]?\d+|\.\d+[eE][-+]?\d+))|  # 5:Float
		([-+]?\d+)|                                     # 6:Integer
		(\{)|(\[))/x                                    # 7:Hash, 8:Array

    def initialize(option = {})
      @default_validation    = option.has_key?('validation')    ? option['validation']    : true
      @default_surrogate     = option.has_key?('surrogate')     ? option['surrogate']     : true
      @default_malformed_chr = option.has_key?('malformed_chr') ? option['malformed_chr'] : nil
    end

    def parse(str, option = {})
      @enable_validation = option.has_key?('validation')    ? option['validation']    : @default_validation
      @enable_surrogate  = option.has_key?('surrogate')     ? option['surrogate']     : @default_surrogate
      @malformed_chr     = option.has_key?('malformed_chr') ? option['malformed_chr'] : @default_malformed_chr
      @malformed_chr = @malformed_chr[0] if String === @malformed_chr
      @scanner = StringScanner.new(str)
      obj = case get_symbol[0]
            when ?{ then parse_hash
            when ?[ then parse_array
            else         raise err_msg(ERR_IllegalSyntax)
            end
      @scanner = nil
      obj
    end

    def validate_string(str)
      code  = 0
      rest  = 0
      range = nil
      ucs   = []
      str.each_byte do |c|
        if rest <= 0
          case c
          when 0x01..0x7f then rest = 0 ; ucs << c
          when 0xc0..0xdf then rest = 1 ; code = c & 0x1f ; range = 0x00080..0x0007ff
          when 0xe0..0xef then rest = 2 ; code = c & 0x0f ; range = 0x00800..0x00ffff
          when 0xf0..0xf7 then rest = 3 ; code = c & 0x07 ; range = 0x10000..0x1fffff
          else                 ucs << malformed_chr()
          end
        elsif 0x80..0xbf === c
          code = (code << 6) | (c & 0x3f)
          if (rest -= 1) <= 0 && (!(range === code) || (0xd800..0xdfff) === code)
            code = malformed_chr()
          end
          ucs << code
        else
          ucs << malformed_chr()
        end
      end
      ucs.pack('U*')
    end

    private

    def malformed_chr()
      raise err_msg(ERR_IllegalUnicode) unless @malformed_chr
      @malformed_chr
    end

    def err_msg(err)
      err + " \"#{@scanner.string[[0, @scanner.pos - 8].max,16]}\""
    end

    def unescape_string(str)
      str = str.gsub(/\\(["\\\/bfnrt])/) do
        $1.tr('"\\/bfnrt', "\"\\/\b\f\n\r\t")
      end.gsub(/(\\u[0-9a-fA-F]{4})+/) do |matched|
        seq = matched.scan(/\\u([0-9a-fA-F]{4})/).flatten.map { |c| c.hex }
        if @enable_surrogate
          seq.each_index do |index|
            if seq[index] && (0xd800..0xdbff) === seq[index]
              n = index + 1
              raise err_msg(ERR_IllegalUnicode) unless seq[n] && 0xdc00..0xdfff === seq[n]
              seq[index] = 0x10000 + ((seq[index] & 0x03ff) << 10) + (seq[n] & 0x03ff)
              seq[n] = nil
            end
          end.compact
        end
        seq.pack('U*')
      end
      str = validate_string(str) if @enable_validation
      str
    end

    def get_symbol
      raise err_msg(ERR_IllegalSyntax) unless @scanner.scan(/\s*(.)/)
      @scanner[1]
    end

    def parse_string
      raise err_msg(ERR_IllegalSyntax) unless @scanner.scan(StringRegex)
      unescape_string(@scanner[1])
    end

    def parse_value
      raise err_msg(ERR_IllegalSyntax) unless @scanner.scan(ValueRegex)
      case
      when @scanner[1] then true
      when @scanner[2] then false
      when @scanner[3] then nil
      when @scanner[4] then unescape_string(@scanner[4])
      when @scanner[5] then @scanner[5].to_f
      when @scanner[6] then @scanner[6].to_i
      when @scanner[7] then parse_hash
      when @scanner[8] then parse_array
      else                  raise err_msg(ERR_IllegalSyntax)
      end
    end

    def parse_hash
      obj = {}
      while true
        index = parse_string
        raise err_msg(ERR_IllegalSyntax) unless get_symbol[0] == ?:
        value = parse_value
        obj[index] = value
        case get_symbol[0]
        when ?} then return obj
        when ?, then next
        else         raise err_msg(ERR_IllegalSyntax)
        end
      end
    end

    def parse_array
      obj = []
      while true
        obj << parse_value
        case get_symbol[0]
        when ?] then return obj
        when ?, then next
        else         raise err_msg(ERR_IllegalSyntax)
        end
      end
    end

  end

  class JsonBuilder

    def build(obj)
      case obj
      when Array then build_array(obj)
      when Hash  then build_object(obj)
      else            build_array([obj])
      end
    end

    private

    def escape(str)
      str.gsub(/[^\x20-\x21\x23-\x5b\x5d-\xff]/) do |chr|
        if chr[0] != 0 && (index = "\"\\/\b\f\n\r\t".index(chr[0]))
          "\\" + '"\\/bfnrt'[index, 1]
        else
          sprintf("\\u%04x", chr[0])
        end
      end
    end

    def build_value(obj)
      case obj
      when Numeric, TrueClass, FalseClass then obj.to_s
      when NilClass then 'null'
      when Array    then build_array(obj)
      when Hash     then build_object(obj)
      else          "\"#{escape(obj.to_s)}\""
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

  end

end
