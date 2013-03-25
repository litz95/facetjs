// Generated by CoffeeScript 1.3.1
var async, diamondsData, driver, druidDriver, druidRequester, simpleDriver, sqlDriver, sqlPass, sqlRequester, testDrivers, uniformizeResults;

async = require('async');

druidRequester = require('../druidRequester').requester;

sqlRequester = require('../mySqlRequester').requester;

simpleDriver = require('../simpleDriver');

druidDriver = require('../druidDriver');

sqlDriver = require('../sqlDriver');

driver = {};

diamondsData = require('../../data/diamonds.js');

driver.simple = simpleDriver(diamondsData);

sqlPass = sqlRequester({
  host: 'localhost',
  user: 'root',
  password: 'root',
  database: 'facet'
});

driver.mySql = sqlDriver({
  requester: sqlPass,
  table: 'diamonds',
  filters: null
});

uniformizeResults = function(result) {
  var name, prop, ret, value, _ref;
  prop = {};
  _ref = result.prop;
  for (name in _ref) {
    value = _ref[name];
    if (!result.prop.hasOwnProperty(name)) {
      continue;
    }
    if (typeof value === 'number' && value !== Math.floor(value)) {
      prop[name] = value.toFixed(3);
    } else if (Array.isArray(value) && typeof value[0] === 'number' && typeof value[1] === 'number' && (value[0] !== Math.floor(value[0]) || value[1] !== Math.floor(value[1]))) {
      prop[name] = [value[0].toFixed(3), value[1].toFixed(3)];
    } else {
      prop[name] = value;
    }
  }
  ret = {
    prop: prop
  };
  if (result.splits) {
    ret.splits = result.splits.map(uniformizeResults);
  }
  return ret;
};

testDrivers = function(_arg) {
  var drivers, query;
  drivers = _arg.drivers, query = _arg.query;
  return function(test) {
    var driversToTest;
    if (drivers.length < 2) {
      throw new Error("must have at least two drivers");
    }
    test.expect(drivers.length);
    driversToTest = drivers.map(function(driverName) {
      if (!driver[driverName]) {
        throw new Error("no such driver " + driverName);
      }
      return function(callback) {
        driver[driverName](query, callback);
      };
    });
    return async.parallel(driversToTest, function(err, results) {
      var i;
      test.ifError(err);
      results = results.map(uniformizeResults);
      i = 1;
      while (i < drivers.length) {
        test.deepEqual(results[0], results[i], "results of '" + drivers[0] + "' and '" + drivers[i] + "' do not match");
        i++;
      }
      test.done();
    });
  };
};

exports["apply count"] = testDrivers({
  drivers: ['simple', 'mySql'],
  query: [
    {
      operation: 'apply',
      name: 'Count',
      aggregate: 'count'
    }
  ]
});

exports["many applies"] = testDrivers({
  drivers: ['simple', 'mySql'],
  query: [
    {
      operation: 'apply',
      name: 'Constant 42',
      aggregate: 'constant',
      value: '42'
    }, {
      operation: 'apply',
      name: 'Count',
      aggregate: 'count'
    }, {
      operation: 'apply',
      name: 'Total Price',
      aggregate: 'sum',
      attribute: 'price'
    }, {
      operation: 'apply',
      name: 'Avg Price',
      aggregate: 'average',
      attribute: 'price'
    }, {
      operation: 'apply',
      name: 'Min Price',
      aggregate: 'min',
      attribute: 'price'
    }, {
      operation: 'apply',
      name: 'Max Price',
      aggregate: 'max',
      attribute: 'price'
    }, {
      operation: 'apply',
      name: 'Num Cuts',
      aggregate: 'uniqueCount',
      attribute: 'cut'
    }
  ]
});

exports["split cut; no apply"] = testDrivers({
  drivers: ['simple', 'mySql'],
  query: [
    {
      operation: 'split',
      name: 'Cut',
      bucket: 'identity',
      attribute: 'cut'
    }, {
      operation: 'combine',
      sort: {
        prop: 'Cut',
        compare: 'natural',
        direction: 'descending'
      }
    }
  ]
});

exports["split cut; apply count"] = testDrivers({
  drivers: ['simple', 'mySql'],
  query: [
    {
      operation: 'split',
      name: 'Cut',
      bucket: 'identity',
      attribute: 'cut'
    }, {
      operation: 'apply',
      name: 'Count',
      aggregate: 'count'
    }, {
      operation: 'combine',
      sort: {
        prop: 'Cut',
        compare: 'natural',
        direction: 'descending'
      }
    }
  ]
});

exports["split carat; apply count"] = testDrivers({
  drivers: ['simple', 'mySql'],
  query: [
    {
      operation: 'split',
      name: 'Carat',
      bucket: 'continuous',
      size: 0.1,
      offset: 0,
      attribute: 'carat'
    }, {
      operation: 'apply',
      name: 'Count',
      aggregate: 'count'
    }, {
      operation: 'combine',
      sort: {
        prop: 'Carat',
        compare: 'natural',
        direction: 'descending'
      }
    }
  ]
});

exports["split cut; apply count > split carat; apply count"] = testDrivers({
  drivers: ['simple', 'mySql'],
  query: [
    {
      operation: 'split',
      name: 'Cut',
      bucket: 'identity',
      attribute: 'cut'
    }, {
      operation: 'apply',
      name: 'Count',
      aggregate: 'count'
    }, {
      operation: 'combine',
      sort: {
        prop: 'Cut',
        compare: 'natural',
        direction: 'descending'
      }
    }, {
      operation: 'split',
      name: 'Carat',
      bucket: 'continuous',
      size: 0.1,
      offset: 0.05,
      attribute: 'carat'
    }, {
      operation: 'apply',
      name: 'Count',
      aggregate: 'count'
    }, {
      operation: 'combine',
      sort: {
        prop: 'Carat',
        compare: 'natural',
        direction: 'descending'
      }
    }
  ]
});
