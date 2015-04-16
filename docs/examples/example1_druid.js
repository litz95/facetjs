var druidRequesterFactory = require('facetjs-druid-requester').druidRequesterFactory;
var facet = require('../../build/facet');
var $ = facet.$;
var Dataset = facet.Dataset;

var druidRequester = druidRequesterFactory({
  host: '10.153.211.100' // Where ever your Druid may be
});

// ----------------------------------

var context = {
  wiki: Dataset.fromJS({
    source: 'druid',
    dataSource: 'wikipedia_editstream',
    timeAttribute: 'time',
    requester: druidRequester
  })
};

var ex = $()
  .def("wiki",
    $('wiki').filter($("time").in({
      start: new Date("2013-02-26T00:00:00Z"),
      end: new Date("2013-02-27T00:00:00Z")
    }).and($('language').is('en')))
  )
  .apply('Count', $('wiki').count())
  .apply('TotalAdded', '$wiki.sum($added)');

ex.compute(context).then(function(data) {
  // Log the data while converting it to a readable standard
  console.log(JSON.stringify(data.toJS(), null, 2));
}).done();

// ----------------------------------

/*
Output:
[
  {
    "Count": 308675,
    "TotalAdded": 41412583
  }
]
*/
