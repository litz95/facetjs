{expect} = require("chai")
{parse} = require('../../build/parser/apply')

describe "parser", ->
  describe "good cases", ->
    it "can deal with nameless applies", ->
      formula = "sum(`hello`)"
      expect(parse(formula)).to.deep.equal({
        aggregate: 'sum'
        attribute: 'hello'
      })

    it "can deal with named applies", ->
      formula = "sum_hello <- sum(`hello`)"
      expect(parse(formula)).to.deep.equal({
        name: 'sum_hello'
        aggregate: 'sum'
        attribute: 'hello'
      })

    it "handles tickless attributes, with nameless applies", ->
      formula = "sum(hello)"
      expect(parse(formula)).to.deep.equal({
        aggregate: 'sum'
        attribute: 'hello'
      })

    it "handles tickless attributes, with named applies", ->
      formula = "sum_hello <- sum(hello)"
      expect(parse(formula)).to.deep.equal({
        name: 'sum_hello'
        aggregate: 'sum'
        attribute: 'hello'
      })

    it "handles other characters in attribute if ticks present", ->
      formula = "sum(`hello)`)"
      expect(parse(formula)).to.deep.equal({
        aggregate: 'sum'
        attribute: 'hello)'
      })

    it "handles constants", ->
      formula = "3"
      expect(parse(formula)).to.deep.equal({
        aggregate: 'constant'
        value: 3
      })

    it "handles arithmetic", ->
      formula = "sum(hello) / 3"
      expect(parse(formula)).to.deep.equal({
        arithmetic: "divide",
        operands: [{
          aggregate: 'sum'
          attribute: 'hello'
        },
        {
          aggregate: 'constant'
          value: 3
        }]
      })


  describe "bad cases", ->
    it "should throw special error for unmatched ticks", ->
      formula = "sum_hello <- sum(`hello)"
      expect(-> parse(formula)).to.throw(Error, "Unmatched tickmark")

    it "should error if non-alpha characters in attribute if ticks not present", ->
      formula = "sum(hello))"
      expect(-> parse(formula)).to.throw(Error, "Expected [*\\/], [+\\-] or end of input but \")\" found.")

    it "should not allow attributes (w/ ticks) without an aggregate", ->
      expect(-> parse("`blah`")).to.throw(Error, "Expected \"(\", Aggregate or Name but \"`\" found.")

    it "should not allow attributes (w/o ticks) without an aggregate", ->
      expect(-> parse("blah")).to.throw(Error, "Expected \"<-\" but end of input found.")
