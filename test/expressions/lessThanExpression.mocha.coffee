{ expect } = require("chai")

tests = require './sharedTests'

describe 'LessThanExpression', ->
  describe 'with false literal values', ->
    beforeEach ->
      this.expression = { op: 'lessThan', lhs: { op: 'literal', value: 5 }, rhs: { op: 'literal', value: 5 } }

    tests.complexityIs(3)
    tests.simplifiedExpressionIs({op:'literal', value: false})

  describe 'with true literal values', ->
    beforeEach ->
      this.expression = { op: 'lessThan', lhs: { op: 'literal', value: 5 }, rhs: { op: 'literal', value: 7 } }

    tests.complexityIs(3)
    tests.simplifiedExpressionIs({op:'literal', value: true})

  describe 'with left-handed reference', ->
    beforeEach ->
      this.expression = { op: 'lessThan', lhs: { op: 'ref', name: 'test' }, rhs: { op: 'literal', value: 5 } }

    tests.complexityIs(3)
    tests.simplifiedExpressionIs({ op: 'in', lhs: { op: 'ref', name: 'test' }, rhs: { op: 'literal', value: [Infinity, 5] } })
    # ToDo: allow for configuring exclusive, inclusive
    # Intervals should be able to be created fliped Int(0, 3) == Int(3, 0)
    # Intervals correspond to Math.abs (could be used to implement it with .length)
    # Do not need lessThanExpression class at all, use interval everywhere, have a renamer so that the fromJs can still work
    # Allow union and intersect of (0, 10) + [(0, 1), (4, 5]] + dayofWeek(time) === 3

    # add = binary or nary

    describe '#mergeAnd', ->
      tests
        .mergeAndWith(
          "merges with is expression of inside value",
          {
            op: 'is',
            lhs: "$test",
            rhs: 1
          })
        .equals({
            op: 'is',
            lhs: { op: 'ref', name: 'test' }
            rhs: { op: 'literal', value: 1 }
          })

      tests
        .mergeAndWith(
          "merges with is expression of outside value",
          {
            op: 'is',
            lhs: "$test",
            rhs: 10
          })
        .equals({
            op: 'literal',
            value: false
          })

      tests
        .mergeAndWith(
          "merges with left-handed lessThan expression of smaller value",
          {
            op: 'lessThan',
            lhs: "$test",
            rhs: 1
          })
        .equals({
            op: 'lessThan',
            lhs: { op: 'ref', name: 'test' }
            rhs: { op: 'literal', value: 1 }
          })

      tests
        .mergeAndWith(
          "merges with left-handed lessThan expression of equal value",
          {
            op: 'lessThan',
            lhs: "$test",
            rhs: 5
          })
        .equals({
            op: 'lessThan',
            lhs: { op: 'ref', name: 'test' }
            rhs: { op: 'literal', value: 5 }
          })

      tests
        .mergeAndWith(
          "merges with left-handed lessThan expression of larger value",
          {
            op: 'lessThan',
            lhs: "$test",
            rhs: 7
          })
        .equals({
            op: 'lessThan',
            lhs: { op: 'ref', name: 'test' }
            rhs: { op: 'literal', value: 5 }
          })

      tests
        .mergeAndWith(
          "merges with right-handed lessThan expression of smaller value",
          {
            op: 'lessThan',
            lhs: 1,
            rhs: "$test"
          })
        .equals(null)

      tests
        .mergeAndWith(
          "merges with right-handed lessThan expression of equal value",
          {
            op: 'lessThan',
            lhs: 5,
            rhs: "$test"
          })
        .equals({
            op: 'literal',
            value: false
          })

      tests
        .mergeAndWith(
          "merges with right-handed lessThan expression of larger value",
          {
            op: 'lessThan',
            lhs: 7,
            rhs: "$test"
          })
        .equals({
            op: 'literal',
            value: false
          })

      tests
        .mergeAndWith(
          "merges with left-handed lessThanOrEqual expression of smaller value",
          {
            op: 'lessThanOrEqual',
            lhs: "$test",
            rhs: 1
          })
        .equals({
            op: 'lessThanOrEqual',
            lhs: { op: 'ref', name: 'test' }
            rhs: { op: 'literal', value: 1 }
          })

      tests
        .mergeAndWith(
          "merges with left-handed lessThanOrEqual expression of equal value",
          {
            op: 'lessThanOrEqual',
            lhs: "$test",
            rhs: 5
          })
        .equals({
            op: 'lessThan',
            lhs: { op: 'ref', name: 'test' }
            rhs: { op: 'literal', value: 5 }
          })

      tests
        .mergeAndWith(
          "merges with left-handed lessThanOrEqual expression of larger value",
          {
            op: 'lessThanOrEqual',
            lhs: "$test",
            rhs: 7
          })
        .equals({
            op: 'lessThan',
            lhs: { op: 'ref', name: 'test' }
            rhs: { op: 'literal', value: 5 }
          })

      tests
        .mergeAndWith(
          "merges with right-handed lessThanOrEqual expression of smaller value",
          {
            op: 'lessThanOrEqual',
            lhs: 1,
            rhs: "$test"
          })
        .equals({
            "op": "in",
            "lhs": {
              "op": "ref",
              "name": "test"
            },
            "rhs": {
              "op": "literal",
              "value": {
                start: 1,
                end: 5
              }
              type: 'NUMBER_RANGE'
            }
          })

      tests
        .mergeAndWith(
          "merges with right-handed lessThanOrEqual expression of equal value",
          {
            op: 'lessThanOrEqual',
            lhs: 5,
            rhs: "$test"
          })
        .equals({
            op: 'literal',
            value: false
          })

      tests
        .mergeAndWith(
          "merges with right-handed lessThanOrEqual expression of larger value",
          {
            op: 'lessThanOrEqual',
            lhs: 7,
            rhs: "$test"
          })
        .equals({
            op: 'literal',
            value: false
          })

    describe '#mergeOr', ->
      tests
        .mergeOrWith(
          "merges with is expression of inside value",
          {
            op: 'is',
            lhs: "$test",
            rhs: 1
          })
        .equals({
            op: 'lessThan',
            lhs: { op: 'ref', name: 'test' }
            rhs: { op: 'literal', value: 5 }
          })

      tests
        .mergeOrWith(
          "merges with is expression of outside value",
          {
            op: 'is',
            lhs: "$test",
            rhs: 10
          })
        .equals(null)

      tests
        .mergeOrWith(
          "merges with left-handed lessThan expression of smaller value",
          {
            op: 'lessThan',
            lhs: "$test",
            rhs: 1
          })
        .equals({
            op: 'lessThan',
            lhs: { op: 'ref', name: 'test' }
            rhs: { op: 'literal', value: 5 }
          })

      tests
        .mergeOrWith(
          "merges with left-handed lessThan expression of equal value",
          {
            op: 'lessThan',
            lhs: "$test",
            rhs: 5
          })
        .equals({
            op: 'lessThan',
            lhs: { op: 'ref', name: 'test' }
            rhs: { op: 'literal', value: 5 }
          })

      tests
        .mergeOrWith(
          "merges with left-handed lessThan expression of larger value",
          {
            op: 'lessThan',
            lhs: "$test",
            rhs: 7
          })
        .equals({
            op: 'lessThan',
            lhs: { op: 'ref', name: 'test' }
            rhs: { op: 'literal', value: 7 }
          })

      tests
        .mergeOrWith(
          "merges with right-handed lessThan expression of smaller value",
          {
            op: 'lessThan',
            lhs: 1,
            rhs: "$test"
          })
        .equals({
            op: 'literal',
            value: true
          })

      tests
        .mergeOrWith(
          "merges with right-handed lessThan expression of equal value",
          {
            op: 'lessThan',
            lhs: 5,
            rhs: "$test"
          })
        .equals({
            op: 'not',
            operand: {
              op: 'is'
              lhs: { op: 'ref', name: 'test' }
              rhs: { op: 'literal', value: 5 }
            }
          })

      tests
        .mergeOrWith(
          "merges with right-handed lessThan expression of larger value",
          {
            op: 'lessThan',
            lhs: 7,
            rhs: "$test"
          })
        .equals(null)

      tests
        .mergeOrWith(
          "merges with left-handed lessThanOrEqual expression of smaller value",
          {
            op: 'lessThanOrEqual',
            lhs: "$test",
            rhs: 1
          })
        .equals({
            op: 'lessThan',
            lhs: { op: 'ref', name: 'test' }
            rhs: { op: 'literal', value: 5 }
          })

      tests
        .mergeOrWith(
          "merges with left-handed lessThanOrEqual expression of equal value",
          {
            op: 'lessThanOrEqual',
            lhs: "$test",
            rhs: 5
          })
        .equals({
            op: 'lessThanOrEqual',
            lhs: { op: 'ref', name: 'test' }
            rhs: { op: 'literal', value: 5 }
          })

      tests
        .mergeOrWith(
          "merges with left-handed lessThanOrEqual expression of larger value",
          {
            op: 'lessThanOrEqual',
            lhs: "$test",
            rhs: 7
          })
        .equals({
            op: 'lessThanOrEqual',
            lhs: { op: 'ref', name: 'test' }
            rhs: { op: 'literal', value: 7 }
          })

      tests
        .mergeOrWith(
          "merges with right-handed lessThanOrEqual expression of smaller value",
          {
            op: 'lessThanOrEqual',
            lhs: 1,
            rhs: "$test"
          })
        .equals({
            op: 'literal',
            value: true
          })

      tests
        .mergeOrWith(
          "merges with right-handed lessThanOrEqual expression of equal value",
          {
            op: 'lessThanOrEqual',
            lhs: 5,
            rhs: "$test"
          })
        .equals({
            op: 'literal',
            value: true
          })

      tests
        .mergeOrWith(
          "merges with right-handed lessThanOrEqual expression of larger value",
          {
            op: 'lessThanOrEqual',
            lhs: 7,
            rhs: "$test"
          })
        .equals(null)

  describe 'with right-handed reference', ->
    beforeEach ->
      this.expression = { op: 'lessThan', lhs: { op: 'literal', value: 5 }, rhs: { op: 'ref', name: 'test' } }

    tests.complexityIs(3)
    tests.simplifiedExpressionIs({ op: 'lessThan', lhs: { op: 'literal', value: 5 }, rhs: { op: 'ref', name: 'test' } })

    describe '#mergeAnd', ->
      tests
        .mergeAndWith(
          "merges with is expression of inside value",
          {
            op: 'is',
            lhs: "$test",
            rhs: 10
          })
        .equals({
            op: 'is',
            lhs: { op: 'ref', name: 'test' }
            rhs: { op: 'literal', value: 10 }
          })

      tests
        .mergeAndWith(
          "merges with is expression of inside value",
          {
            op: 'is',
            lhs: "$test",
            rhs: 1
          })
        .equals({
            op: 'literal',
            value: false
          })

      tests
        .mergeAndWith(
          "merges with left-handed lessThan expression of smaller value",
          {
            op: 'lessThan',
            lhs: "$test",
            rhs: 1
          })
        .equals({
            op: 'literal',
            value: false
          })

      tests
        .mergeAndWith(
          "merges with left-handed lessThan expression of equal value",
          {
            op: 'lessThan',
            lhs: "$test",
            rhs: 5
          })
        .equals(null)

      tests
        .mergeAndWith(
          "merges with left-handed lessThan expression of larger value",
          {
            op: 'lessThan',
            lhs: "$test",
            rhs: 7
          })
        .equals(null)

      tests
        .mergeAndWith(
          "merges with right-handed lessThan expression of smaller value",
          {
            op: 'lessThan',
            lhs: 1,
            rhs: "$test"
          })
        .equals({
          op: 'lessThan',
          lhs: { op: 'literal', value: 5 },
          rhs: { op: 'ref', name: 'test' }
        })

      tests
        .mergeAndWith(
          "merges with right-handed lessThan expression of equal value",
          {
            op: 'lessThan',
            lhs: 5,
            rhs: "$test"
          })
        .equals({
            op: 'lessThan',
            lhs: { op: 'literal', value: 5 },
            rhs: { op: 'ref', name: 'test' }
          })

      tests
        .mergeAndWith(
          "merges with right-handed lessThan expression of larger value",
          {
            op: 'lessThan',
            lhs: 7,
            rhs: "$test"
          })
        .equals({
            op: 'lessThan',
            lhs: { op: 'literal', value: 7 },
            rhs: { op: 'ref', name: 'test' }
          })


      tests
        .mergeAndWith(
          "merges with left-handed lessThanOrEqual expression of smaller value",
          {
            op: 'lessThanOrEqual',
            lhs: "$test",
            rhs: 1
          })
        .equals({
            op:'literal',
            value: false
          })

      tests
        .mergeAndWith(
          "merges with left-handed lessThanOrEqual expression of equal value",
          {
            op: 'lessThanOrEqual',
            lhs: "$test",
            rhs: 5
          })
        .equals({
            op:'literal',
            value: false
          })

      tests
        .mergeAndWith(
          "merges with left-handed lessThanOrEqual expression of larger value",
          {
            op: 'lessThanOrEqual',
            lhs: "$test",
            rhs: 7
          })
        .equals(null)

      tests
        .mergeAndWith(
          "merges with right-handed lessThanOrEqual expression of smaller value",
          {
            op: 'lessThanOrEqual',
            lhs: 1,
            rhs: "$test"
          })
        .equals({
            op: 'lessThan',
            lhs: { op: 'literal', value: 5 },
            rhs: { op: 'ref', name: 'test' }
          })

      tests
        .mergeAndWith(
          "merges with right-handed lessThanOrEqual expression of equal value",
          {
            op: 'lessThanOrEqual',
            lhs: 5,
            rhs: "$test"
          })
        .equals({
            op: 'lessThan',
            lhs: { op: 'literal', value: 5 },
            rhs: { op: 'ref', name: 'test' }
          })

      tests
        .mergeAndWith(
          "merges with right-handed lessThanOrEqual expression of larger value",
          {
            op: 'lessThanOrEqual',
            lhs: 7,
            rhs: "$test"
          })
        .equals({
            op: 'lessThanOrEqual',
            lhs: { op: 'literal', value: 7 },
            rhs: { op: 'ref', name: 'test' }
          })

    describe '#mergeOr', ->
      tests
        .mergeOrWith(
          "merges with is expression of inside value",
          {
            op: 'is',
            lhs: "$test",
            rhs: 10
          })
        .equals({
            op: 'lessThan',
            lhs: { op: 'literal', value: 5 }
            rhs: { op: 'ref', name: 'test' }
          })

      tests
        .mergeOrWith(
          "merges with is expression of outside value",
          {
            op: 'is',
            lhs: "$test",
            rhs: 1
          })
        .equals(null)

      tests
        .mergeOrWith(
          "merges with left-handed lessThan expression of smaller value",
          {
            op: 'lessThan',
            lhs: "$test",
            rhs: 1
          })
        .equals(null)

      tests
        .mergeOrWith(
          "merges with left-handed lessThan expression of equal value",
          {
            op: 'lessThan',
            lhs: "$test",
            rhs: 5
          })
        .equals({
            op: 'not',
            operand: {
              op: 'is'
              lhs: { op: 'ref', name: 'test' }
              rhs: { op: 'literal', value: 5 }
            }
          })

      tests
        .mergeOrWith(
          "merges with left-handed lessThan expression of larger value",
          {
            op: 'lessThan',
            lhs: "$test",
            rhs: 7
          })
        .equals({
            op: 'literal'
            value: true
          })

      tests
        .mergeOrWith(
          "merges with right-handed lessThan expression of smaller value",
          {
            op: 'lessThan',
            lhs: 1,
            rhs: "$test"
          })
        .equals({
            op: 'lessThan'
            lhs: { op: 'literal', value: 1 }
            rhs: { op: 'ref', name: 'test' }
          })

      tests
        .mergeOrWith(
          "merges with right-handed lessThan expression of equal value",
          {
            op: 'lessThan',
            lhs: 5,
            rhs: "$test"
          })
        .equals({
            op: 'lessThan'
            lhs: { op: 'literal', value: 5 }
            rhs: { op: 'ref', name: 'test' }
          })

      tests
        .mergeOrWith(
          "merges with right-handed lessThan expression of larger value",
          {
            op: 'lessThan',
            lhs: 7,
            rhs: "$test"
          })
        .equals({
            op: 'lessThan'
            lhs: { op: 'literal', value: 5 }
            rhs: { op: 'ref', name: 'test' }
          })

      tests
        .mergeOrWith(
          "merges with left-handed lessThanOrEqual expression of smaller value",
          {
            op: 'lessThanOrEqual',
            lhs: "$test",
            rhs: 1
          })
        .equals(null)

      tests
        .mergeOrWith(
          "merges with left-handed lessThanOrEqual expression of equal value",
          {
            op: 'lessThanOrEqual',
            lhs: "$test",
            rhs: 5
          })
        .equals({
            op: 'literal'
            value: true
          })

      tests
        .mergeOrWith(
          "merges with left-handed lessThanOrEqual expression of larger value",
          {
            op: 'lessThanOrEqual',
            lhs: "$test",
            rhs: 7
          })
        .equals({
            op: 'literal'
            value: true
          })

      tests
        .mergeOrWith(
          "merges with right-handed lessThanOrEqual expression of smaller value",
          {
            op: 'lessThanOrEqual',
            lhs: 1,
            rhs: "$test"
          })
        .equals({
            op: 'lessThanOrEqual'
            lhs: { op: 'literal', value: 1 }
            rhs: { op: 'ref', name: 'test' }
          })

      tests
        .mergeOrWith(
          "merges with right-handed lessThanOrEqual expression of equal value",
          {
            op: 'lessThanOrEqual',
            lhs: 5,
            rhs: "$test"
          })
        .equals({
            op: 'lessThanOrEqual'
            lhs: { op: 'literal', value: 5 }
            rhs: { op: 'ref', name: 'test' }
          })

      tests
        .mergeOrWith(
          "merges with right-handed lessThanOrEqual expression of larger value",
          {
            op: 'lessThanOrEqual',
            lhs: 7,
            rhs: "$test"
          })
        .equals({
            op: 'lessThan'
            lhs: { op: 'literal', value: 5 }
            rhs: { op: 'ref', name: 'test' }
          })

  describe 'with complex values', ->
    beforeEach ->
      this.expression = { op: 'lessThan', lhs: { op: 'literal', value: 5 }, rhs: { op: 'add', operands: [{ op: 'literal', value: 3 }, { op: 'literal', value: 3 }] } }

    tests.complexityIs(5)
    tests.simplifiedExpressionIs({op:'literal', value: true})
