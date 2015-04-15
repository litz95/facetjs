{ expect } = require("chai")

{ WallTime } = require('chronology')
if not WallTime.rules
  tzData = require("chronology/lib/walltime/walltime-data.js")
  WallTime.init(tzData.rules, tzData.zones)

facet = require('../../build/facet')
{ Expression, Dataset, TimeRange, $ } = facet

context = {
  rankings: Dataset.fromJS({
    source: 'druid',
    dataSource: 'rankings',
    timeAttribute: 'time',
    forceInterval: false,
    approximate: true,
    context: null
    attributes: {
      pageURL: { type: 'STRING' } # VARCHAR(300)
      pageRank: { type: 'NUMBER' } # INT
      avgDuration: { type: 'NUMBER' } # INT
    }
  })
  uservisits: Dataset.fromJS({
    source: 'druid',
    dataSource: 'uservisits',
    timeAttribute: 'visitDate',
    forceInterval: false,
    approximate: true,
    context: null
    attributes: {
      sourceIP: { type: 'STRING' } # VARCHAR(116)
      destURL: { type: 'STRING' } # VARCHAR(100)
      visitDate: { type: 'TIME' } # DATE
      adRevenue: { type: 'NUMBER' } # FLOAT
      userAgent: { type: 'STRING' } # VARCHAR(256)
      countryCode: { type: 'STRING' } # CHAR(3)
      languageCode: { type: 'STRING' } # CHAR(6)
      searchWord: { type: 'STRING' } # VARCHAR(32)
      duration: { type: 'NUMBER' } # INT
    }
  })
}

# https://amplab.cs.berkeley.edu/benchmark/
describe "simulate Druid for amplab benchmark", ->
  it.skip "works for Query1", ->
    #      SELECT pageURL, pageRank FROM rankings WHERE pageRank > X
    sql = 'SELECT pageURL, pageRank FROM rankings WHERE pageRank > 5'

  it "works for Query1 (modified)", ->
    #      SELECT pageURL, sum(pageRank) AS pageRank FROM rankings GROUP BY pageURL HAVING pageRank > X
    sql = 'SELECT pageURL, sum(pageRank) AS pageRank FROM rankings GROUP BY pageURL HAVING pageRank > 5'
    ex = Expression.parseSQL(sql)

#    expect(ex.toJS()).to.deep.equal(
#      $('rankings')
#        .split('$pageURL', 'pageURL')
#        .apply('pageRank', '$rankings.sum($pageRank)')
#        .filter('$pageRank > 5')
#        .toJS()
#    )

    ex = $('rankings').split('$pageURL', 'pageURL')
      .apply('pageRank', '$rankings.sum($pageRank)')
      .filter('$pageRank > 5')

    expect(ex.simulateQueryPlan(context)).to.deep.equal([
      {
        "aggregations": [
          {
            "fieldName": "pageRank"
            "name": "pageRank"
            "type": "doubleSum"
          }
        ]
        "dataSource": "rankings"
        "dimensions": [
          "pageURL"
        ]
        "granularity": "all"
        "having": {
          "aggregation": "pageRank"
          "type": "greaterThan"
          "value": 5
        }
        "intervals": [
          "1000-01-01/3000-01-01"
        ]
        "limitSpec": {
          "columns": [
            "pageURL"
          ]
          "limit": 500000
          "type": "default"
        }
        "queryType": "groupBy"
      }
    ])

  it "works for Query2", ->
    #      SELECT SUBSTR(sourceIP, 1, X), SUM(adRevenue) FROM uservisits GROUP BY SUBSTR(sourceIP, 1, X)
    sql = 'SELECT SUBSTR(sourceIP, 1, 5), SUM(adRevenue) FROM uservisits GROUP BY SUBSTR(sourceIP, 1, 5)'
    ex = Expression.parseSQL(sql)

#    expect(ex.toJS()).to.deep.equal(
#      $('uservisits').split('$sourceIP.substr(1, 5)', 'prefix')
#        .apply('pageRank', '$uservisits.sum($adRevenue)')
#        .toJS()
#    )

    ex = $('uservisits').split('$sourceIP.substr(1, 5)', 'prefix')
      .apply('pageRank', '$uservisits.sum($adRevenue)')

    expect(ex.simulateQueryPlan(context)).to.deep.equal([
      {
        "aggregations": [
          {
            "fieldName": "adRevenue"
            "name": "pageRank"
            "type": "doubleSum"
          }
        ]
        "dataSource": "uservisits"
        "dimensions": [
          {
            "dimension": "sourceIP"
            "extractionFn": {
              "function": "function(s){return s.substr(1,5);}"
              "type": "javascript"
            }
            "outputName": "prefix"
            "type": "extraction"
          }
        ]
        "granularity": "all"
        "intervals": [
          "1000-01-01/3000-01-01"
        ]
        "limitSpec": {
          "columns": [
            "prefix"
          ]
          "limit": 500000
          "type": "default"
        }
        "queryType": "groupBy"
      }
    ])