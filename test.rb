#! /usr/bin/ruby

require('webapi')
require('accounts')

api = REST.new(REST.https('api.del.icio.us'), REST.basic_auth(Delicious['username'], Delicious['password']))
print api.get('/v1/posts/recent')

