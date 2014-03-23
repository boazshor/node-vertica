path    = require 'path'
fs      = require 'fs'
assert  = require 'assert'
Vertica = require('../../src/vertica')

describe 'Vertica.Connection#copy', ->
  connection = null


  beforeEach (done) ->
    if !fs.existsSync('./test/connection.json')
      done("Create test/connection.json to run functional tests")
    else
      Vertica.connect JSON.parse(fs.readFileSync('./test/connection.json')), (err, conn) ->
        return done(err) if err?
        connection = conn

        runSetupQueries = (setupQueries, done) ->
          return done() if setupQueries.length == 0
          sql = setupQueries.shift()
          connection.query sql, (err, resultset) ->
            return done(err) if err?
            runSetupQueries(setupQueries, done)

        setupQueries = [
          "DROP TABLE IF EXISTS test_node_vertica_table CASCADE;"
          "CREATE TABLE test_node_vertica_table (id int, name varchar(100))"
          "CREATE PROJECTION IF NOT EXISTS test_node_vertica_table_p (id, name) AS SELECT * FROM test_node_vertica_table SEGMENTED BY HASH(id) ALL NODES OFFSET 1"
        ]
        runSetupQueries(setupQueries, done)


  afterEach ->
    connection.disconnect() if connection.connected


  it "should COPY data from a file", (done) ->
    copySQL  = "COPY test_node_vertica_table FROM STDIN ABORT ON ERROR"
    copyFile = "./test/test_node_vertica_table.csv"
    connection.copy copySQL, copyFile, (err, _) ->
      return done(err) if err?
      
      verifySQL = "SELECT * FROM test_node_vertica_table ORDER BY id"
      connection.query verifySQL, (err, resultset) ->
        return done(err) if err?
        assert.deepEqual resultset.rows, [[11, "Stuff"], [12, "More stuff"], [13, "Final stuff"]]
        done()      


  it "should COPY data from a data handler function", (done) ->
    dataHandler = (data, success, fail) ->
      data("11|Stuff\r\n")
      data("12|More stuff\n13|Fin")
      data("al stuff\n")
      success()

    copySQL = "COPY test_node_vertica_table FROM STDIN ABORT ON ERROR"
    connection.copy copySQL, dataHandler, (err, _) ->
      return done(err) if err?
      
      verifySQL = "SELECT * FROM test_node_vertica_table ORDER BY id"
      connection.query verifySQL, (err, resultset) ->
        return done(err) if err?
        assert.deepEqual resultset.rows, [[11, "Stuff"], [12, "More stuff"], [13, "Final stuff"]]
        done()


  it "should COPY data from a stream function", (done) ->
    stream = fs.createReadStream("./test/test_node_vertica_table.csv");
    copySQL = "COPY test_node_vertica_table FROM STDIN ABORT ON ERROR"
    connection.copy copySQL, stream, (err, _) ->
      stream.close()
      return done(err) if err?
      
      verifySQL = "SELECT * FROM test_node_vertica_table ORDER BY id"
      connection.query verifySQL, (err, resultset) ->
        return done(err) if err?
        assert.deepEqual resultset.rows, [[11, "Stuff"], [12, "More stuff"], [13, "Final stuff"]]
        done()


  it "should not load data if fail is called", (done) ->
    dataHandler = (data, success, fail) ->
      fail("Sorry, not happening")

    copySQL = "COPY test_node_vertica_table FROM STDIN ABORT ON ERROR"
    connection.copy copySQL, dataHandler, (err, _) ->
      return done("Copy error expected") unless err?
      assert.equal err.information['Code'], "08000"
      assert.equal err.information['Message'], "COPY: from stdin failed: Sorry, not happening"
      
      verifySQL = "SELECT * FROM test_node_vertica_table ORDER BY id"
      connection.query verifySQL, (err, resultset) ->
        return done(err) if err?
        assert.equal resultset.getLength(), 0
        done()


  it "should not load data if the input data is invalid", (done) ->
    dataHandler = (data, success, fail) ->
      data("Invalid data")
      success()

    copySQL = "COPY test_node_vertica_table FROM STDIN ABORT ON ERROR"
    connection.copy copySQL, dataHandler, (err, _) ->
      return done("Copy error expected") unless err?
      assert.equal err.information['Code'], "22V04"
      
      verifySQL = "SELECT * FROM test_node_vertica_table ORDER BY id"
      connection.query verifySQL, (err, resultset) ->
        return done(err) if err?

        assert.equal resultset.getLength(), 0
        done()


  it "should fail when not providing a data source", (done) ->
    copySQL = "COPY test_node_vertica_table FROM STDIN ABORT ON ERROR"
    connection.query copySQL, (err, _) ->
      return done("Copy error expected") unless err?
      assert.equal err.information['Code'], '08000'
      assert.equal err.information['Message'], 'COPY: from stdin failed: Error: No copy in handler defined to handle the COPY statement.'
      done()


  it "should fail when throwing an error in the copy handler", (done) ->
    dataHandler = (data, success, fail) ->
      throw new Error("Shit hits the fan!")

    copySQL = "COPY test_node_vertica_table FROM STDIN ABORT ON ERROR"
    connection.copy copySQL, dataHandler, (err, _) ->
      return done("Copy error expected") unless err?
      assert.equal err.information['Code'], "08000"
      assert.equal err.information['Message'], "COPY: from stdin failed: Error: Shit hits the fan!"
      done()
