require 'net/https'
require 'digest/sha1'
require 'time'

module WebAPI

  module Util
    def urlencode(str)
      str.gsub(/[^a-zA-Z0-9_\.\-]/n) do |s|
        if s == ' ' then '+' else  sprintf('%%%02x', s[0])  end
      end
    end
  end

  class REST

    include Util

    # Protocol

    class HTTP
      # Specify a domain here because I plan to use persistent conection.
      def initialize(domain, port)
        @domain = domain
        @port   = port
      end
      def call(req)
        Net::HTTP.start(@domain, @port) do |http|
          http.request(req).body
        end
      end
    end
    def REST.http(domain, port = 80)
      HTTP.new(domain, port)
    end

    class HTTPS
      # Specify a domain here because I plan to use persistent conection.
      def initialize(domain, port)
        @domain = domain
        @port   = port
      end
      def call(req)
        h = Net::HTTP.new(@domain, @port)
        h.use_ssl = true
        h.start do |http|
          http.request(req).body
        end
      end
    end
    def REST.https(domain, port = 443)
      HTTPS.new(domain, port)
    end

    # Authentication

    class Public
      def set!(req)
        req
      end
    end
    def REST.public()
      Public.new
    end

    class BasicAuth
      def initialize(user, password)
        @user     = user
        @password = password
      end
      def set!(req)
        req.basic_auth(@user, @password)
        req
      end
    end
    def REST.basic_auth(user, password)
      BasicAuth.new(user, password)
    end

    class WSSE
      def initialize(user, password)
        nonce = ''
        while nonce.size < 20
          nonce << rand(256)
        end
        created = Time.new.utc.iso8601.to_s
        digest  = encode64(Digest::SHA1.digest(nonce+created+password))
        @wsse = [
          %!UsernameToken Username="#{user}", !,
          %!PasswordDigest="#{digest}", !,
          %!Nonce="#{encode64(nonce)}", !,
          %!Created="#{created}"!].join('')
      end
      def set!(req)
        req['X-WSSE'] = @wsse
        req
      end
      def encode64(str)
        [str].pack('m').gsub("\n", '')
      end
      private :encode64
    end
    def REST.wsse(user, password)
      WSSE.new(user, password)
    end

    # Methods

    def initialize(protocol, auth = nil)
      @protocol = protocol
      @auth     = auth ? auth : REST.public
    end

    def get(path, params = {})
      params = params.reject { |key, value| !value }
      prm = params.map do |k, v|
        "#{urlencode(k.to_s)}=#{urlencode(v.to_s)}"
      end
      req = Net::HTTP::Get.new(path + (prm.size <= 0 ? '' : '?'+prm.join('&')))
      @auth.set!(req)
      @protocol.call(req)
    end

    def post(path, params = {})
      params = params.reject { |key, value| !value }
      req = Net::HTTP::Post.new(path)
      req.set_form_data(params)
      @auth.set!(req)
      @protocol.call(req)
    end
  end

end
