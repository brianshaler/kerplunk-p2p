_ = require 'lodash'
request = require 'request'
openpgp = require 'openpgp'
Promise = require 'when'

FriendSchema = require './models/Friend'

myDomain = null

module.exports = (System) ->
  Friend = System.registerModel 'Friend', FriendSchema
  Identity = System.getModel 'Identity'

  socket = null

  myPublicKey = System.getMethod 'kerplunk-pgp', 'myPublicKey'
  myPrivateKey = System.getMethod 'kerplunk-pgp', 'myPrivateKey'

  getFriends = ->
    mpromise = Friend
    .where
      following: true
      requested: true
    .find()
    Promise mpromise

  getFriendsAndRequests = ->
    mpromise = Friend
    .where
      '$or': [
        {following: true}
        {ignored: false}
      ]
    .find()
    Promise mpromise

  sendRequest = (req, res, next) ->
    return next() unless req.query.domain
    domain = req.query?.domain ? req.body?.domain
    myPublicKey()
    .then (publicKey) ->
      url = "https://#{domain}/connect/request.json"
      localhost = req.headers?.host
      return next new Error 'unable to determine localhost' unless localhost
      console.log 'url', url
      options =
        rejectUnauthorized: false
        body:
          domain: localhost
          publicKey: publicKey
        json: true
      console.log 'options', options
      request.post url, options, (err, response, body) ->
        console.log 'body', body
        return next err if err
        return next new Error 'no body' unless body
        if !body.publicKey
          return res.send
            message: 'not really all that ok'
        Friend
        .where
          domain: domain
        .findOne (err, friend) ->
          return next err if err
          if friend
            friend.following = true
            friend.ignored = false
          else
            friend = new Friend
              domain: domain
              publicKey: body.publicKey
              following: true
              ignored: false
          friend.save (err) ->
            return next err if err
            socket.broadcast friend
            res.send
              message: 'ok'
              friend: friend
              body: body

  handleRequest = (req, res, next) ->
    domain = req.body?.domain ? req.query?.domain
    publicKey = req.body?.publicKey ? req.query?.publicKey
    return next new Error 'domain and publicKey required' unless domain and publicKey
    myPublicKey()
    .then (myPublicKey) ->
      Friend
      .where
        domain: domain
      .findOne (err, friend) ->
        return next err if err
        data =
          message: 'ok'
          publicKey: myPublicKey
        if friend
          friend.requested = true
          friend.requestedAt = new Date()
        else
          friend = new Friend
            domain: domain
            publicKey: publicKey
            following: false
            requested: true
            ignored: false
            requestedAt: new Date()
        friend.save (err) ->
          return next err if err
          socket.broadcast friend
          res.send data

  askFriend = (friendDomain, query, parameters, degrees = 0, omit = []) ->
    console.log 'askFriend', myDomain, '->', friendDomain
    url = "https://#{friendDomain}/connect/ask.json"
    timestamp = Date.now()

    myPrivateKey()
    .then (privateKeyText) ->
      privateKey = openpgp.key.readArmored privateKeyText
      privateKey = privateKey.keys[0]
      privateKey.decrypt('super long and hard to guess secret!')
      openpgp
      .signClearMessage [privateKey], "{#{myDomain}|#{timestamp}}"
    .then (signed) ->
      Promise.promise (resolve, reject) ->
        options =
          rejectUnauthorized: false
          body:
            domain: myDomain
            timestamp: timestamp
            signature: signed
            query: query
            parameters: JSON.stringify parameters
            degrees: degrees
            omit: _.compact(omit).join ','
          json: true
        request.post url, options, (err, response, body) ->
          return reject err if err
          return resolve body
          obj = {}
          obj[friendDomain] = body
          resolve obj

  askMyFriends = (query, parameters, degrees = 0, omit = []) ->
    console.log 'askFriends', myDomain
    getFriends()
    .then (friends) ->
      promises = _ friends
        .filter (friend) ->
          omit.indexOf(friend.domain) == -1
        .map (friend) ->
          askFriend friend.domain, query, parameters, degrees, omit
          .then (result) ->
            domain: friend.domain
            answer: result
        .value()
      Promise.all promises

  answer = (query, parameters) ->
    console.log 'my answer', query, parameters
    emptyResult = ->
      parameters: parameters
      answer: null
    System.do "ask.#{query}", emptyResult()
    .catch (err) ->
      console.log 'oops', err
      emptyResult()
    .then (result) ->
      domain: myDomain
      answer: result.answer

  ask = (req, res, next) ->
    console.log 'ask', req.body
    myDomain = myDomain ? req.headers?.host
    query = req.query?.query ? req.body?.query
    parametersString = req.query?.parameters ? req.body?.parameters
    try
      parameters = JSON.parse parametersString
    catch ex
      console.log "couldn't parse #{parametersString}", ex
      parameters = {}
    degrees = parseInt (req.query?.degrees ? req.body?.degrees)
    degrees = 0 unless degrees > 0
    omit = req.query?.omit ? req.body?.omit
    omit = '' unless omit
    omit = omit.split ','
    omit.push myDomain
    promises = []
    promises.push answer query, parameters
    if degrees > 0
      promises.push askMyFriends query, parameters, degrees - 1, omit
    Promise.all promises
    .then (results) ->
      [firstResult, otherResults...] = results
      console.log 'results', results
      console.log 'firstResult', firstResult
      console.log 'otherResults', otherResults
      friends = _ otherResults
        .flatten()
        .compact()
        .reduce (memo, result) ->
          memo[result.domain] = result.answer
          memo
        , {}
      obj =
        answer: firstResult.answer
        friends: friends
      console.log 'obj', obj
      res.send obj

  authorise = ->
    (req, res, next) ->
      signature = req.query?.signature ? req.body?.signature
      domain = req.query?.domain ? req.body?.domain
      timestamp = req.query?.timestamp ? req.body?.timestamp
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

      Friend
      .where
        domain: domain
        following: true
      .findOne (err, friend) ->
        return next err if err
        return next new Error 'not authorized' unless friend

        publicKey = openpgp.key.readArmored friend.publicKey
        message = openpgp.cleartext.readArmored signature
        openpgp
        .verifyClearSignedMessage publicKey.keys, message
        .then (pgpMessage) ->
          # console.log 'verified?', pgpMessage
          if pgpMessage?.signatures?[0]?.valid == true and pgpMessage.text == "{#{domain}|#{timestamp}}"
            next()
          else
            next new Error "signature issue"
        .catch (err) ->
          next err

  routes:
    admin:
      '/admin/p2p/connect': 'connect'
      '/admin/p2p/connect/request': 'sendRequest'
      '/admin/p2p/connect/testask': 'ask'
      '/admin/p2p/clear': 'clear'
    public:
      '/connect/request': 'handleRequest'
    friend:
      '/connect/test': 'private'
      '/connect/ask': 'ask'

  auth:
    friend: authorise

  handlers:
    connect: (req, res, next) ->
      getFriendsAndRequests()
      .done (friends) ->
        res.render 'connect',
          host: req.headers.host
          friends: friends
      , (err) ->
        next err
    sendRequest: sendRequest
    handleRequest: handleRequest
    private: (req, res, next) ->
      res.send
        private: true
    ask: ask
    clear: (req, res, next) ->
      Friend
      .where {}
      .remove (err) ->
        console.log arguments
        res.redirect '/admin/p2p/connect'

  globals:
    public:
      nav:
        P2P:
          Connect: '/admin/p2p/connect'

  events:
    ask:
      echo:
        do: (data) ->
          data.answer = data.parameters?.message ? 'no message?'
          data

  init: (next) ->
    socket = System.getSocket 'p2p'
    socket.on 'receive', (spark, data) ->
      console.log 'client said what?', data
    socket.on 'connection', (spark, data) ->
      console.log 'p2p connection'
    next()
