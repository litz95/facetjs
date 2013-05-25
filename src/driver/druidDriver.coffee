`(typeof window === 'undefined' ? {} : window)['druidDriver'] = (function(module, require){"use strict"; var exports = module.exports`

async = require('async')
driverUtil = require('./driverUtil')

# -----------------------------------------------------

# Open source Druid issues:
# - add limit to groupBy

makeFilter = (attribute, value) ->
  if Array.isArray(value)
    return { type: 'within', attribute, range: value }
  else
    return { type: 'is', attribute, value }

andFilters = (filters...) ->
  filters = filters.filter((filter) -> filter?)
  switch filters.length
    when 0
      return null
    when 1
      return filters[0]
    else
      return { type: 'and', filters }

rangeToDruidInterval = (interval) ->
  return interval.map((d) -> d.toISOString().replace('Z', '')).join('/')


class DruidQueryBuilder
  @ALL_DATA_CHUNKS = 10000
  @allTimeInterval = ["1000-01-01/3000-01-01"]

  constructor: (@dataSource, @timeAttribute, @forceInterval, @approximate) ->
    throw new Error("must have a dataSource") unless typeof @dataSource is 'string'
    throw new Error("must have a timeAttribute") unless typeof @timeAttribute is 'string'
    @queryType = 'timeseries'
    @granularity = 'all'
    @filter = null
    @aggregations = []
    @postAggregations = []
    @nameIndex = 0
    @intervals = null
    @useCache = true

  dateToIntervalPart: (date) ->
    return date.toISOString()
      .replace('Z',    '') # remove Z
      .replace('.000', '') # millis if 0
      .replace(/:00$/, '') # remove seconds if 0
      .replace(/:00$/, '') # remove minutes if 0
      .replace(/T00$/, '') # remove hours if 0

  unionIntervals: (intervals) ->
    null # ToDo

  intersectIntervals: (intervals) ->
    # ToDo: rewrite this to actually work
    startTime = -Infinity
    endTime = Infinity
    for interval in intervals
      intStart = interval[0].start.valueOf()
      intEnd = interval[0].end.valueOf()
      if startTime < intStart
        startTime = intStart
      if intEnd < endTime
        endTime = intEnd
    return null unless isFinite(startTime) and isFinite(endTime)
    ret = [{
      start: new Date(startTime)
      end: new Date(endTime)
    }]
    return ret

  addToContext: (context, attribute) ->
    if context[attribute]
      return context[attribute]

    context[attribute] = "v#{@jsCount}"
    @jsCount++
    return context[attribute]

  # return { jsFilter, context }
  filterToJSHelper: (filter, context) ->
    switch filter.type
      when 'is'
        throw new Error("can not filter on specific time") if filter.attribute is @timeAttribute
        varName = @addToContext(context, filter.attribute)
        "#{varName}==='#{filter.value}'"

      when 'in'
        throw new Error("can not filter on specific time") if filter.attribute is @timeAttribute
        varName = @addToContext(context, filter.attribute)
        filter.values.map((value) -> "#{varName}==='#{value}'").join('||')

      when 'not'
        "!(#{@filterToJSHelper(filter.filter, context)})"

      when 'and'
        filter.filters.map(((filter) -> "(#{@filterToJSHelper(filter, context)})"), this).join('&&')

      when 'or'
        filter.filters.map(((filter) -> "(#{@filterToJSHelper(filter, context)})"), this).join('||')

      else
        throw new Error("unknown JS filter type '#{filter.type}'")

  filterToJS: (filter) ->
    context = {}
    @jsCount = 0
    jsFilter = @filterToJSHelper(filter, context)
    return {
      jsFilter
      context
    }

  # return a (up to) two element array [druid_filter_object, druid_intervals_array]
  filterToDruid: (filter) ->
    switch filter.type
      when 'is'
        throw new Error("can not filter on specific time") if filter.attribute is @timeAttribute
        [{
          type: 'selector'
          dimension: filter.attribute
          value: filter.value
        }]

      when 'in'
        throw new Error("can not filter on specific time") if filter.attribute is @timeAttribute
        [{
          type: 'or'
          fields: filter.values.map(((value) ->
            return {
              type: 'selector'
              dimension: filter.attribute
              value
            }
          ), this)
        }]

      when 'fragments'
        throw new Error("can not fragments filter time") if filter.attribute is @timeAttribute
        [{
          type: "search"
          dimension: filter.attribute
          query: {
            type: "fragment"
            values: filter.fragments
          }
        }]

      when 'match'
        throw new Error("can not match filter time") if filter.attribute is @timeAttribute
        [{
          type: "regex"
          dimension: filter.attribute
          pattern: filter.expression
        }]

      when 'within'
        [r0, r1] = filter.range
        if filter.attribute is @timeAttribute
          r0 = new Date(r0) if typeof r0 is 'string'
          r1 = new Date(r1) if typeof r1 is 'string'
          throw new Error("start and end must be dates") unless r0 instanceof Date and r1 instanceof Date
          throw new Error("invalid dates") if isNaN(r0) or isNaN(r1)
          [
            null,
            [{ start: r0, end: r1 }]
          ]
        else if typeof r0 is 'number' and typeof r1 is 'number'
          [{
            type: 'javascript'
            dimension: filter.attribute
            function: "function(a){return a=~~a,#{r0}<=a&&a<#{r1};}"
          }]
        else
          throw new Error("has to be a numeric range")

      when 'not'
        [f, i] = @filterToDruid(filter.filter)
        throw new Error("can not use a 'not' filter on a time interval") if i
        [{
          type: 'not'
          field: f
        }]

      when 'and'
        fis = filter.filters.map(@filterToDruid, this)
        druidFields = fis.map((d) -> d[0]).filter((d) -> d?)
        druidIntervals = fis.map((d) -> d[1]).filter((d) -> d?)
        druidFilter = switch druidFields.length
          when 0 then null
          when 1 then druidFields[0]
          else { type: 'and', fields: druidFields }
        [
          druidFilter
          @intersectIntervals(druidIntervals)
        ]

      when 'or'
        fis = filter.filters.map(@filterToDruid, this)
        for [f, i] in fis
          throw new Error("can not 'or' time... yet") if i # ToDo
        [{
          type: 'or'
          fields: fis.map((d) -> d[0]).filter((d) -> d?)
        }]

      else
        throw new Error("filter type '#{filter.type}' not defined")

  addFilter: (filter) ->
    return unless filter
    [@filter, intervals] = @filterToDruid(filter)
    if intervals
      @intervals = intervals.map((({start, end}) -> "#{@dateToIntervalPart(start)}/#{@dateToIntervalPart(end)}"), this)
    return this

  addSplit: (split) ->
    switch split.bucket
      when 'identity'
        @queryType = 'groupBy'
        #@granularity stays 'all'
        @dimension = {
          type: 'default'
          dimension: split.attribute
          outputName: split.name
        }

      when 'timePeriod'
        throw new Error("timePeriod split can only work on '#{@timeAttribute}'") if split.attribute isnt @timeAttribute
        throw new Error("invalid period") unless split.period
        #@queryType stays 'timeseries'
        @granularity = {
          type: "period"
          period: split.period
          timeZone: split.timezone
        }

      when 'timeDuration'
        throw new Error("timeDuration split can only work on '#{@timeAttribute}'") if split.attribute isnt @timeAttribute
        throw new Error("invalid duration") unless split.duration
        #@queryType stays 'timeseries'
        @granularity = {
          type: "duration"
          duration: split.duration
        }

      when 'continuous'
        throw new Error("approximate queries not allowed") unless @approximate
        #@queryType stays 'timeseries'
        #@granularity stays 'all'
        aggregation = {
          type: "approxHistogramFold"
          fieldName: split.attribute
        }
        aggregation.lowerLimit = split.lowerLimit if split.lowerLimit?
        aggregation.upperLimit = split.upperLimit if split.upperLimit?

        tempHistogramName = @addAggregation(aggregation)
        @addPostAggregation {
          type: "buckets"
          name: "histogram"
          fieldName: tempHistogramName
          bucketSize: split.size
          offset: split.offset
        }
        #@useCache = false

      when 'tuple'
        throw new Error("only supported tuples of size 2 (is: #{split.splits.length})") unless split.splits.length is 2
        @queryType = 'heatmap'
        #@granularity stays 'all'
        @dimensions = split.splits.map (split) -> {
          dimension: split.attribute
          threshold: 10 # arbitrary value to be updated later
        }

      else
        throw new Error("unsupported bucketing function")

    return this

  throwawayName: ->
    @nameIndex++
    return "_f#{@nameIndex}"

  isThrowawayName: (name) ->
    return name[0] is '_'

  renameAggregationInPostAgregation: (postAggregation, from, to) ->
    switch postAggregation.type
      when 'fieldAccess', 'quantile'
        if postAggregation.fieldName is from
          postAggregation.fieldName = to

      when 'arithmetic'
        for postAgg in postAggregation.fields
          @renameAggregationInPostAgregation(postAgg, from, to)

      when 'constant'
        null # do nothing

      else
        throw new Error("unsupported postAggregation type '#{postAggregation.type}'")
    return

  addAggregation: (aggregation) ->
    aggregation.name or= @throwawayName()

    for existingAggregation in @aggregations
      if existingAggregation.type is aggregation.type and
         existingAggregation.fieldName is aggregation.fieldName and
         String(existingAggregation.fieldNames) is String(aggregation.fieldNames) and
         existingAggregation.fnAggregate is aggregation.fnAggregate and
         existingAggregation.fnCombine is aggregation.fnCombine and
         existingAggregation.fnReset is aggregation.fnReset and
         (@isThrowawayName(existingAggregation.name) or @isThrowawayName(aggregation.name))

        if @isThrowawayName(aggregation.name)
          # Use the existing aggregation
          return existingAggregation.name
        else
          # We have a throwaway existing aggregation, replace it's name with my non throwaway name
          for postAggregation in @postAggregations
            @renameAggregationInPostAgregation(postAggregation, existingAggregation.name, aggregation.name)
          existingAggregation.name = aggregation.name
          return aggregation.name

    @aggregations.push(aggregation)
    return aggregation.name

  addPostAggregation: (postAggregation) ->
    throw new Error("direct postAggregation must have name") unless postAggregation.name

    # We need this because of an asymmetry in druid, hopefully soon we will be able to remove this.
    if postAggregation.type is 'arithmetic' and not postAggregation.name
      postAggregation.name = @throwawayName()

    @postAggregations.push(postAggregation)
    return

  # This method will ether return a post aggregation or add it.
  addApplyHelper: do ->
    arithmeticToDruidFn = {
      add: '+'
      subtract: '-'
      multiply: '*'
      divide: '/'
    }
    aggregateToJS = {
      count: ['0', (a, b) -> "#{a}+#{b}"]
      sum:   ['0', (a, b) -> "#{a}+#{b}"]
      min:   ['Infinity',  (a, b) -> "Math.min(#{a},#{b})"]
      max:   ['-Infinity', (a, b) -> "Math.max(#{a},#{b})"]
    }
    return (apply, returnPostAggregation) ->
      applyName = apply.name or @throwawayName()
      if apply.aggregate
        switch apply.aggregate
          when 'constant'
            postAggregation = {
              type: "constant"
              value: apply.value
            }
            if returnPostAggregation
              return postAggregation
            else
              postAggregation.name = applyName
              @addPostAggregation(postAggregation)
              return

          when 'count', 'sum', 'min', 'max'
            if apply.filter
              { jsFilter, context } = @filterToJS(apply.filter)
              fieldNames = []
              varNames = []
              for fieldName, varName of context
                fieldNames.push(fieldName)
                varNames.push(varName)

              [zero, jsAgg] = aggregateToJS[apply.aggregate]

              if apply.aggregate is 'count'
                jsIf = "(#{jsFilter}?1:#{zero})"
              else
                fieldNames.push(apply.attribute)
                varNames.push('a')
                jsIf = "(#{jsFilter}?a:#{zero})"

              aggregation = {
                type: "javascript"
                name: applyName
                fieldNames: fieldNames
                fnAggregate: "function(cur,#{varNames.join(',')}){return #{jsAgg('cur', jsIf)};}"
                fnCombine: "function(pa,pb){return #{jsAgg('pa', 'pb')};}"
                fnReset: "function(){return #{zero};}"
              }
            else
              aggregation = {
                type: if apply.aggregate is 'sum' then 'doubleSum' else apply.aggregate
                name: applyName
              }

              if apply.aggregate isnt 'count'
                throw new Error("#{apply.aggregate} must have an attribute") unless apply.attribute
                aggregation.fieldName = apply.attribute

            aggregationName = @addAggregation(aggregation)
            if returnPostAggregation
              return { type: "fieldAccess", fieldName: aggregationName }
            else
              return

          when 'uniqueCount'
            throw new Error("approximate queries not allowed") unless @approximate
            throw new Error("can not filter a uniqueCount") if apply.filter

            # ToDo: add a throw here in case approximate is false
            aggregation = {
              type: "hyperUnique"
              name: applyName
              fieldName: apply.attribute
            }

            aggregationName = @addAggregation(aggregation)
            if returnPostAggregation
              # hyperUniqueCardinality is the fieldAccess equivalent for uniques
              return { type: "hyperUniqueCardinality", fieldName: aggregationName }
            else
              return

          when 'average'
            throw new Error("can not filter an average right now") if apply.filter

            sumAggregationName = @addAggregation {
              type: 'doubleSum'
              fieldName: apply.attribute
            }

            countAggregationName = @addAggregation {
              type: 'count'
            }

            postAggregation = {
              type: "arithmetic"
              fn: "/"
              fields: [
                { type: "fieldAccess", fieldName: sumAggregationName }
                { type: "fieldAccess", fieldName: countAggregationName }
              ]
            }

            if returnPostAggregation
              return postAggregation
            else
              postAggregation.name = applyName
              @addPostAggregation(postAggregation)
              return

          when 'quantile'
            throw new Error("approximate queries not allowed") unless @approximate
            throw new Error("quantile apply must have quantile") unless apply.quantile

            histogramAggregationName = @addAggregation {
              type: "approxHistogramFold"
              fieldName: apply.attribute
            }
            postAggregation = {
              type: "quantile"
              fieldName: histogramAggregationName
              probability: apply.quantile
            }

            if returnPostAggregation
              return postAggregation
            else
              postAggregation.name = applyName
              @addPostAggregation(postAggregation)
              return

          else
            throw new Error("unsupported aggregate '#{apply.aggregate}'")

      else if apply.arithmetic
        druidFn = arithmeticToDruidFn[apply.arithmetic]
        if druidFn
          a = @addApplyHelper(apply.operands[0], true)
          b = @addApplyHelper(apply.operands[1], true)
          postAggregation = {
            type: "arithmetic"
            fn: druidFn
            fields: [a, b]
          }

          if returnPostAggregation
            return postAggregation
          else
            postAggregation.name = applyName
            @addPostAggregation(postAggregation)
            return

        else
          throw new Error("unsupported arithmetic '#{apply.arithmetic}'")

      else
        throw new Error("must have an aggregate or an arithmetic")

  addApply: (apply) ->
    @addApplyHelper(apply, false)
    return this

  addDummyApply: ->
    @addApplyHelper({ aggregate: 'count' }, false)
    return this

  addCombine: (combine) ->
    switch combine.combine
      when 'slice'
        { sort, limit } = combine

        if @queryType is 'groupBy'
          if sort and limit?
            throw new Error("can not sort and limit on without approximate") unless @approximate
            @queryType = 'topN'
            @threshold = limit
            if sort.prop is @dimension.outputName
              throw new Error("lexicographic dimension must be 'ascending'") unless sort.direction is 'ascending'
              @metric = { type: "lexicographic" }
            else
              if sort.direction is 'descending'
                @metric = sort.prop
              else
                @metric = { type: "inverted", metric: sort.prop }

          else if sort
            # groupBy can only sort lexicographic
            throw new Error("can not do an unlimited sort on an apply") unless sort.prop is @dimension.outputName

          else if limit?
            throw new Error("handle this better")


      when 'matrix'
        sort = combine.sort
        if sort
          if sort.direction is 'descending'
            @metric = sort.prop
          else
            throw new Error("not supported yet")

        limits = combine.limits
        if limits
          for dim, i in @dimensions
            dim.threshold = limits[i] if limits[i]?

      else
        throw new Error("unsupported combine '#{combine.combine}'")

    return this

  getQuery: ->
    intervals = @intervals
    if not intervals
      throw new Error("must have an interval") if @forceInterval
      intervals = DruidQueryBuilder.allTimeInterval

    query = {
      queryType: @queryType
      dataSource: @dataSource
      granularity: @granularity
      intervals
    }

    if not @useCache
      query.context = {
        useCache: false
        populateCache: false
      }

    query.filter = @filter if @filter

    if @dimension
      if @queryType is 'groupBy'
        query.dimensions = [@dimension]
      else
        query.dimension = @dimension
    else if @dimensions
      query.dimensions = @dimensions

    query.aggregations = @aggregations if @aggregations.length
    query.postAggregations = @postAggregations if @postAggregations.length
    query.metric = @metric if @metric
    query.threshold = @threshold if @threshold
    return query


compareFns = {
  ascending: (a, b) ->
    return if a < b then -1 else if a > b then 1 else if a >= b then 0 else NaN

  descending: (a, b) ->
    return if b < a then -1 else if b > a then 1 else if b >= a then 0 else NaN
}

druidQueryFns = {
  all: ({requester, dataSource, timeAttribute, filter, forceInterval, condensedCommand, approximate}, callback) ->
    if condensedCommand.applies.length is 0
      callback(null, [{}])
      return

    druidQuery = new DruidQueryBuilder(dataSource, timeAttribute, forceInterval, approximate)

    try
      # filter
      druidQuery.addFilter(filter)

      # apply
      if condensedCommand.applies.length
        for apply in condensedCommand.applies
          druidQuery.addApply(apply)
      else
        druidQuery.addDummyApply()

      queryObj = druidQuery.getQuery()
    catch e
      callback(e)
      return

    requester queryObj, (err, ds) ->
      if err
        callback({
          message: err
          query: queryObj
        })
        return

      if ds.length > 1
        callback({
          message: "unexpected result form Druid (all)"
          query: queryObj
          result: ds
        })
        return

      callback(null, ds.map((d) -> d.result))
      return
    return

  timeseries: ({requester, dataSource, timeAttribute, filter, forceInterval, condensedCommand, approximate}, callback) ->
    druidQuery = new DruidQueryBuilder(dataSource, timeAttribute, forceInterval, approximate)

    try
      # filter
      druidQuery.addFilter(filter)

      # split
      druidQuery.addSplit(condensedCommand.split)

      # apply
      if condensedCommand.applies.length
        for apply in condensedCommand.applies
          druidQuery.addApply(apply)
      else
        druidQuery.addDummyApply()

      queryObj = druidQuery.getQuery()
    catch e
      callback({
        detail: e.message
      })
      return

    requester queryObj, (err, ds) ->
      if err
        callback(err)
        return

      # ToDo: implement actual timezones
      periodMap = {
        'PT1S': 1000
        'PT1M': 60 * 1000
        'PT1H': 60 * 60 * 1000
        'P1D' : 24 * 60 * 60 * 1000
      }

      timePropName = condensedCommand.split.name

      if condensedCommand.combine
        if condensedCommand.combine.sort
          if condensedCommand.combine.sort.prop is timePropName
            if condensedCommand.combine.sort.direction is 'descending'
              ds.reverse()
          else
            comapreFn = compareFns[condensedCommand.combine.sort.direction]
            sortProp = condensedCommand.combine.sort.prop
            ds.sort((a, b) -> comapreFn(a.result[sortProp], b.result[sortProp]))

        if condensedCommand.combine.limit?
          limit = condensedCommand.combine.limit
          driverUtil.inPlaceTrim(ds, limit)

      period = periodMap[condensedCommand.split.period]
      props = ds.map (d) ->
        rangeStart = new Date(d.timestamp)
        range = [rangeStart, new Date(rangeStart.valueOf() + period)]
        prop = d.result
        prop[timePropName] = range
        return prop

      # Total Hack!
      # Trim down the 0s form the end in an ascending timeseries
      # Remove this when druid pushes the new code live.
      interestingApplies = condensedCommand.applies.filter ({aggregate}) -> aggregate not in ['min', 'max']
      if condensedCommand.combine.sort.direction is 'ascending' and interestingApplies.length
        while props.length
          lastProp = props[props.length-1]
          allZero = true
          for apply in interestingApplies
            allZero = allZero and lastProp[apply.name] is 0
          if allZero
            props.pop()
          else
            break
      #/ Hack

      callback(null, props)
      return
    return

  topN: ({requester, dataSource, timeAttribute, filter, forceInterval, condensedCommand, approximate}, callback) ->
    druidQuery = new DruidQueryBuilder(dataSource, timeAttribute, forceInterval, approximate)

    try
      # filter
      druidQuery.addFilter(filter)

      # split
      druidQuery.addSplit(condensedCommand.split)

      # apply
      if condensedCommand.applies.length
        for apply in condensedCommand.applies
          druidQuery.addApply(apply)
      else
        druidQuery.addDummyApply()

      if condensedCommand.combine
        druidQuery.addCombine(condensedCommand.combine)

      queryObj = druidQuery.getQuery()
    catch e
      callback(e)
      return

    requester queryObj, (err, ds) ->
      if err
        callback({
          message: err
          query: queryObj
        })
        return

      if ds.length > 1 or (ds.length is 1 and not ds[0].result)
        callback({
          message: "unexpected result form Druid (topN)"
          query: queryObj
          result: ds
        })
        return

      callback(null, ds[0].result)
      return
    return

  allData: ({requester, dataSource, timeAttribute, filter, forceInterval, condensedCommand, approximate}, callback) ->
    druidQuery = new DruidQueryBuilder(dataSource, timeAttribute, forceInterval, approximate)
    allDataChunks = DruidQueryBuilder.ALL_DATA_CHUNKS

    try
      # filter
      druidQuery.addFilter(filter)

      # split
      druidQuery.addSplit(condensedCommand.split)

      # apply
      if condensedCommand.applies.length
        for apply in condensedCommand.applies
          druidQuery.addApply(apply)
      else
        druidQuery.addDummyApply()

      druidQuery.addCombine({
        combine: 'slice'
        sort: {
          compare: 'natural'
          prop: condensedCommand.split.name
          direction: condensedCommand.combine.sort.direction
        }
        limit: allDataChunks
      })

      queryObj = druidQuery.getQuery()
    catch e
      callback(e)
      return

    props = []
    done = false
    queryObj.metric.previousStop = null
    async.whilst(
      -> not done
      (callback) ->
        requester queryObj, (err, ds) ->
          if err
            callback(err)
            return

          if ds.length > 1 or (ds.length is 1 and not ds[0].result)
            callback({
              message: "unexpected result form Druid (topN/allData)"
              query: queryObj
              result: ds
            })
            return

          myProps = ds[0].result
          props = props.concat(myProps)
          if myProps.length < allDataChunks
            done = true
          else
            queryObj.metric.previousStop = myProps[allDataChunks - 1][condensedCommand.split.name]
          callback()
        return
      (err) ->
        if err
          callback(err)
          return

        callback(null, props)
        return
    )
    return

  groupBy: ({requester, dataSource, timeAttribute, filter, forceInterval, condensedCommand, approximate}, callback) ->
    druidQuery = new DruidQueryBuilder(dataSource, timeAttribute, forceInterval, approximate)

    try
      # filter
      druidQuery.addFilter(filter)

      # split
      druidQuery.addSplit(condensedCommand.split)

      # apply
      if condensedCommand.applies.length
        for apply in condensedCommand.applies
          druidQuery.addApply(apply)
      else
        druidQuery.addDummyApply()

      if condensedCommand.combine
        druidQuery.addCombine(condensedCommand.combine)

      queryObj = druidQuery.getQuery()
    catch e
      callback(e)
      return

    # console.log '------------------------------'
    # console.log queryObj

    requester queryObj, (err, ds) ->
      if err
        callback({
          message: err
          query: queryObj
        })
        return

      # console.log '------------------------------'
      # console.log err, ds

      callback(null, ds.map((d) -> d.event))
      return
    return

  histogram: ({requester, dataSource, timeAttribute, filter, forceInterval, condensedCommand, approximate}, callback) ->
    druidQuery = new DruidQueryBuilder(dataSource, timeAttribute, forceInterval, approximate)

    try
      # filter
      druidQuery.addFilter(filter)

      # split
      druidQuery.addSplit(condensedCommand.split)

      # applies are constrained to count
      # combine has to be computed in post processing

      queryObj = druidQuery.getQuery()
    catch e
      callback(e)
      return

    requester queryObj, (err, ds) ->
      if err
        callback({
          message: err
          query: queryObj
        })
        return

      if ds.length > 1 or (ds.length is 1 and not ds[0].result)
        callback({
          message: "unexpected result form Druid (histogram)"
          query: queryObj
          result: ds
        })
        return

      filterAttribute = condensedCommand.split.attribute
      histName = condensedCommand.split.name
      countName = condensedCommand.applies[0].name
      { breaks, counts } = ds[0].result.histogram

      props = []
      for count, i in counts
        continue if count is 0
        range = [breaks[i], breaks[i+1]]
        prop = {}
        prop[histName] = range
        prop[countName] = count
        props.push(prop)

      if condensedCommand.combine
        if condensedCommand.combine.sort
          if condensedCommand.combine.sort.prop is histName
            if condensedCommand.combine.sort.direction is 'descending'
              props.reverse()
          else
            comapreFn = compareFns[condensedCommand.combine.sort.direction]
            sortProp = condensedCommand.combine.sort.prop
            props.sort((a, b) -> comapreFn(a[sortProp], b[sortProp]))

        if condensedCommand.combine.limit?
          limit = condensedCommand.combine.limit
          driverUtil.inPlaceTrim(props, limit)

      callback(null, props)
      return
    return

  heatmap: ({requester, dataSource, timeAttribute, filter, forceInterval, condensedCommand, approximate}, callback) ->
    druidQuery = new DruidQueryBuilder(dataSource, timeAttribute, forceInterval, approximate)

    try
      # filter
      druidQuery.addFilter(filter)

      # split
      druidQuery.addSplit(condensedCommand.split)

      # apply
      if condensedCommand.applies.length
        for apply in condensedCommand.applies
          druidQuery.addApply(apply)
      else
        druidQuery.addDummyApply()

      if condensedCommand.combine
        druidQuery.addCombine(condensedCommand.combine)

      queryObj = druidQuery.getQuery()
    catch e
      callback(e)
      return

    requester queryObj, (err, ds) ->
      if err
        callback({
          message: err
          query: queryObj
        })
        return

      if ds.length isnt 1
        callback({
          message: "unexpected result form Druid (heatmap)"
          query: queryObj
          result: ds
        })
        return

      dimensionRenameNeeded = false
      dimensionRenameMap = {}
      for split in condensedCommand.split.splits
        continue if split.name is split.attribute
        dimensionRenameMap[split.attribute] = split.name
        dimensionRenameNeeded = true

      props = ds[0].result

      if dimensionRenameNeeded
        for prop in props
          for k, v in props
            renameTo = dimensionRenameMap[k]
            if renameTo
              props[renameTo] = v
              delete props[k]

      callback(null, props)
      return
    return
}


# This is the Druid driver. It translates facet queries to Druid
#
# @author Vadim
#
# @param {Requester} requester, a function to make requests to Druid
# @param {string} dataSource, name of the datasource in Druid
# @param {string} timeAttribute [optional, default="time"], name by which the time attribute will be referred to
# @param {boolean} approximate [optional, default=false], allow use of approximate queries
# @param {Filter} filter [optional, default=null], the filter that should be applied to the data
# @param {boolean} forceInterval [optional, default=false], if true will not execute queries without a time constraint
# @param {number} concurrentQueryLimit [optional, default=16], max number of queries to execute concurrently
# @param {number} queryLimit [optional, default=Infinity], max query complexity
#
# @return {FacetDriver} the driver that does the requests

module.exports = ({requester, dataSource, timeAttribute, approximate, filter, forceInterval, concurrentQueryLimit, queryLimit}) ->
  timeAttribute or= 'time'
  approximate ?= true
  concurrentQueryLimit or= 16
  queryLimit or= Infinity

  queriesMade = 0
  return (query, callback) ->
    try
      condensedQuery = driverUtil.condenseQuery(query)
    catch e
      callback(e)
      return

    rootSegment = null
    segments = [rootSegment]

    queryDruid = (condensedCommand, lastCmd, callback) ->
      if condensedCommand.split
        switch condensedCommand.split.bucket
          when 'identity'
            if approximate
              if condensedCommand.combine.limit?
                queryFn = druidQueryFns.topN
              else
                queryFn = druidQueryFns.allData
            else
              queryFn = druidQueryFns.groupBy
          when 'timeDuration', 'timePeriod'
            queryFn = druidQueryFns.timeseries
          when 'continuous'
            queryFn = druidQueryFns.histogram
          when 'tuple'
            if approximate and condensedCommand.split.splits.length is 2
              queryFn = druidQueryFns.heatmap
            else
              queryFn = druidQueryFns.groupBy
          else
            callback('unsupported query'); return
      else
        queryFn = druidQueryFns.all

      queryForSegment = (parentSegment, callback) ->
        queriesMade++
        if queryLimit < queriesMade
          callback('query limit exceeded')
          return

        myFilter = andFilters((if parentSegment then parentSegment._filter else filter), condensedCommand.filter)
        queryFn({
          requester
          dataSource
          timeAttribute
          filter: myFilter
          forceInterval
          condensedCommand
          approximate
        }, (err, props) ->
          if err
            callback(err)
            return

          # Make the results into segments and build the tree
          if condensedCommand.split
            splitAttribute = condensedCommand.split.attribute
            splitName = condensedCommand.split.name
            propToSplit = if lastCmd
              (prop) ->
                driverUtil.cleanProp(prop)
                return { prop }
            else
              (prop) ->
                driverUtil.cleanProp(prop)
                return { prop, _filter: andFilters(myFilter, makeFilter(splitAttribute, prop[splitName])) }
            parentSegment.splits = splits = props.map(propToSplit)
            driverUtil.cleanSegment(parentSegment)
          else
            prop = props[0]
            driverUtil.cleanProp(prop)
            rootSegment = if lastCmd then { prop: prop } else { prop: prop, _filter: myFilter }
            splits = [rootSegment]

          callback(null, splits)
          return
        )
        return

      # do the query in parallel
      async.mapLimit(
        segments
        concurrentQueryLimit
        queryForSegment
        (err, results) ->
          if err
            callback(err)
            return
          segments = driverUtil.flatten(results)
          callback()
          return
      )
      return

    cmdIndex = 0
    async.whilst(
      -> cmdIndex < condensedQuery.length
      (callback) ->
        condensedCommand = condensedQuery[cmdIndex]
        cmdIndex++
        last = cmdIndex is condensedQuery.length
        queryDruid(condensedCommand, last, callback)
        return
      (err) ->
        if err
          callback(err)
          return

        callback(null, rootSegment)
        return
    )
    return

module.exports.DruidQueryBuilder = DruidQueryBuilder

# -----------------------------------------------------
# Handle commonJS crap
`return module.exports; }).call(this,
  (typeof module === 'undefined' ? {exports: {}} : module),
  (typeof require === 'undefined' ? function (modulePath) {
    var moduleParts = modulePath.split('/');
    return window[moduleParts[moduleParts.length - 1]];
  } : require)
)`
