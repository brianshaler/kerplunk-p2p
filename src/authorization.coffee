crypto = require 'crypto'

_ = require 'lodash'
Promise = require 'when'
openpgp = require 'openpgp'
request = require 'request'

hash = (str) ->
  h = crypto.createHash 'sha1'
  h.update str
  h.digest 'base64'

module.exports = (System, getMe) ->
  getDB = System.getMethod 'kerplunk-graphdb', 'getDB'
  signClearMessage = System.getMethod 'kerplunk-pgp', 'signClearMessage'

  verifySignedMessage = (message, publicKey, signature) ->
    publicKey = openpgp.key.readArmored publicKey
    signedMessage = openpgp.cleartext.readArmored signature
    openpgp
    .verifyClearSignedMessage publicKey.keys, signedMessage
    .then (pgpMessage) ->
      # console.log 'verified?', pgpMessage
      return false unless pgpMessage?.signatures?[0]?.valid == true
      return false unless pgpMessage.text == message
      true

  fetchPublicKey = (domain) ->
    url = "https://#{domain}/connect/publickey.json"
    Promise.promise (resolve, reject) ->
      options =
        rejectUnauthorized: false
        json: true
      request.post url, options, (err, response, body) ->
        # console.log 'body', body
        return reject err if err
        return reject new Error 'no body' unless body
        if typeof body is 'string'
          try
            body = JSON.parse body
          catch err
            return reject err
        unless body?.publicKey
          return reject new Error 'no publicKey returned'
        resolve
          domain: domain
          publicKey: body.publicKey

  recentlyFetched = {}
  getEntity = (domain) ->
    return recentlyFetched[domain] if recentlyFetched[domain]
    recentlyFetched[domain] = getDB()
    .then (db) ->
      Entity = db.model 'Entity'
      Entity.findByDomain domain
      .then (entity) ->
        return entity if entity
        fetchPublicKey domain
        .then (obj) ->
          throw new Error 'could not retrieve publicKey' unless obj?.publicKey
          entity = new Entity
            domain: domain
            name: domain
            publicKey: obj.publicKey
          entity.save()
    .catch (err) ->
      setTimeout ->
        recentlyFetched = {}
      , 2000
      throw err

  getFriend = (domain) ->
    Promise.all [
      getDB()
      getMe()
    ]
    .then ([db, me]) ->
      Entity = db.model 'Entity'
      me.getRelationshipsWith domain, 'FOLLOWING', Entity.REL_BOTH
      .then (rels) ->
        return unless rels?.length > 0
        friend = if rels[0][0]?.domain == me?.domain
          rels[0][2]
        else if rels[0][2]?.domain == me?.domain
          rels[0][0]

  authorizeSignature = (signature, domain, timestamp, next) ->
    try
      if typeof timestamp is 'string'
        if /^[\d]+$/.test timestamp
          timestamp = parseInt timestamp
        else
          date = Date.parse timestamp
          timestamp = date.getTime()
    catch ex
      return next ex
    unless 30 * 1000 > Math.abs Date.now() - timestamp
      return next new Error 'bad timestamp'

    getFriend domain
    .then (friend) ->
      if !friend?.publicKey
        console.log "no publicKey for #{domain}?", rels
      return unless friend?.publicKey
      friend
    .then (friend) ->
      return false unless friend?.publicKey
      msg = "{#{domain}|#{timestamp}}"
      verifySignedMessage msg, friend.publicKey, signature
    .done (isAuthorized) ->
      return next new Error 'not authorized' unless isAuthorized == true
      next()
    , (err) ->
      next err

  authorizeSession = (req, res, next) ->
    {userName, isFriend, sessionToken} = req.session

    console.log 'authorizeSession', userName, isFriend, sessionToken
    promise = if String(isFriend) is 'true'
      getFriend userName
      .then (friend) ->
        return unless friend?.sessionToken
        sessionToken: friend.sessionToken
        domain: friend.domain
        publicKey: friend.publicKey
        isFriend: true
    else
      getEntity userName
      .then (entity) ->
        return unless entity?.sessionToken
        sessionToken: entity.sessionToken
        domain: entity.domain
        publicKey: entity.publicKey
        isFriend: false

    promise.then (entity) ->
      if !entity?.sessionToken
        console.log "no sessionToken for #{userName}?", rels
      unless entity?.sessionToken?.length > 0 and sessionToken?.length > 0
        throw new Error 'not authorized'
      unless entity?.sessionToken == sessionToken
        throw new Error 'not authorized'
      domain: entity.domain
      verified: true
    .done (result) ->
      if result.verified == true
        return next()
      next new Error 'not authorized'
    , (err) ->
      next err

  authenticationRedirect = (req, res, next) ->
    domain = req.query?.domain ? req.body?.domain
    redirectUri = req.query?.redirectUri ? req.body?.redirectUri ? '/?2'
    unless domain?.length
      return next new Error 'domain is required'
    Promise.all [
      getMe()
      getEntity domain
    ]
    .then ([me, entity]) ->
      throw new Error 'error getting me..' unless me?.domain
      throw new Error 'domain not recognized' unless entity?.publicKey
      timestamp = "#{Date.now()}"
      signClearMessage timestamp
      .then (signature) ->
        console.log 'signature for '+timestamp, signature
        url = "https://#{entity.domain}/connect/acknowledge?"
        params =
          domain: me.domain
          redirectUri: redirectUri
          signature: signature
          timestamp: timestamp
        qs = _
          .map params, (val, key) ->
            "#{key}=#{encodeURIComponent val}"
          .join '&'
        url + qs
    .done (url) ->
      return next new Error 'umm.. no url?' unless url
      res.redirect url
    , (err) ->
      next err

  acknowledge = (req, res, next) ->
    domain = req.query?.domain ? req.body?.domain
    redirectUri = req.query?.redirectUri ? req.body?.redirectUri ? '/?2'
    signature = req.query?.signature ? req.body?.signature
    timestamp = req.query?.timestamp ? req.body?.timestamp

    baseUrl = "https://#{domain}/connect/verify"

    Promise.all [
      getMe()
      getEntity domain
    ]
    .then ([me, entity]) ->
      throw new Error 'domain not recognized' unless entity?.publicKey
      msg = timestamp
      verifySignedMessage msg, entity.publicKey, signature
      .then (verified) ->
        unless verified == true
          console.log 'verified?', verified
          console.log domain, signature, timestamp
        throw new Error 'not verified' unless verified == true
        signClearMessage 'v'
        .then (signedMessage) ->
          params =
            domain: me.domain
            signature: signedMessage
            redirectUri: redirectUri
          qs = _
            .map params, (val, key) ->
              "#{key}=#{encodeURIComponent val}"
            .join '&'
          "#{baseUrl}?#{qs}"
    .done (url) ->
      res.redirect url
    , (err) ->
      console.log 'auth failed', err
      url = baseUrl + "?error=#{encodeURIComponent 'auth failed'}"
      url += "&redirectUri=#{redirectUri}"
      res.redirect url

  verify = (req, res, next) ->
    domain = req.query?.domain ? req.body?.domain
    signature = req.query?.signature ? req.body?.signature
    redirectUri = req.query?.redirectUri ? req.body?.redirectUri ? '/?3'

    getFriend domain
    .then (friend) ->
      if friend?.publicKey
        obj =
          model: friend
          domain: friend.domain
          publicKey: friend.publicKey
          isFriend: true
        return obj
      getEntity domain
      .then (entity) ->
        model: entity
        domain: entity.domain
        publicKey: entity.publicKey
        isFriend: false
    .then (entity) ->
      throw new Error 'domain not recognized' unless entity?.publicKey
      msg = 'v'
      verifySignedMessage msg, entity.publicKey, signature
      .then (verified) ->
        unless verified == true
          console.log 'not verified?', verified
          console.log domain, signature, timestamp
        throw new Error 'message not verified' unless verified == true
        return false unless verified == true
        sessionToken = hash entity.domain + signature + entity.publicKey
        entity.model.set
          sessionToken: sessionToken
        .then ->
          req.session.sessionToken = sessionToken
          req.session.userName = entity.domain
          req.session.isFriend = String entity.isFriend
          true
    .done (verified) ->
      return next new Error 'verification failed' unless verified
      console.log 'redirect?', redirectUri, typeof redirectUri
      if redirectUri
        return res.redirect redirectUri
      res.send
        message: 'verified!'
    , (err) ->
      next err

  authorizeSignature: authorizeSignature
  authorizeSession: authorizeSession
  authenticationRedirect: authenticationRedirect
  acknowledge: acknowledge
  verify: verify
  authorize: ->
    (req, res, next) ->
      res.header 'Cache-Control', 'no-cache, no-store, must-revalidate'
      res.header 'Pragma', 'no-cache'
      signature = req.query?.signature ? req.body?.signature
      domain = req.query?.domain ? req.body?.domain
      timestamp = req.query?.timestamp ? req.body?.timestamp
      if signature and domain and timestamp
        return authorizeSignature signature, domain, timestamp, next
      if req.session.userName and req.session.sessionToken
        return authorizeSession req, res, next
      next new Error 'not authorized'
