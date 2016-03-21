_ = require 'lodash'
React = require 'react'

{DOM} = React

Request = React.createFactory React.createClass
  handleFollow: (e) ->
    e.preventDefault()
    @props.onFollow @props.request.domain

  handleIgnore: (e) ->
    e.preventDefault()
    @props.onIgnore @props.request.domain

  render: ->
    # requestedAt = @props.request.requestedAt
    # if typeof requestedAt is 'string'
    #   requestedAt = new Date requestedAt
    DOM.p null,
      DOM.strong null, @props.request.domain
      # DOM.em null, " (#{requestedAt.toISOString()})"
      DOM.a
        href: '/admin/p2p/connect/reciprocate'
        onClick: @handleFollow
      , '[ add ]'
      DOM.a
        href: '/admin/p2p/connect/ignore'
        onClick: @handleIgnore
      , '[ ignore ]'

Friend = React.createFactory React.createClass
  render: ->
    DOM.p null,
      DOM.strong null, @props.friend.domain

module.exports = React.createFactory React.createClass
  getInitialState: ->
    value: false
    degrees: 1
    queryResults: null
    friends: @props.friends ? []

  componentDidMount: ->
    @socket = @props.getSocket 'p2p'
    @socket.on 'data', (data) =>
      return unless @isMounted()
      if data.domain
        found = false
        friends = _.map @state.friends, (friend) ->
          return friend unless friend.domain == data.domain
          found = true
          data
        if !found
          friends.push data
        @setState
          friends: friends
      else
        console.log 'wat'

  onFormSubmit: (e) ->
    e.preventDefault()
    @setState
      value: false
    domainName = React.findDOMNode(@refs.test).value
    console.log 'input', domainName
    @props.request.get '/admin/p2p/connect/request.json', {domain: domainName}, (err, data) =>
      console.log err, data
      @setState
        value: data

  onFollow: (domain) ->
    @props.request.get '/admin/p2p/connect/request.json', {domain: domain}, (err, data) =>
      friends = _.map @state.friends, (friend) ->
        return friend unless friend.domain == domain
        friend = _.clone friend, true
        friend.follower = true
        friend
        # friend.requestedAt = new Date()
      @setState
        friends: friends

  onIgnore: (domain) ->
    @props.request.get '/admin/p2p/connect/ignore.json', {domain: domain}, (err, data) =>
      friends = _.map @state.friends, (friend) ->
        return friend unless friend.domain == domain
        friend = _.clone friend, true
        friend.ignored = true
      @setState
        friends: friends

  onDegreesChange: (e) ->
    e.preventDefault()
    degrees = e.target.value
    if degrees != ''
      degrees = parseInt degrees
    @setState
      degrees: degrees

  onAsk: (e) ->
    e.preventDefault()
    query = React.findDOMNode(@refs.query).value
    parameters = React.findDOMNode(@refs.parameters).value
    reduction = React.findDOMNode(@refs.reduction).value
    url = '/admin/p2p/query/send.json'
    options =
      query: query
      parameters: parameters
      degrees: @state.degrees
      reduction: reduction
      json: true
    @setState
      queryResults: null
    console.log 'query', url, options
    @props.request.post url, options, (err, data) =>
      console.log 'answer', err, data
      @setState
        queryResults: data

  render: ->
    friends = _.filter @state.friends, (friend) ->
      friend.following and friend.follower
    pending = _.filter @state.friends, (friend) ->
      friend.following and !friend.follower
    requests = _.filter @state.friends, (friend) ->
      !friend.following and friend.follower
    DOM.section
      className: 'content'
    ,
      DOM.section
        className: 'col-lg-12'
      ,
        DOM.h3 null, "Connect (#{@props.profile.domain ? ''})"
        DOM.form
          onSubmit: @onFormSubmit
        ,
          DOM.input
            ref: 'test'
            placeholder: 'domain'
          DOM.input
            type: 'submit'
            value: 'add'
      DOM.section
        className: 'col-lg-3 col-md-4 col-sm-4'
      ,
        DOM.h3 null, 'Requests:'
        if requests?.length > 0
          DOM.div null,
            _.map requests, (req) =>
              Request
                key: "req-#{req.domain}"
                request: req
                onFollow: @onFollow
                onIgnore: @onIgnore
        else
          DOM.p null, 'none'
      DOM.section
        className: 'col-lg-3 col-md-4 col-sm-4'
      ,
        DOM.h3 null, 'Pending:'
        if pending?.length > 0
          DOM.div null,
            _.map pending, (pending) ->
              Friend
                key: "pending-#{pending.domain}"
                friend: pending
        else
          DOM.p null, 'none'
      DOM.section
        className: 'col-lg-3 col-md-4 col-sm-4'
      ,
        DOM.h3 null, 'Friends:'
        if friends?.length > 0
          DOM.div null,
            _.map friends, (friend) =>
              Friend _.extend {}, @props,
                key: "friend-#{friend.domain}"
                friend: friend
        else
          DOM.p null, 'none'
      DOM.hr
        style:
          width: '100%'
      , ' '
      DOM.section
        className: 'col-lg-12'
      ,
        DOM.h3 null, 'Test Query:'
        DOM.form
          method: 'post'
          action: '/connect/ask'
          onSubmit: @onAsk
        ,
          DOM.p null,
            'query: '
            DOM.input
              ref: 'query'
              defaultValue: 'echo'
              placeholder: 'query'
          DOM.p null,
            'parameters: '
            DOM.input
              ref: 'parameters'
              defaultValue: '{"message":"hi"}'
              placeholder: 'parameters'
          DOM.p null,
            'reduction: '
            DOM.input
              ref: 'reduction'
              defaultValue: 'tree'
              placeholder: '(e.g. tree, domain, other)'
          DOM.p null,
            'degrees: '
            DOM.input
              ref: 'degrees'
              value: @state.degrees
              onChange: @onDegreesChange
              placeholder: 'degrees'
          DOM.p null,
            DOM.input
              type: 'submit'
              value: 'ask'
        if @state.queryResults
          DOM.pre null, JSON.stringify @state.queryResults, null, 2
        else
          null
        DOM.div null,
          DOM.p null, 'Example queries'
          DOM.p null,
            'query: '
            DOM.input
              disabled: true
            , 'myPlaces'
          DOM.p null,
            'parameters: '
            DOM.input
              disabled: true
            , '{"lat":33.42,"lng":-111.94,"radius":1}'
          DOM.p null,
            'reduction: '
            DOM.input
              disabled: true
            , 'domain'
          DOM.hr()
          DOM.p null,
            'query: '
            DOM.input
              disabled: true
            , 'echo'
          DOM.p null,
            'parameters: '
            DOM.input
              disabled: true
            , '{"message":"hi"}'
          DOM.p null,
            'reduction: '
            DOM.input
              disabled: true
            , 'someId'
      DOM.section
        className: 'col-lg-12'
      ,
        DOM.a
          href: '/admin/p2p/clear'
        , 'clear'
