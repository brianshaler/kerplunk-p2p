crypto = require 'crypto'

_ = require 'lodash'
Promise = require 'when'
openpgp = require 'openpgp'

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
    {friendDomain, sessionToken} = req.session

    console.log 'authorizeSession', friendDomain, sessionToken
    getFriend friendDomain
    .then (friend) ->
      if !friend?.sessionToken
        console.log "no sessionToken for #{friendDomain}?", rels
      unless friend?.sessionToken?.length > 0 and sessionToken?.length > 0
        throw new Error 'not authorized'
      unless friend?.sessionToken == sessionToken
        throw new Error 'not authorized'
      domain: friend.domain
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
      getFriend domain
    ]
    .then ([me, friend]) ->
      throw new Error 'error getting me..' unless me?.domain
      throw new Error 'domain not recognized' unless friend?.publicKey
      timestamp = "#{Date.now()}"
      signClearMessage timestamp
      .then (signature) ->
        console.log 'signature for '+timestamp, signature
        url = "https://#{friend.domain}/connect/acknowledge?"
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
      getFriend domain
    ]
    .then ([me, friend]) ->
      throw new Error 'domain not recognized' unless friend?.publicKey
      msg = timestamp
      verifySignedMessage msg, friend.publicKey, signature
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

    Promise.all [
      getFriend domain
    ]
    .then ([friend]) ->
      throw new Error 'domain not recognized' unless friend?.publicKey
      msg = 'v'
      verifySignedMessage msg, friend.publicKey, signature
      .then (verified) ->
        unless verified == true
          console.log 'not verified?', verified
          console.log domain, signature, timestamp
        throw new Error 'message not verified' unless verified == true
        return false unless verified == true
        sessionToken = hash friend.domain + signature + friend.publicKey
        friend.set
          sessionToken: sessionToken
        .then ->
          req.session.sessionToken = sessionToken
          req.session.friendDomain = friend.domain
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
      if req.session.friendDomain and req.session.sessionToken
        return authorizeSession req, res, next
      next new Error 'not authorized'
