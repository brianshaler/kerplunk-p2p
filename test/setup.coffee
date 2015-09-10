path = require 'path'
global.Should = require 'should'

before ->
  @fixturePath = (pathname) ->
    path.join __dirname, 'fixtures', pathname
  @fixture = (pathname) ->
    require path.join __dirname, 'fixtures', pathname
