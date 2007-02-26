#! /usr/bin/ruby

lines = $<.readlines

# remove WebAPI module and adjust indent.
lines.map! do |line|
  if /(^module WebAPI)|(^end)/ === line
    nil
  elsif /^  (.*)/m === line
    $1
  else
    line
  end
end.compact!

# remove "WebAPI::".
lines.each do |line|
  line.gsub!('WebAPI::', '')
end

# print results
lines.each do |line|
  print line
end
