///|
async test "logger reports the status chosen by a streaming handler" {
  let lines : Array[String] = []
  let app = @feather.App::new()
    .use(@feather.middleware_logger(log=line => lines.push(line)))
    .stream("/feed", async fn(_ctx, stream) {
      stream.set_status(201)
      stream.write("created")
    })
  with_stream_server(app, client => {
    let response = client.get("/feed")
    assert_eq(response.code, 201)
    assert_eq(client.read_all().text(), "created")
    @async.sleep(20)
  })
  assert_eq(lines, ["[201] GET /feed"])
}

///|
async test "logger reports a stream failure that never started as 500" {
  let lines : Array[String] = []
  let app = @feather.App::new()
    .use(@feather.middleware_logger(log=line => lines.push(line)))
    .stream("/feed", async fn(_ctx, _stream) { raise Failure("boom") })
  with_stream_server(app, client => {
    let response = client.get("/feed")
    assert_eq(response.code, 500)
    ignore(client.read_all())
    @async.sleep(20)
  })
  assert_eq(lines, ["[500] GET /feed"])
}

///|
async test "logger waits for an sse handler before recording the status" {
  let lines : Array[String] = []
  let app = @feather.App::new()
    .use(@feather.middleware_logger(log=line => lines.push(line)))
    .sse("/events", async fn(_ctx, sse) {
      sse.send("one")
      sse.close()
    })
  with_sse_server(app, client => {
    let response = client.get("/events")
    assert_eq(response.code, 200)
    assert_eq(client.read_all().text(), "data: one\n\n")
    @async.sleep(20)
  })
  assert_eq(lines, ["[200] GET /events"])
}
