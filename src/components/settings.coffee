_ = require 'lodash'
React = require 'react'

{DOM} = React

module.exports = React.createFactory React.createClass
  getInitialState: ->
    hostname: null
    profile: @props.profile
    domain: @props.profile.domain
    visibility: @props.profile.visibility ? @props.entity?.visibility
    entity: @props.entity

  componentDidMount: ->
    @setState
      hostname: window.location.hostname

  saveSettings: (settings) ->
    url = '/admin/p2p/settings.json'
    @props.request.post url, settings, (err, data) =>
      return unless @isMounted()
      if data?.state?.profile
        profile = _.extend {}, @state.profile, data.state.profile
        @setState
          profile: profile
          domain: profile.domain
          visibility: profile.visibility
          entity: data.state.entity ? @state.entity
      console.log 'result', err, data

  onDomainChange: (e) ->
    @setState
      domain: e.target.value

  onFormSubmit: (e) ->
    e.preventDefault()
    domain = React.findDOMNode(@refs.domain).value
    visibility = parseInt React.findDOMNode(@refs.visibility).value
    visibility = 1 unless visibility > 1
    settings =
      domain: domain
      visibility: visibility
    console.log 'update profile', settings
    @saveSettings settings
    return

  setDomain: (domain) ->
    (e) =>
      e.preventDefault()
      console.log 'set domain to', domain
      @saveSettings
        domain: domain

  render: ->
    DOM.section
      className: 'content'
    ,
      DOM.h3 null, "Settings"
      DOM.form
        onSubmit: @onFormSubmit
      ,
        DOM.p null,
          DOM.input
            ref: 'domain'
            placeholder: 'domain'
            name: 'domain'
            value: @state.domain
            onChange: @onDomainChange
        if !@state.profile.domain and @state.hostname
          DOM.p null,
            DOM.a
              href: '#'
              onClick: @setDomain @state.hostname
            , "set domain to #{@state.hostname}"
        else
          null
        DOM.p null,
          DOM.input
            ref: 'visibility'
            placeholder: 'visibility (degrees)'
            name: 'visibility'
            defaultValue: @state.visibility
        DOM.p null,
          DOM.input
            type: 'submit'
            value: 'save'
      DOM.pre null,
        JSON.stringify @state.entity, null, 2
