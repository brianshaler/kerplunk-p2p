crypto = require 'crypto'

_ = require 'lodash'
request = require 'request'
Promise = require 'when'
neo4j = require 'neo4j'

EntityModel = require './models/Entity'

module.exports = (System) ->
  {ip, ports} = System.getService 'neo4j'
  dbUrl = "http://#{ip}:#{ports['7474/tcp']}"
  console.log 'dbUrl', dbUrl

  defaultUsername = 'neo4j'
  defaultPassword = 'neo4j'

  getDB = (settings) ->
    # _dbUrl = "http://#{settings.username}:#{settings.password}@#{ip}:#{ports['7474/tcp']}"
    # db = new neo4j.GraphDatabase _dbUrl
    settings.username = settings.username ? defaultUsername
    settings.password = settings.password ? defaultPassword

    dbRef = new neo4j.GraphDatabase
      url: dbUrl
      auth:
        username: settings.username
        password: settings.password

    dbRef: dbRef
    models: {}
    cypher: (opt) ->
      Promise.promise (resolve, reject) ->
        dbRef.cypher opt, (err, data) ->
          return reject err if err
          resolve data
    createConstraint: (opt) ->
      Promise.promise (resolve, reject) ->
        dbRef.createConstraint opt, (err, data) ->
          return reject err if err
          resolve data
    checkPasswordChangeNeeded: ->
      Promise.promise (resolve, reject) ->
        dbRef.checkPasswordChangeNeeded (err, data) ->
          return reject err if err
          resolve data
    changePassword: (opt) ->
      Promise.promise (resolve, reject) ->
        dbRef.changePassword opt, (err) ->
          return reject err if err
          resolve()

  checkPassword = (db) ->
    db.checkPasswordChangeNeeded()
    .then (needed) ->
      return unless needed
      password = crypto.createHash 'sha1'
        .update "#{Date.now()}#{Math.round Math.random() * 100000000}"
        .digest 'hex'
      db.changePassword password
      .then System.getSettings
      .then (settings) ->
        settings.username = settings.username ? defaultUsername
        settings.password = password
        System.updateSettings settings
    .then -> db

  registerModel = (db, Model) ->
    model = Model db
    db.models[model.name] = model
    Promise.all _.map (model.schema), (properties, key) ->
      return unless properties.unique
      db.createConstraint
        label: model.name
        property: key
    .catch (err) ->
      console.log 'failed to register constraints', err?.stack ? err
    model

  System.getSettings()
  .then (settings) ->
    # looks like first run, so delay to give service time to start up
    if !settings.password
      # console.log 'wait for it....'
      Promise.promise (resolve, reject) ->
        setTimeout ->
          # console.log 'okay, now try to connect to DB'
          resolve settings
        , 4000
    else
      # console.log 'try right away'
      settings
  .then getDB
  .then checkPassword
  .then (db) ->
    db.model = (Model) ->
      if typeof Model is 'string'
        db.models[Model]
      else if typeof Model is 'function'
        registerModel db, Model
    db
