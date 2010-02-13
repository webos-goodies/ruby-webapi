#! /usr/bin/ruby

def remove_comments(lines)
  lines.map do |line|
    /^\s*#/ === line ? nil : line
  end.compact
end

def peel_module(lines)
  lines.map do |line|
    if /(^module WebAPI)|(^end)/ === line
      nil
    elsif /^  (.*)/m === line
      $1
    else
      line
    end
  end.compact
end

def remove_namespace(lines)
  lines.map do |line|
    line.gsub('WebAPI::', '')
  end
end

def write_file(fname, perm, lines)
  File.open(fname, 'w', perm) do |file|
    lines.each do |line|
      file.write(line)
    end
  end
end

# convert library
lines = IO.readlines('../webapi/json.rb')
lines = remove_namespace(peel_module(lines))
write_file('SimpleJson/SimpleJson.rb', 0666, lines)

lines = IO.readlines('../webapi/json.rb')
lines = remove_namespace(peel_module(remove_comments(lines)))
write_file('SimpleJson/SimpleJson_without_comment.rb', 0666, lines)

# convert test
lines = IO.readlines('../test/test_json.rb')
lines.delete("# -*- coding: utf-8 -*-\n")
lines.delete("require 'webapi/json'\n")
lines.unshift(["#! /usr/bin/ruby",
               "# -*- coding: utf-8 -*-",
               "",
               "require 'test/unit'",
               "require 'SimpleJson.rb'"].join("\n"))
lines = remove_namespace(lines)
write_file('SimpleJson/test_json.rb', 0777, lines)
