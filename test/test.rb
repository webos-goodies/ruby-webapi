#! /usr/bin/ruby

$: << File.dirname(__FILE__) + '/..'

begin
require 'rubygems'
rescue LoadError
end

require 'test/unit'
require 'flexmock'
require 'test_delicious.rb'
require 'test_json.rb'
