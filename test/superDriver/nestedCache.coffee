chai = require("chai")
expect = chai.expect
utils = require('../utils')

simpleDriver = require('../../src/driver/simpleDriver')
nestedCache = require('../../src/superDriver/nestedCache')

{FacetQuery} = require('../../src/query')

wikipediaData = require('../../data/wikipedia.js')

allowQuery = true
checkEquality = false
expectedQuery = null

driverFns = {}
driverFns.wikipediaSimple = wikipediaSimple = simpleDriver(wikipediaData)

nestedCacheCallback = null
nestedCacheInstance = nestedCache({
  transport: (request, callback) ->
    if checkEquality
      expect(request.query.valueOf()).to.deep.equal(expectedQuery)

    if not allowQuery
      #console.log 'request.query.valueOf()', JSON.stringify(request.query.valueOf(), null, 2)
      throw new Error("query not allowed")

    wikipediaSimple(request, callback)
    return
  onData: (data, state) ->
    return unless state is 'final'
    nestedCacheCallback(null, data)
    nestedCacheCallback = null
    return
})

driverFns.wikipediaCached = (query, callback) ->
  nestedCacheCallback = callback
  nestedCacheInstance(query)
  return


testEquality = utils.makeEqualityTest(driverFns)

describe "Nested cache", ->

  describe "errors", ->
    it "complains when there is no query", ->
      expect(->
        nestedCacheInstance({})
      ).to.throw()

  describe "basically works", ->
    it "apply Revenue", testEquality {
      drivers: ['wikipediaCached', 'wikipediaSimple']
      query: [
        { operation: 'apply', name: 'Count', aggregate: 'sum', attribute: 'count' }
      ]
    }

    it "split Color; apply Revenue; combine descending", testEquality {
      drivers: ['wikipediaCached', 'wikipediaSimple']
      query: [
        { operation: 'filter', type: 'within', attribute: 'time', range: [new Date("2013-02-26T00:00:00Z"), new Date("2013-02-27T00:00:00Z")] }
        { operation: 'split', name: 'Time', bucket: 'timePeriod', attribute: 'time', period: 'PT1H', timezone: 'Etc/UTC' }
        { operation: 'apply', name: 'Count', aggregate: 'sum', attribute: 'count' }
        { operation: 'combine', combine: 'slice', sort: { compare: 'natural', prop: 'Time', direction: 'ascending' } }
      ]
    }

  describe 'caches removing an expansions and split', ->
    setUpQuery = [
      { operation: "apply", name: "Count", aggregate: "sum", attribute: "count" }
      { operation: "split", name: "Language", bucket: "identity", attribute: "language" }
      { operation: "apply", name: "Count", aggregate: "sum", attribute: "count" }
      { operation: "combine", method: "slice", sort: { compare: "natural", prop: "Count", direction: "descending" }, limit: 10 }
      {
        operation: "split", name: "Page", bucket: "identity", attribute: "page",
        segmentFilter: {
          type: "or"
          filters: [
            { type: "is", prop: "Language", value: "fr" }
            { type: "is", prop: "Language", value: "de" }
          ]
        }
      }
      { operation: "apply", name: "Count", aggregate: "sum", attribute: "count" }
      { operation: "combine", method: "slice", sort: { compare: "natural", prop: "Count", direction: "descending" }, limit: 10 }
    ]

    before (done) ->
      allowQuery = true
      driverFns.wikipediaCached({query: new FacetQuery(setUpQuery)}, (err, result) ->
        throw err if err?
        allowQuery = false
        done()
        return
      )

    after -> allowQuery = true

    it "repeats query", testEquality {
      drivers: ['wikipediaCached', 'wikipediaSimple']
      query: setUpQuery
    }

    it "collapses one level", testEquality {
      drivers: ['wikipediaCached', 'wikipediaSimple']
      query: [
        { operation: "apply", name: "Count", aggregate: "sum", attribute: "count" }
        { operation: "split", name: "Language", bucket: "identity", attribute: "language" }
        { operation: "apply", name: "Count", aggregate: "sum", attribute: "count" }
        { operation: "combine", method: "slice", sort: { compare: "natural", prop: "Count", direction: "descending" }, limit: 10 }
        {
          operation: "split", name: "Page", bucket: "identity", attribute: "page",
          segmentFilter: {
            type: "or"
            filters: [
              { type: "is", prop: "Language", value: "fr" }
            ]
          }
        }
        { operation: "apply", name: "Count", aggregate: "sum", attribute: "count" }
        { operation: "combine", method: "slice", sort: { compare: "natural", prop: "Count", direction: "descending" }, limit: 10 }
      ]
    }

    it "collapses another level (to empty)", testEquality {
      drivers: ['wikipediaCached', 'wikipediaSimple']
      query: [
        { operation: "apply", name: "Count", aggregate: "sum", attribute: "count" }
        { operation: "split", name: "Language", bucket: "identity", attribute: "language" }
        { operation: "apply", name: "Count", aggregate: "sum", attribute: "count" }
        { operation: "combine", method: "slice", sort: { compare: "natural", prop: "Count", direction: "descending" }, limit: 10 }
        {
          operation: "split", name: "Page", bucket: "identity", attribute: "page",
          segmentFilter: {
            type: "false"
          }
        }
        { operation: "apply", name: "Count", aggregate: "sum", attribute: "count" }
        { operation: "combine", method: "slice", sort: { compare: "natural", prop: "Count", direction: "descending" }, limit: 10 }
      ]
    }

    it "removes the empty split", testEquality {
      drivers: ['wikipediaCached', 'wikipediaSimple']
      query: [
        { operation: "apply", name: "Count", aggregate: "sum", attribute: "count" }
        { operation: "split", name: "Language", bucket: "identity", attribute: "language" }
        { operation: "apply", name: "Count", aggregate: "sum", attribute: "count" }
        { operation: "combine", method: "slice", sort: { compare: "natural", prop: "Count", direction: "descending" }, limit: 10 }
      ]
    }


  describe 'caches adding a split and expansions (identity)', ->
    setUpQuery = [
      { operation: "apply", name: "Count", aggregate: "sum", attribute: "count" }
      { operation: "split", name: "Language", bucket: "identity", attribute: "language" }
      { operation: "apply", name: "Count", aggregate: "sum", attribute: "count" }
      { operation: "combine", method: "slice", sort: { compare: "natural", prop: "Count", direction: "descending" }, limit: 10 }
    ]

    before (done) ->
      allowQuery = true
      driverFns.wikipediaCached({query: new FacetQuery(setUpQuery)}, (err, result) ->
        throw err if err?
        allowQuery = false
        done()
        return
      )

    after -> allowQuery = true

    it "adds an empty split (without querying)", testEquality {
      drivers: ['wikipediaCached', 'wikipediaSimple']
      query: [
        { operation: "apply", name: "Count", aggregate: "sum", attribute: "count" }
        { operation: "split", name: "Language", bucket: "identity", attribute: "language" }
        { operation: "apply", name: "Count", aggregate: "sum", attribute: "count" }
        { operation: "combine", method: "slice", sort: { compare: "natural", prop: "Count", direction: "descending" }, limit: 10 }
        {
          operation: "split", name: "Page", bucket: "identity", attribute: "page",
          segmentFilter: {
            type: "false"
          }
        }
        { operation: "apply", name: "Count", aggregate: "sum", attribute: "count" }
        { operation: "combine", method: "slice", sort: { compare: "natural", prop: "Count", direction: "descending" }, limit: 10 }
      ]
    }

    it "adds an expansion", (done) ->
      allowQuery = true
      checkEquality = true
      expectedQuery = [
        { operation: "filter", type: "is", attribute: "language", value: "en" }
        { operation: "split", name: "Page", bucket: "identity", attribute: "page" }
        { operation: "apply", name: "Count", aggregate: "sum", attribute: "count" }
        { operation: "combine", method: "slice", sort: { compare: "natural", prop: "Count", direction: "descending" }, limit: 10 }
      ]
      testEquality({
        drivers: ['wikipediaCached', 'wikipediaSimple']
        query: [
          { operation: "apply", name: "Count", aggregate: "sum", attribute: "count" }
          { operation: "split", name: "Language", bucket: "identity", attribute: "language" }
          { operation: "apply", name: "Count", aggregate: "sum", attribute: "count" }
          { operation: "combine", method: "slice", sort: { compare: "natural", prop: "Count", direction: "descending" }, limit: 10 }
          {
            operation: "split", name: "Page", bucket: "identity", attribute: "page",
            segmentFilter: {
              type: "or"
              filters: [
                { type: "is", prop: "Language", value: "en" }
              ]
            }
          }
          { operation: "apply", name: "Count", aggregate: "sum", attribute: "count" }
          { operation: "combine", method: "slice", sort: { compare: "natural", prop: "Count", direction: "descending" }, limit: 10 }
        ]
      })(done)

    it "adds another expansion", (done) ->
      allowQuery = true
      checkEquality = true
      expectedQuery = [
        { operation: "filter", type: "is", attribute: "language", value: "fr" }
        { operation: "split", name: "Page", bucket: "identity", attribute: "page" }
        { operation: "apply", name: "Count", aggregate: "sum", attribute: "count" }
        { operation: "combine", method: "slice", sort: { compare: "natural", prop: "Count", direction: "descending" }, limit: 10 }
      ]
      testEquality({
        drivers: ['wikipediaCached', 'wikipediaSimple']
        query: [
          { operation: "apply", name: "Count", aggregate: "sum", attribute: "count" }
          { operation: "split", name: "Language", bucket: "identity", attribute: "language" }
          { operation: "apply", name: "Count", aggregate: "sum", attribute: "count" }
          { operation: "combine", method: "slice", sort: { compare: "natural", prop: "Count", direction: "descending" }, limit: 10 }
          {
            operation: "split", name: "Page", bucket: "identity", attribute: "page",
            segmentFilter: {
              type: "or"
              filters: [
                { type: "is", prop: "Language", value: "en" }
                { type: "is", prop: "Language", value: "fr" }
              ]
            }
          }
          { operation: "apply", name: "Count", aggregate: "sum", attribute: "count" }
          { operation: "combine", method: "slice", sort: { compare: "natural", prop: "Count", direction: "descending" }, limit: 10 }
        ]
      })(done)

    it "adds an expansion that does not exist", (done) ->
      allowQuery = true
      checkEquality = true
      expectedQuery = [
        { operation: "filter", type: "is", attribute: "language", value: "poo" }
        { operation: "split", name: "Page", bucket: "identity", attribute: "page" }
        { operation: "apply", name: "Count", aggregate: "sum", attribute: "count" }
        { operation: "combine", method: "slice", sort: { compare: "natural", prop: "Count", direction: "descending" }, limit: 10 }
      ]
      testEquality({
        drivers: ['wikipediaCached', 'wikipediaSimple']
        query: [
          { operation: "apply", name: "Count", aggregate: "sum", attribute: "count" }
          { operation: "split", name: "Language", bucket: "identity", attribute: "language" }
          { operation: "apply", name: "Count", aggregate: "sum", attribute: "count" }
          { operation: "combine", method: "slice", sort: { compare: "natural", prop: "Count", direction: "descending" }, limit: 10 }
          {
            operation: "split", name: "Page", bucket: "identity", attribute: "page",
            segmentFilter: {
              type: "or"
              filters: [
                { type: "is", prop: "Language", value: "en" }
                { type: "is", prop: "Language", value: "fr" }
                { type: "is", prop: "Language", value: "poo" }
              ]
            }
          }
          { operation: "apply", name: "Count", aggregate: "sum", attribute: "count" }
          { operation: "combine", method: "slice", sort: { compare: "natural", prop: "Count", direction: "descending" }, limit: 10 }
        ]
      })(done)

    it "filters", (done) ->
      allowQuery = false
      checkEquality = false
      expectedQuery = null
      testEquality({
        drivers: ['wikipediaCached', 'wikipediaSimple']
        query: [
          { operation: "filter", type: "is", attribute: "language", value: "en" }
          { operation: "apply", name: "Count", aggregate: "sum", attribute: "count" }
          { operation: "split", name: "Page", bucket: "identity", attribute: "page" }
          { operation: "apply", name: "Count", aggregate: "sum", attribute: "count" }
          { operation: "combine", method: "slice", sort: { compare: "natural", prop: "Count", direction: "descending" }, limit: 10 }
        ]
      })(done)


  describe.only 'caches adding a split and expansions (time)', ->
    setUpQuery = [
      { operation: "apply", name: "Count", aggregate: "sum", attribute: "count" }
      { operation: "split", name: "Time", bucket: "timePeriod", attribute: "time", period: 'PT1H' }
      { operation: "apply", name: "Count", aggregate: "sum", attribute: "count" }
      { operation: "combine", method: "slice", sort: { compare: "natural", prop: "Count", direction: "descending" }, limit: 10 }
    ]

    before (done) ->
      allowQuery = true
      driverFns.wikipediaCached({query: new FacetQuery(setUpQuery)}, (err, result) ->
        throw err if err?
        allowQuery = false
        done()
        return
      )

    after -> allowQuery = true

    it "adds an empty split (without querying)", testEquality {
      drivers: ['wikipediaCached', 'wikipediaSimple']
      query: [
        { operation: "apply", name: "Count", aggregate: "sum", attribute: "count" }
        { operation: "split", name: "Time", bucket: "timePeriod", attribute: "time", period: 'PT1H' }
        { operation: "apply", name: "Count", aggregate: "sum", attribute: "count" }
        { operation: "combine", method: "slice", sort: { compare: "natural", prop: "Count", direction: "descending" }, limit: 10 }
        {
          operation: "split", name: "Page", bucket: "identity", attribute: "page",
          segmentFilter: {
            type: "false"
          }
        }
        { operation: "apply", name: "Count", aggregate: "sum", attribute: "count" }
        { operation: "combine", method: "slice", sort: { compare: "natural", prop: "Count", direction: "descending" }, limit: 10 }
      ]
    }

    it "adds an expansion", (done) ->
      allowQuery = true
      checkEquality = true
      expectedQuery = [
        { operation: "filter", type: "within", attribute: "time", range: [new Date("2013-02-26T01:00:00.000Z"), new Date("2013-02-26T02:00:00.000Z")] }
        { operation: "split", name: "Page", bucket: "identity", attribute: "page" }
        { operation: "apply", name: "Count", aggregate: "sum", attribute: "count" }
        { operation: "combine", method: "slice", sort: { compare: "natural", prop: "Count", direction: "descending" }, limit: 10 }
      ]
      testEquality({
        drivers: ['wikipediaCached', 'wikipediaSimple']
        query: [
          { operation: "apply", name: "Count", aggregate: "sum", attribute: "count" }
          { operation: "split", name: "Time", bucket: "timePeriod", attribute: "time", period: 'PT1H' }
          { operation: "apply", name: "Count", aggregate: "sum", attribute: "count" }
          { operation: "combine", method: "slice", sort: { compare: "natural", prop: "Count", direction: "descending" }, limit: 10 }
          {
            operation: "split", name: "Page", bucket: "identity", attribute: "page",
            segmentFilter: {
              type: "or"
              filters: [
                { type: "is", prop: "Time", value: [new Date("2013-02-26T01:00:00.000Z"), new Date("2013-02-26T02:00:00.000Z")] }
              ]
            }
          }
          { operation: "apply", name: "Count", aggregate: "sum", attribute: "count" }
          { operation: "combine", method: "slice", sort: { compare: "natural", prop: "Count", direction: "descending" }, limit: 10 }
        ]
      })((err, result) ->
        expect(result.splits[1])
          .to.have.property('splits')
          .that.is.an('array')
        done()
      )

    it "adds another expansion", (done) ->
      allowQuery = true
      checkEquality = true
      expectedQuery = [
        { operation: "filter", type: "within", attribute: "time", range: [new Date("2013-02-26T15:00:00.000Z"), new Date("2013-02-26T16:00:00.000Z")] }
        { operation: "split", name: "Page", bucket: "identity", attribute: "page" }
        { operation: "apply", name: "Count", aggregate: "sum", attribute: "count" }
        { operation: "combine", method: "slice", sort: { compare: "natural", prop: "Count", direction: "descending" }, limit: 10 }
      ]
      testEquality({
        drivers: ['wikipediaCached', 'wikipediaSimple']
        query: [
          { operation: "apply", name: "Count", aggregate: "sum", attribute: "count" }
          { operation: "split", name: "Time", bucket: "timePeriod", attribute: "time", period: 'PT1H' }
          { operation: "apply", name: "Count", aggregate: "sum", attribute: "count" }
          { operation: "combine", method: "slice", sort: { compare: "natural", prop: "Count", direction: "descending" }, limit: 10 }
          {
            operation: "split", name: "Page", bucket: "identity", attribute: "page",
            segmentFilter: {
              type: "or"
              filters: [
                { type: "is", prop: "Time", value: [new Date("2013-02-26T01:00:00.000Z"), new Date("2013-02-26T02:00:00.000Z")] }
                { type: "is", prop: "Time", value: [new Date("2013-02-26T15:00:00.000Z"), new Date("2013-02-26T16:00:00.000Z")] }
              ]
            }
          }
          { operation: "apply", name: "Count", aggregate: "sum", attribute: "count" }
          { operation: "combine", method: "slice", sort: { compare: "natural", prop: "Count", direction: "descending" }, limit: 10 }
        ]
      })((err, result) ->
        expect(result.splits[2])
          .to.have.property('splits')
          .that.is.an('array')
        done()
      )

    it "adds an expansion that does not exist", (done) ->
      allowQuery = true
      checkEquality = true
      expectedQuery = [
        { operation: "filter", type: "within", attribute: "time", range: [new Date("2010-02-26T15:00:00.000Z"), new Date("2010-02-26T16:00:00.000Z")] }
        { operation: "split", name: "Page", bucket: "identity", attribute: "page" }
        { operation: "apply", name: "Count", aggregate: "sum", attribute: "count" }
        { operation: "combine", method: "slice", sort: { compare: "natural", prop: "Count", direction: "descending" }, limit: 10 }
      ]
      testEquality({
        drivers: ['wikipediaCached', 'wikipediaSimple']
        query: [
          { operation: "apply", name: "Count", aggregate: "sum", attribute: "count" }
          { operation: "split", name: "Time", bucket: "timePeriod", attribute: "time", period: 'PT1H' }
          { operation: "apply", name: "Count", aggregate: "sum", attribute: "count" }
          { operation: "combine", method: "slice", sort: { compare: "natural", prop: "Count", direction: "descending" }, limit: 10 }
          {
            operation: "split", name: "Page", bucket: "identity", attribute: "page",
            segmentFilter: {
              type: "or"
              filters: [
                { type: "is", prop: "Time", value: [new Date("2013-02-26T01:00:00.000Z"), new Date("2013-02-26T02:00:00.000Z")] }
                { type: "is", prop: "Time", value: [new Date("2013-02-26T15:00:00.000Z"), new Date("2013-02-26T16:00:00.000Z")] }
                { type: "is", prop: "Time", value: [new Date("2010-02-26T15:00:00.000Z"), new Date("2010-02-26T16:00:00.000Z")] }
              ]
            }
          }
          { operation: "apply", name: "Count", aggregate: "sum", attribute: "count" }
          { operation: "combine", method: "slice", sort: { compare: "natural", prop: "Count", direction: "descending" }, limit: 10 }
        ]
      })(done)

    it "filters", (done) ->
      allowQuery = false
      checkEquality = false
      expectedQuery = null
      testEquality({
        drivers: ['wikipediaCached', 'wikipediaSimple']
        query: [
          { operation: "filter", type: "within", attribute: "time", range: [new Date("2013-02-26T01:00:00.000Z"), new Date("2013-02-26T02:00:00.000Z")] }
          { operation: "apply", name: "Count", aggregate: "sum", attribute: "count" }
          { operation: "split", name: "Page", bucket: "identity", attribute: "page" }
          { operation: "apply", name: "Count", aggregate: "sum", attribute: "count" }
          { operation: "combine", method: "slice", sort: { compare: "natural", prop: "Count", direction: "descending" }, limit: 10 }
        ]
      })(done)

