express = require('express')
http = require('http')
mysql = require('mysql')

simpleDriver = require('./simpleDriver')
druidDriver = require('./druidDriver')
sqlDriver = require('./sqlDriver')

data = {}
data.data1 = do ->
  pick = (arr) -> arr[Math.floor(Math.random() * arr.length)]
  now = Date.now()
  w = 100
  ret = []
  for i in [0...400]
    ret.push {
      id: i
      time: new Date(now + i * 13 * 1000)
      letter: 'ABC'[Math.floor(3 * i / 400)]
      number: pick([1, 10, 3, 4])
      scoreA: i * Math.random() * Math.random()
      scoreB: 10 * Math.random()
      walk: w += Math.random() - 0.5 + 0.02
    }
  return ret

data.diamonds = require('../data/diamonds.js')


druidPost = ({host, port, path}) ->
  opts = {
    host
    port
    path
    method: 'POST'
    headers: {
      'content-type': 'application/json'
    }
  }
  return (druidQuery, callback) ->
    druidQuery = new Buffer(JSON.stringify(druidQuery), 'utf-8')
    opts.headers['content-length'] = druidQuery.length
    req = http.request(opts, (response) ->
      # response.statusCode
      # response.headers
      # response.statusCode

      response.setEncoding('utf8')
      chunks = []
      response.on 'data', (chunk) ->
        chunks.push(chunk)
        return

      response.on 'close', (err) ->
        console.log 'CLOSE'
        return

      response.on 'end', ->
        chunks = chunks.join('')
        if response.statusCode isnt 200
          callback(chunks, null)
          return

        try
          chunks = JSON.parse(chunks)
        catch e
          callback(e, null)
          return

        callback(null, chunks)
        return
      return
    )

    req.write(druidQuery.toString('utf-8'))
    req.end()
    return

sqlRequester =({host, user, password, dataset}) ->
  connection = mysql.createConnection({
    host: 'localhost'
    user: 'root'
    password: 'root'
    database: 'facet'
  })

  connection.connect()
  return (sqlQuery, callback) ->
    connection.query(sqlQuery, callback)
    return


app = express()

app.disable('x-powered-by')

app.use(express.compress())
app.use(express.json())

app.use(express.directory(__dirname + '/../static'))
app.use(express.static(__dirname + '/../static'))
app.use(express.static(__dirname + '/../target'))

app.get '/', (req, res) ->
  res.send('Welcome to facet')
  return

respondWithResult = (res) -> (err, result) ->
  if err
    res.json(500, err)
    return
  res.json(result)
  return

# Simple
app.post '/driver/simple', (req, res) ->
  { context, query } = req.body
  simpleDriver(data[context.data])(query, respondWithResult(res))
  return

# SQL
sqlPass = sqlRequester({
  host: 'localhost'
  user: 'root'
  password: 'root'
  database: 'facet'
})
app.post '/pass/sql', (req, res) ->
  { context, query } = req.body
  sqlPass(query, respondWithResult(res))
  return

app.post '/driver/sql', (req, res) ->
  { context, query } = req.body
  sqlDriver({
    requester: sqlPass
    table: context.table
    filters: null
  })(query, respondWithResult(res))
  return

# Druid
druidPass = druidPost({
  #host: '10.60.134.138'
  #port: 8080
  #path: '/druid/v2/'
  host: 'druid-rave.metamx.com'
  port: 80
  path: '/druid/v2/'
})
app.post '/pass/druid', (req, res) ->
  { context, query } = req.body
  druidPass(query, respondWithResult(res))
  return

app.post '/driver/druid', (req, res) ->
  { context, query } = req.body
  druidDriver({
    requester: druidPass
    dataSource: context.dataSource
    interval: context.interval.map((d) -> new Date(d))
    filters: null
  })(query, respondWithResult(res))
  return

# Druid notes:
# http://10.60.134.138:8080/druid/v2/datasources/
# http://10.60.134.138:8080/druid/v2/datasources/wikipedia_editstream
# http://10.60.134.138:8080/druid/v2/datasources/wikipedia_editstream/dimensions

app.listen(9876)
console.log('Listening on port 9876')

