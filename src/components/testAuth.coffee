_ = require 'lodash'
React = require 'react'

{DOM} = React

module.exports = React.createFactory React.createClass
  getInitialState: ->
    show: false
    redirectUri: ''

  componentDidMount: ->
    fullPath = [
      window.location.pathname
      window.location.search
      window.location.hash
    ].join ''
    console.log 'fullPath', fullPath
    @setState
      redirectUri: fullPath

  handleToggle: (e) ->
    e.preventDefault()
    @setState
      show: !@state.show

  render: ->
    DOM.div
      style:
        position: 'absolute'
        top: '0px'
        right: '0px'
        zIndex: '3'
      className: 'content'
    ,
      if @state.show
        if @props.friendDomain
          DOM.div null,
            DOM.h3 null, "Welcome #{@props.friendDomain}!"
            DOM.p null,
              DOM.a
                href: "/connect/logout?redirectUri=#{@state.redirectUri}"
              , 'logout'
        else
          DOM.form
            method: 'post'
            action: '/connect/auth'
          ,
            DOM.input
              type: 'hidden'
              name: 'redirectUri'
              value: @state.redirectUri
            DOM.input
              placeholder: 'domain'
              name: 'domain'
            DOM.input
              type: 'submit'
              value: 'auth'
      else
        DOM.a
          href: '#'
          onClick: @handleToggle
        ,
          if @props.friendDomain
            "logged in as #{@props.friendDomain}"
          else
            'log in'
