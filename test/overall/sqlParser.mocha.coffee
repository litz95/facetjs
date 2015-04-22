{ expect } = require("chai")

{ WallTime } = require('chronology')
if not WallTime.rules
  tzData = require("chronology/lib/walltime/walltime-data.js")
  WallTime.init(tzData.rules, tzData.zones)

facet = require('../../build/facet')
{ Expression, $ } = facet

describe "SQL parser", ->
  it "should fail on a expression with no columns", ->
    expect(->
      Expression.parseSQL("SELECT  FROM diamonds")
    ).to.throw('SQL parse error Can not have empty column list on `SELECT  FROM diamonds`')

  it "should parse a simple expression", ->
    ex = Expression.parseSQL("""
      SELECT
      COUNT() AS 'Count'
      FROM `wiki`
      """)

    ex2 = $()
      .def('data', '$wiki')
      .apply('Count', '$data.count()')

    expect(ex.toJS()).to.deep.equal(ex2.toJS())

  it "should parse a total expression", ->
    ex = Expression.parseSQL("""
      SELECT
      SUM(added) AS 'TotalAdded',
      '2014-01-02' AS 'Date',
      SUM(added) / 4 AS TotalAddedOver4,
      NOT(true) AS 'False'
      FROM `wiki`
      WHERE `language`="en"    -- This is just some comment
      GROUP BY ''
      """)

    ex2 = $()
      .def('data', '$wiki.filter($language = "en")')
      .apply('TotalAdded', '$data.sum($added)')
      .apply('Date', new Date('2014-01-02T00:00:00.000Z'))
      .apply('TotalAddedOver4', '$data.sum($added) / 4')
      .apply('False', $(true).not())

    expect(ex.toJS()).to.deep.equal(ex2.toJS())

  it "should parse a total expression without group by clause", ->
    ex = Expression.parseSQL("""
      SELECT
      SUM(added) AS TotalAdded
      FROM `wiki`
      WHERE `language`="en"    -- This is just some comment
      """)

    ex2 = $()
      .def('data', '$wiki.filter($language = "en")')
      .apply('TotalAdded', '$data.sum($added)')

    expect(ex.toJS()).to.deep.equal(ex2.toJS())

  it "should work without a FROM", ->
    ex = Expression.parseSQL("""
      SELECT
      SUM(added) AS 'TotalAdded'
      WHERE `language`="en"
      GROUP BY 1
      """)

    ex2 = $()
      .def('data', '$data.filter($language = "en")')
      .apply('TotalAdded', '$data.sum($added)')

    expect(ex.toJS()).to.deep.equal(ex2.toJS())

  it "should work without with a BETWEEN", ->
    ex = Expression.parseSQL("""
      SELECT
      SUM(added) AS 'TotalAdded'
      WHERE `language`="en" AND `time` BETWEEN '2015-01-01T10:30:00' AND '2015-01-02T12:30:00'
      GROUP BY 1
      """)

    ex2 = $()
      .def('data', $('data').filter(
        $('language').is("en").and($('time').in({
          start: new Date('2015-01-01T10:30:00'),
          end: new Date('2015-01-02T12:30:00'),
          bounds: '[]'
        }))
      ))
      .apply('TotalAdded', '$data.sum($added)')

    expect(ex.toJS()).to.deep.equal(ex2.toJS())

  it "should work without with <= <", ->
    ex = Expression.parseSQL("""
      SELECT
      SUM(added) AS 'TotalAdded'
      WHERE `language`="en" AND '2015-01-01T10:30:00' <= `time` AND `time` < '2015-01-02T12:30:00'
      GROUP BY 1
      """).simplify()

    ex2 = $()
      .def('data', $('data').filter(
        $('language').is("en").and($('time').in({
          start: new Date('2015-01-01T10:30:00'),
          end: new Date('2015-01-02T12:30:00')
        }))
      ))
      .apply('TotalAdded', '$data.sum($added)')

    expect(ex.toJS()).to.deep.equal(ex2.toJS())

  it "should work without top level GROUP BY", ->
    ex = Expression.parseSQL("""
      SELECT
      `page` AS 'Page',
      SUM(added) AS 'TotalAdded'
      FROM `wiki`
      WHERE `language`="en" AND `time` BETWEEN '2015-01-01T10:30:00' AND '2015-01-02T12:30:00'
      GROUP BY `page`
      """)

    ex2 = $('wiki').filter(
      $('language').is("en").and($('time').in({
        start: new Date('2015-01-01T10:30:00'),
        end: new Date('2015-01-02T12:30:00'),
        bounds: '[]'
      }))
    ).split('$page', 'Page', 'data')
      .apply('TotalAdded', '$data.sum($added)')

    expect(ex.toJS()).to.deep.equal(ex2.toJS())

  it "should work without top level GROUP BY with ORDER BY and LIMIT", ->
    ex = Expression.parseSQL("""
      SELECT
      `page` AS 'Page',
      SUM(added) AS 'TotalAdded'
      FROM `wiki`
      GROUP BY `page`
      ORDER BY TotalAdded
      LIMIT 5
      """)

    ex2 = $('wiki').split('$page', 'Page', 'data')
      .apply('TotalAdded', '$data.sum($added)')
      .sort('$TotalAdded', 'ascending')
      .limit(5)

    expect(ex.toJS()).to.deep.equal(ex2.toJS())

  it "should work without top level GROUP BY with LIMIT only", ->
    ex = Expression.parseSQL("""
      SELECT
      `page` AS 'Page',
      SUM(added) AS 'TotalAdded'
      FROM `wiki`
      GROUP BY `page`
      LIMIT 5
      """)

    ex2 = $('wiki').split('$page', 'Page', 'data')
      .apply('TotalAdded', '$data.sum($added)')
      .limit(5)

    expect(ex.toJS()).to.deep.equal(ex2.toJS())

  it "should work with a TIME_BUCKET function", ->
    ex = Expression.parseSQL("""
      SELECT
      TIME_BUCKET(`time`, 'PT1H', 'Etc/UTC') AS 'TimeByHour',
      SUM(added) AS 'TotalAdded'
      FROM `wiki`
      GROUP BY TIME_BUCKET(`time`, PT1H, 'Etc/UTC')
      """)

    ex2 = $('wiki').split($('time').timeBucket('PT1H', 'Etc/UTC'), 'TimeByHour', 'data')
      .apply('TotalAdded', '$data.sum($added)')

    expect(ex.toJS()).to.deep.equal(ex2.toJS())

  it "should work with a NUMBER_BUCKET function", ->
    ex = Expression.parseSQL("""
      SELECT
      NUMBER_BUCKET(added, 10, 1) AS 'AddedBucket',
      SUM(added) AS 'TotalAdded'
      FROM `wiki`
      GROUP BY NUMBER_BUCKET(added, 10, 1)
      """)

    ex2 = $('wiki').split($('added').numberBucket(10, 1), 'AddedBucket', 'data')
      .apply('TotalAdded', '$data.sum($added)')

    expect(ex.toJS()).to.deep.equal(ex2.toJS())

  it "should work with a TIME_PART function", ->
    ex = Expression.parseSQL("""
      SELECT
      TIME_PART(`time`, DAY_OF_WEEK, 'Etc/UTC') AS 'DayOfWeek',
      SUM(added) AS 'TotalAdded'
      FROM `wiki`
      GROUP BY TIME_PART(`time`, DAY_OF_WEEK, 'Etc/UTC')
      """)

    ex2 = $('wiki').split($('time').timePart('DAY_OF_WEEK', 'Etc/UTC'), 'DayOfWeek', 'data')
      .apply('TotalAdded', '$data.sum($added)')

    expect(ex.toJS()).to.deep.equal(ex2.toJS())

  it "should parse a complex filter", ->
    ex = Expression.parseSQL("""
      SELECT
      SUM(added) AS 'TotalAdded'
      FROM `wiki`    -- Filters can have ANDs and all sorts of stuff!
      WHERE language="en" AND page<>"Hello World" AND added < 5
      GROUP BY ''
      """)

    ex2 = $()
      .def('data',
        $('wiki').filter(
          $('language').is("en").and($('page').isnt("Hello World"), $('added').lessThan(5))
        )
      )
      .apply('TotalAdded', '$data.sum($added)')

    expect(ex.toJS()).to.deep.equal(ex2.toJS())

  it "should parse a total + split expression", ->
    ex = Expression.parseSQL("""
      SELECT
      SUM(`added`) AS 'TotalAdded',
      (
        SELECT
        `page` AS 'Page',
        COUNT() AS 'Count',
        SUM(`added`) AS 'TotalAdded',
        min(`added`) AS 'MinAdded',
        mAx(`added`) AS 'MaxAdded'
        GROUP BY `page`
        HAVING `TotalAdded` > 100
        ORDER BY `Count` DESC
        LIMIT 10
      ) AS 'Pages'
      FROM `wiki`
      WHERE `language`="en"
      GROUP BY ''
      """)

    ex2 = $()
      .def('data', '$wiki.filter($language = "en")')
      .apply('TotalAdded', '$data.sum($added)')
      .apply('Pages',
        $('data').split('$page', 'Page')
          .apply('Count', '$data.count()')
          .apply('TotalAdded', '$data.sum($added)')
          .apply('MinAdded', '$data.min($added)')
          .apply('MaxAdded', '$data.max($added)')
          .filter('$TotalAdded > 100')
          .sort('$Count', 'descending')
          .limit(10)
      )

    expect(ex.toJS()).to.deep.equal(ex2.toJS())
