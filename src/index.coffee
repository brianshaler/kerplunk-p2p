_ = require 'lodash'
request = require 'request'
openpgp = require 'openpgp'
Promise = require 'when'

Authorization = require './authorization'
EntityModel = require './models/Entity'

module.exports = (System) ->
  db = null
  socket = null

  myPublicKey = System.getMethod 'kerplunk-pgp', 'myPublicKey'

  getDB = System.getMethod 'kerplunk-graphdb', 'getDB'

  meCache = null

  getMe = ->
    return meCache if meCache
    Entity = db.model 'Entity'
    meCache = System.getSettings()
    .then (settings) ->
      unless settings.profile?.domain
        return meCache = Promise.reject new Error 'no domain in profile'
      Entity.findByDomain settings.profile.domain
      .then (entity) ->
        # console.log 'foundByDomain', entity, settings.profile.domain
        return entity if entity
        myPublicKey()
        .then (pubkey) ->
          entity = new Entity
            domain: settings.profile?.domain
            publicKey: pubkey
          entity.save()
    .catch (err) ->
      console.log 'something terrible has happened'
      console.log err?.stack ? err

  authorization = Authorization System, getMe

  updateMe = (profile) ->
    getMe()
    .catch (err) -> null
    .then (me) ->
      return me if me
      Entity = db.model 'Entity'
      myPublicKey()
      .then (pubkey) ->
        entity = new Entity
          domain: profile.domain
          publicKey: pubkey
        entity.save()
    .then (me) ->
      meCache = me.set profile

  getFriends = ->
    Promise.all [
      getDB()
      getMe()
    ]
    .then ([db, me]) ->
      Entity = db.model 'Entity'
      # me.getRelationships 'FOLLOWING', Entity.REL_BOTH
      me.getRelatedEntities
        relation: 'FOLLOWING'
        direction: Entity.REL_BOTH

  getFriendsDomains = ->
    Promise.all [
      getDB()
      getMe()
    ]
    .then ([db, me]) ->
      Entity = db.model 'Entity'
      # me.getRelationships 'FOLLOWING', Entity.REL_BOTH
      me.getRelatedEntitiesProp
        prop: 'domain'
        relation: 'FOLLOWING'
        direction: Entity.REL_BOTH

  getFollowingDomains = ->
    Promise.all [
      getDB()
      getMe()
    ]
    .then ([db, me]) ->
      Entity = db.model 'Entity'
      # me.getRelationships 'FOLLOWING', Entity.REL_BOTH
      me.getRelatedEntitiesProp
        prop: 'domain'
        relation: 'FOLLOWING'
        direction: Entity.REL_RIGHT

  getFriendsAndRequests = ->
    Entity = db.model 'Entity'
    getMe().then (me) ->
      # console.log 'me:', me.toObject()
      where = 'WHERE NOT (entity)-[:IGNORED]->(other)'
      me.getRelationshipsWhere where, 'FOLLOWING', Entity.REL_EITHER

  sendRequest = (req, res, next) ->
    return next() unless req.query?.domain
    domain = req.query?.domain ? req.body?.domain
    Entity = db.model 'Entity'
    Promise.all [
      System.getSettings()
      getMe()
    ]
    .then ([settings, me]) ->
      url = "https://#{domain}/connect/request.json"
      localhost = settings.profile.domain
      throw new Error 'unable to determine localhost' unless localhost
      console.log 'url', url
      options =
        rejectUnauthorized: false
        body: me.toObject()
        json: true
      # console.log 'options', options
      Promise.promise (resolve, reject) ->
        request.post url, options, (err, response, body) ->
          # console.log 'body', body
          return reject err if err
          return reject new Error 'no body' unless body
          if !body.publicKey
            return reject new Error 'no publicKey returned'
          resolve
            domain: domain
            body: body
      .then (data) ->
        friend = new Entity
          domain: data.domain
          publicKey: data.body.publicKey
        friend.save()
        .then ->
          me.relate friend.domain, 'FOLLOWING', Entity.REL_RIGHT
        .then ->
          friend.getRelationshipsWith me.domain, 'FOLLOWING', Entity.REL_EITHER
        .then (rels) ->
          obj = friend.toObject()
          obj.following = false
          obj.follower = false
          return obj unless rels?.length > 0
          for rel in rels
            if rel[0].domain == me.domain
              obj.following = true
            else if rel[0].domain == friend.domain
              obj.follower = true
          # console.log 'friend rel data', rels
          obj
    .done (friendObj) ->
      # console.log 'broadcast', friendObj
      socket.broadcast friendObj
      res.send
        message: 'ok'
        friend: friendObj
    , (err) ->
      next err

  handleRequest = (req, res, next) ->
    domain = req.body?.domain ? req.query?.domain
    publicKey = req.body?.publicKey ? req.query?.publicKey
    return next new Error 'domain and publicKey required' unless domain and publicKey
    Entity = db.model 'Entity'
    Entity.findByDomain domain
    .then (friend) ->
      return friend if friend
      friend = new Entity
        domain: domain
    .then (friend) ->
      friend.publicKey = publicKey
      friend.save()
    .then (friend) ->
      getMe().then (me) ->
        me.relate friend.domain, 'FOLLOWING', Entity.REL_LEFT
      .then (me) ->
        me.getRelationshipsWith friend.domain, 'FOLLOWING', Entity.REL_EITHER
        .then (rels) ->
          obj = friend.toObject()
          obj.following = false
          obj.follower = false
          return obj unless rels?.length > 0
          for rel in rels
            if rel[0].domain == me.domain
              obj.following = true
            else if rel[0].domain == friend.domain
              obj.follower = true
          # console.log 'friend rel data', rels, obj
          obj
    .then (friendObj) ->
      # console.log 'broadcast', friendObj
      socket.broadcast friendObj
      myPublicKey()
    .done (pubkey) ->
      res.send
        message: 'ok'
        publicKey: pubkey
    , (err) ->
      next err

  routes:
    admin:
      '/admin/p2p/settings': 'settings'
      '/admin/p2p/connect': 'connect'
      '/admin/p2p/connect/request': 'sendRequest'
      '/admin/p2p/clear': 'clear'
      '/connect/acknowledge': 'acknowledge'
    public:
      '/connect/request': 'handleRequest'
      '/connect/test': 'testAuth'
      '/connect/auth': 'authenticationRedirect'
      '/connect/verify': 'verify'
      '/connect/logout': 'logout'
      '/connect/publickey': 'publickey'
    friend:
      '/connect/private': 'testPrivate'

  auth:
    friend: authorization.authorize

  handlers:
    settings: (req, res, next) ->
      System.getSettings()
      .then (settings) ->
        return settings unless req.body?.domain?.length > 0
        settings.profile = {} unless settings.profile
        _.merge settings.profile, req.body
        System.updateSettings settings
        .then ->
          # console.log 'update me'
          updateMe settings.profile
        .then -> settings
      .then (settings) ->
        getMe()
        .catch (err) -> {}
        .then (me) ->
          res.render 'settings',
            profile: settings.profile ? {}
            entity: me
    connect: (req, res, next) ->
      System.getSettings()
      .then (settings) ->
        unless settings.profile?.domain?.length > 0
          throw new Error 'No profile'
        Promise.all [
          getFriendsAndRequests()
          getMe()
        ]
        .then ([rels, me]) ->
          friends = _ rels
            .groupBy (rel) ->
              if rel[0]?.domain == me?.domain
                rel[2]?.domain
              else
                rel[0]?.domain
            .map (rels) ->
              friendEntity = if rels[0][0]?.domain == me?.domain
                rels[0][2]
              else
                rels[0][0]
              friend = friendEntity.toObject()
              friend.following = false
              friend.follower = false
              for rel in rels
                if rel[0]?.domain == me?.domain
                  friend.following = true
                else if rel[2]?.domain == me?.domain
                  friend.follower = true
              friend
            .value()
          profile: settings.profile
          friends: friends
      .done (data) ->
        res.render 'connect', data
      , (err) ->
        console.log 'handling error'
        if err.message == 'No profile'
          return res.redirect '/admin/p2p/settings'
        next err
    sendRequest: sendRequest
    handleRequest: handleRequest
    clear: (req, res, next) ->
      db.cypher 'MATCH (entity:Entity)
        OPTIONAL MATCH (entity)-[rel]-()
        DELETE entity, rel'
      .done ->
        res.send
          message: 'cleared'
      , (err) -> next err

    publickey: (req, res, next) ->
      myPublicKey()
      .done (pubkey) ->
        res.send
          message: 'ok'
          publicKey: pubkey
      , (err) ->
        next err

    testAuth: (req, res, next) ->
      res.header 'Cache-Control', 'no-cache, no-store, must-revalidate'
      res.header 'Pragma', 'no-cache'
      res.render 'testAuth'
    authenticationRedirect: authorization.authenticationRedirect
    acknowledge: authorization.acknowledge
    verify: authorization.verify
    testPrivate: (req, res, next) ->
      res.header 'Cache-Control', 'no-cache, no-store, must-revalidate'
      res.header 'Pragma', 'no-cache'
      res.send
        message: 'hopefully this means we are friends.'
        userName: req.session.userName
    logout: (req, res, next) ->
      res.header 'Cache-Control', 'no-cache, no-store, must-revalidate'
      res.header 'Pragma', 'no-cache'
      redirectUri = req.query?.redirectUri ? '/'
      req.session.userName = ''
      req.session.sessionToken = ''
      req.session.isFriend = ''
      res.redirect redirectUri

  globals:
    public:
      nav:
        P2P:
          Settings: '/admin/p2p/settings'
          Connect: '/admin/p2p/connect'
      preContent:
        p2p: 'kerplunk-p2p:testAuth'

  methods:
    getMe: getMe
    getFriends: getFriends
    getFriendsDomains: getFriendsDomains
    getFollowingDomains: getFollowingDomains

  init: (next) ->
    socket = System.getSocket 'p2p'
    # socket.on 'receive', (spark, data) ->
    #   console.log 'client said what?', data
    # socket.on 'connection', (spark, data) ->
    #   console.log 'p2p connection'
    setup = ->
      getDB()
      .then (_db) ->
        db = _db
        # console.log 'got db', db
        Entity = db.model EntityModel
        getMe()
    setup()
    .catch (err) ->
      console.log 'uhh.. p2p init', err?.stack ? err
      setTimeout setup, 7000
    next()
