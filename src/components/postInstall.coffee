React = require 'react'

{DOM} = React

module.exports = React.createFactory React.createClass
  render: ->
    DOM.div null,
      # DOM.h4 null, 'Kerplunk P2P Installed'
      DOM.p null, 'Groovy!'
      DOM.p null,
        'Now connect with your friends by going to '
        DOM.a
          href: '/admin/p2p/connect'
          onClick: @props.pushState
        , 'P2P > Connect'
