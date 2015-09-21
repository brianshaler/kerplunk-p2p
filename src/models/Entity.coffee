_ = require 'lodash'
Promise = require 'when'

module.exports = (db) ->
  class Entity
    @name: 'Entity'
    @schema:
      name:
        type: String
        required: true
      domain:
        type: String
        required: true
      publicKey:
        type: String
      visibility:
        type: Number
        default: -> 1
      createdAt:
        type: Number
        default: Date.now

    constructor: (obj) ->
      defaults = {}
      for k, v of Entity.schema
        if typeof v.default is 'function'
          defaults[k] = v.default()
        else
          defaults[k] = v.default
      props = _.extend defaults, obj
      for k, v of props
        @[k] = v

    toObject: ->
      props = {}
      for k, v of Entity.schema
        props[k] = if typeof @[k] is 'object'
          _.clone @[k], true
        else
          @[k]
      props

    save: =>
      props = {}
      for k, v of Entity.schema
        props[k] = @[k]
      query = 'MERGE (entity:Entity {domain: {domain}})
        SET entity = {props}
        RETURN entity'
      db.cypher
        query: query
        params:
          domain: @domain
          props: props
      .then (data) => @

    set: (newProps) =>
      for k, v of newProps
        @[k] = v
      query = 'MATCH (entity:Entity {domain: {domain}})
        SET entity += {props}
        RETURN entity'
      db.cypher
        query: query
        params:
          domain: @domain
          props: newProps
      .then (data) => @

    @REL_EITHER: 0
    @REL_LEFT: 1
    @REL_RIGHT: 2
    @REL_BOTH: 3

    relate: (domain, rel, dir = Entity.REL_EITHER) =>
      dir = Entity.REL_EITHER unless dir > 0
      dir = Entity.REL_BOTH if dir > 3
      left = if (dir & 1) == 1 then '<' else ''
      right = if (dir & 2) == 2 then '>' else ''

      unless @domain?.length > 0
        console.log 'panic at relate', @

      query = "MATCH (entity:Entity {domain: {me}}),
          (other:Entity {domain: {other}})
        MERGE (entity)#{left}-[rel:#{rel}]-#{right}(other)
        RETURN entity"
      db.cypher
        query: query
        params:
          me: @domain
          other: domain ? ''
          rel: rel
      .then (data) => @

    getRelatedEntities: (opt = {}) =>
      rel = if opt.relation?.length > 0
        ":#{opt.relation}"
      else
        ''
      limit = opt.limit ? 100

      dir = opt.direction ? Entity.REL_EITHER
      dir = Entity.REL_EITHER unless dir > 0
      dir = Entity.REL_BOTH if dir > 3

      left = if (dir & 1) == 1 then '<' else ''
      right = if (dir & 2) == 2 then '>' else ''

      unless @domain?.length > 0
        console.log 'panic at getRelationships', @

      query = "MATCH (entity:Entity {domain: {me}})
          #{left}-[rel#{rel}]-#{right}
          (other:Entity)
        RETURN entity, rel, other
        LIMIT {limit}"

      db.cypher
        query: query
        params:
          me: @domain
          rel: rel
          limit: limit
      .then Entity.formatRelationships
      .then (rels) =>
        _ rels
        .groupBy (rel) =>
          if rel[0]?.domain == @domain
            rel[2]?.domain
          else
            rel[0]?.domain
        .map (rels) =>
          rel = rels[0]
          entity = if rel[0]?.domain == @domain
            rel[2]
          else
            rel[0]
          entity.relations = rels
          entity
        .value()

    getRelatedEntitiesProp: (opt = {}) =>
      rel = if opt.relation?.length > 0
        ":#{opt.relation}"
      else
        ''
      limit = opt.limit ? 100

      dir = opt.direction ? Entity.REL_EITHER
      dir = Entity.REL_EITHER unless dir > 0
      dir = Entity.REL_BOTH if dir > 3

      left = if (dir & 1) == 1 then '<' else ''
      right = if (dir & 2) == 2 then '>' else ''

      wheres = []
      if (dir & 1) == 1
        wheres.push "(entity:Entity {domain: {me}})
            <-[follower#{rel}]-
            (other:Entity)"
      if (dir & 2) == 2
        wheres.push "(entity:Entity {domain: {me}})
            -[following#{rel}]->
            (other:Entity)"

      query = "MATCH #{wheres.join ', '}
        RETURN other.#{opt.prop} AS #{opt.prop}
        LIMIT {limit}"

      db.cypher
        query: query
        params:
          me: @domain
          rel: rel
          prop: "other.#{opt.prop}"
          limit: limit
      .then (rels) ->
        return [] unless rels?.length > 0
        _.pluck rels, opt.prop

    getRelationships: (rel = '', dir = Entity.REL_EITHER, limit = 100) =>
      dir = Entity.REL_EITHER unless dir > 0
      dir = Entity.REL_BOTH if dir > 3

      left = if (dir & 1) == 1 then '<' else ''
      right = if (dir & 2) == 2 then '>' else ''

      unless @domain?.length > 0
        console.log 'panic at getRelationships', @

      if rel.length > 0 and rel.charAt(0) != ':'
        rel = ":#{rel}"

      query = "MATCH (entity:Entity {domain: {me}})
          #{left}-[rel#{rel}]-#{right}
          (other:Entity)
        RETURN entity, rel, other
        LIMIT {limit}"

      db.cypher
        query: query
        params:
          me: @domain
          rel: rel
          limit: limit
      .then Entity.formatRelationships

    getRelationshipsWith: (domain, rel = '', dir = Entity.REL_EITHER, limit = 100) =>
      dir = Entity.REL_EITHER unless dir > 0
      dir = Entity.REL_BOTH if dir > 3

      left = if (dir & 1) == 1 then '<' else ''
      right = if (dir & 2) == 2 then '>' else ''

      unless @domain?.length > 0
        console.log 'panic at getRelationshipsWith', @, domain

      if rel.length > 0 and rel.charAt(0) != ':'
        rel = ":#{rel}"

      query = "MATCH (entity:Entity {domain: {me}})
          #{left}-[rel#{rel}]-#{right}
          (other:Entity {domain: {domain}})
        RETURN entity, rel, other
        LIMIT {limit}"

      db.cypher
        query: query
        params:
          me: @domain
          rel: rel
          domain: domain
          limit: limit
      .then Entity.formatRelationships

    getRelationshipsWhere: (where, rel = '', dir = Entity.REL_EITHER, limit = 100) =>
      dir = Entity.REL_EITHER unless dir > 0
      dir = Entity.REL_BOTH if dir > 3

      left = if (dir & 1) == 1 then '<' else ''
      right = if (dir & 2) == 2 then '>' else ''

      unless @domain?.length > 0
        console.log 'panic at getRelationshipsWhere', @

      if rel.length > 0 and rel.charAt(0) != ':'
        rel = ":#{rel}"

      query = "MATCH (entity:Entity {domain: {me}})
          #{left}-[rel#{rel}]-#{right}
          (other:Entity)
        #{where}
        RETURN entity, rel, other
        LIMIT {limit}"

      db.cypher
        query: query
        params:
          me: @domain
          rel: rel
          limit: limit
      .then Entity.formatRelationships

    @getRelationshipsByDomain: (domain, rel = '', dir = Entity.REL_EITHER, limit = 100) =>
      dir = Entity.REL_EITHER unless dir > 0
      dir = Entity.REL_BOTH if dir > 3

      left = if (dir & 1) == 1 then '<' else ''
      right = if (dir & 2) == 2 then '>' else ''

      if rel.length > 0 and rel.charAt(0) != ':'
        rel = ":#{rel}"

      query = "MATCH (entity:Entity {domain: {domain}})
          #{left}-[rel#{rel}]-#{right}
          (other)
        RETURN entity, rel, other
        LIMIT {limit}"

      db.cypher
        query: query
        params:
          domain: domain
          rel: rel
          limit: limit
      .then Entity.formatRelationships

    @formatRelationships: (rels) ->
      return [] unless rels?.length > 0
      entities = {}
      getEntity = (obj) ->
        return entities[obj.domain] if entities[obj.domain]
        entities[obj.domain] = new Entity obj

      _.map rels, (row) ->
        if row.rel._fromId == row.entity._id
          [
            getEntity row.entity.properties
            row.rel.type
            getEntity row.other.properties
          ]
        else
          [
            getEntity row.other.properties
            row.rel.type
            getEntity row.entity.properties
          ]

    @findByDomain: (domain) ->
      query = 'MATCH (entity:Entity {domain: {domain}})
        RETURN entity'
      db.cypher
        query: query
        params:
          domain: domain
      .then (data) ->
        return unless data?[0]?.entity?.properties
        # console.log 'raw result', data?[0]?.entity.properties
        new Entity data[0].entity.properties
