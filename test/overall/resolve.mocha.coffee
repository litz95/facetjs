{ expect } = require("chai")

facet = require('../../build/facet')
{ Expression, Dataset, NativeDataset, $ } = facet

describe "resolve", ->
  describe "errors if", ->
    it "went too deep", ->
      ex = $()
        .apply('num', '$^foo + 1')
        .apply('subData',
          $()
            .apply('x', '$^num * 3')
            .apply('y', '$^^^foo * 10')
        )

      expect(->
        ex.resolve({ foo: 7 })
      ).to.throw('went too deep during resolve on: $^^^foo')

    it "could not find something in context", ->
      ex = $()
        .apply('num', '$^foo + 1')
        .apply('subData',
          $()
            .apply('x', '$^num * 3')
            .apply('y', '$^^foobar * 10')
        )

      expect(->
        ex.resolve({ foo: 7 })
      ).to.throw('could not resolve $^^foobar because is was not in the context')

    it "ended up with bad types", ->
      ex = $()
        .apply('num', '$^foo + 1')
        .apply('subData',
          $()
            .apply('x', '$^num * 3')
            .apply('y', '$^^foo * 10')
        )

      expect(->
        ex.resolve({ foo: 'bar' })
      ).to.throw('add must have an operand of type NUMBER at position 0')


  describe "resolves", ->
    it "works in a basic case", ->
      ex = $('foo').add('$bar')

      context = {
        foo: 7
      }

      ex = ex.resolve(context, true)
      expect(ex.toJS()).to.deep.equal(
        $(7).add('$bar').toJS()
      )

    it "works in a basic case (and simplifies)", ->
      ex = $('foo').add(3)

      context = {
        foo: 7
      }

      ex = ex.resolve(context, true).simplify()
      expect(ex.toJS()).to.deep.equal(
        $(10).toJS()
      )

    it "works in a basic actions case", ->
      ex = $()
        .apply('num', '$^foo + 1')
        .apply('subData',
          $()
            .apply('x', '$^num * 3')
            .apply('y', '$^^foo * 10')
        )

      context = {
        foo: 7
      }

      ex = ex.resolve(context)
      expect(ex.toJS()).to.deep.equal(
        $()
          .apply('num', '7 + 1')
          .apply('subData',
            $()
              .apply('x', '$^num * 3')
              .apply('y', '7 * 10')
          )
          .toJS()
      )

      ex = ex.simplify()
      expect(ex.toJS()).to.deep.equal(
        $()
          .apply('num', 8)
          .apply('subData',
            $()
              .apply('x', '$^num * 3')
              .apply('y', 70)
          )
          .toJS()
      )

    it "works in a basic actions case (in $def)", ->
      ex = $()
        .apply('num', '$^foo + 1')
        .apply('subData',
          $()
            .apply('x', '$^num * 3')
            .apply('y', '$^^foo * 10')
        )

      context = {
        $def: { foo: 7 }
      }

      ex = ex.resolve(context)
      expect(ex.toJS()).to.deep.equal(
        $()
          .apply('num', '7 + 1')
          .apply('subData',
            $()
              .apply('x', '$^num * 3')
              .apply('y', '7 * 10')
          )
          .toJS()
      )

      
  describe "resolves remotes", ->
    context = {
      diamonds: Dataset.fromJS({
        source: 'druid',
        dataSource: 'diamonds',
        timeAttribute: 'time',
        context: null
        attributes: {
          time: { type: 'TIME' }
          color: { type: 'STRING' }
          cut: { type: 'STRING' }
          carat: { type: 'NUMBER' }
        }
      })
      diamonds2: Dataset.fromJS({
        source: 'druid',
        dataSource: 'diamonds2',
        timeAttribute: 'time',
        context: null
        attributes: {
          time: { type: 'TIME' }
          color: { type: 'STRING' }
          cut: { type: 'STRING' }
          carat: { type: 'NUMBER' }
        }
      })
    }

    it "resolves all remotes correctly", ->
      ex = $()
        .apply('Cuts',
          $("diamonds").split("$cut", 'Cut')
            .apply('Count', $('diamonds').count())
            .sort('$Count', 'descending')
            .limit(10)
        )
        .apply('Carats',
          $("diamonds").split($('carat').numberBucket(0.5), 'Carat')
            .apply('Count', $('diamonds').count())
            .sort('$Count', 'descending')
            .limit(10)
        )

      ex = ex.referenceCheck(context)

      expect(ex.every((e) ->
        return (String(e.remote) is 'druid:diamonds') if e.isOp('ref')
        return null
      )).to.equal(true)

    it "resolves two dataset remotes", ->
      ex = $()
        .apply('Cuts',
          $("diamonds").split("$cut", 'Cut')
            .apply('Count', $('diamonds').count())
            .sort('$Count', 'descending')
            .limit(10)
        )
        .apply('Carats',
          $("diamonds2").split($('carat').numberBucket(0.5), 'Carat')
            .apply('Count', $('diamonds2').count())
            .sort('$Count', 'descending')
            .limit(10)
        )

      ex = ex.referenceCheck(context)

      expect(ex.actions[0].expression.every((e) ->
        return (String(e.remote) is 'druid:diamonds') if e.isOp('ref')
        return null
      )).to.equal(true)

      expect(ex.actions[1].expression.every((e) ->
        return (String(e.remote) is 'druid:diamonds2') if e.isOp('ref')
        return null
      )).to.equal(true)
