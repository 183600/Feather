///|
async fn with_stream_server(
  app : @feather.App,
  run : async (@http.Client) -> Unit,
) -> Unit {
  @async.with_task_group(group => {
    let server = @http.Server(@socket.Addr::parse("127.0.0.1:0"))
    let addr = server.addr
    group.spawn_bg(no_wait=true, () => app.serve_with(server))
    @async.sleep(50)
    let client = @http.Client("http://127.0.0.1:\{addr.port()}")
    defer client.close()
    run(client)
    server.close()
  })
}

///|
test "App has_stream reports registered streams" {
  let app = @feather.App::new().stream("/feed", async fn(_ctx, _stream) { () })
  assert_true(app.has_stream("/feed"))
  assert_false(app.has_stream("/other"))
}

///|
test "resolve_stream binds route parameters" {
  let app = @feather.App::new().stream("/feed/:room", async fn(_ctx, _stream) {
    ()
  })
  match app.resolve_stream("/feed/lobby") {
    Some((_, params)) => assert_eq(params.get("room"), Some("lobby"))
    None => fail("expected the stream route to resolve")
  }
  match app.resolve_stream("/feed") {
    Some(_) => fail("expected a shorter path not to resolve")
    None => ()
  }
}

///|
async test "server streams chunks as they are written" {
  let app = @feather.App::new().stream("/feed", async fn(_ctx, stream) {
    stream.write("one")
    stream.write("two")
    stream.write("three")
  })
  with_stream_server(app, client => {
    let response = client.get("/feed")
    assert_eq(response.code, 200)
    assert_eq(
      response.headers.get(@http.CaseInsensitiveString("Content-Type")),
      Some("text/plain; charset=utf-8"),
    )
    assert_eq(client.read_all().text(), "onetwothree")
  })
}

///|
async test "stream status and headers are configurable before the first write" {
  let app = @feather.App::new().stream("/feed", async fn(_ctx, stream) {
    stream.set_status(201)
    stream.set_header("Content-Type", "application/x-ndjson")
    stream.set_header("X-Feed", "yes")
    stream.write("{\"n\":1}\n")
  })
  with_stream_server(app, client => {
    let response = client.get("/feed")
    assert_eq(response.code, 201)
    assert_eq(
      response.headers.get(@http.CaseInsensitiveString("Content-Type")),
      Some("application/x-ndjson"),
    )
    assert_eq(
      response.headers.get(@http.CaseInsensitiveString("X-Feed")),
      Some("yes"),
    )
    assert_eq(client.read_all().text(), "{\"n\":1}\n")
  })
}

///|
async test "stream metadata changes after start are ignored" {
  let app = @feather.App::new().stream("/feed", async fn(_ctx, stream) {
    stream.write("first")
    assert_true(stream.is_started())
    stream.set_status(500)
    stream.set_header("X-Late", "no")
    stream.write("second")
  })
  with_stream_server(app, client => {
    let response = client.get("/feed")
    assert_eq(response.code, 200)
    assert_eq(response.headers.get(@http.CaseInsensitiveString("X-Late")), None)
    assert_eq(client.read_all().text(), "firstsecond")
  })
}

///|
async test "stream write_json emits compact json" {
  let app = @feather.App::new().stream("/feed", async fn(_ctx, stream) {
    stream.write_json({ "ok": true })
  })
  with_stream_server(app, client => {
    ignore(client.get("/feed"))
    assert_eq(client.read_all().text(), "{\"ok\":true}")
  })
}

///|
async test "stream write_bytes sends raw bytes" {
  let app = @feather.App::new().stream("/bin", async fn(_ctx, stream) {
    stream.write_bytes(@utf8.encode("raw"))
    stream.write_bytes(@utf8.encode("-bytes"))
  })
  with_stream_server(app, client => {
    ignore(client.get("/bin"))
    assert_eq(client.read_all().text(), "raw-bytes")
  })
}

///|
async test "stream write_reader copies a reader into the body" {
  let app = @feather.App::new().stream("/copy", async fn(_ctx, stream) {
    let reader = @io.MemoryReader(async fn(writer) {
      writer.write(@utf8.encode("from-"))
      writer.write(@utf8.encode("reader"))
    })
    stream.write_reader(reader)
  })
  with_stream_server(app, client => {
    ignore(client.get("/copy"))
    assert_eq(client.read_all().text(), "from-reader")
  })
}

///|
async test "stream write_reader starts an otherwise empty response" {
  let app = @feather.App::new().stream("/copy", async fn(_ctx, stream) {
    let reader = @io.MemoryReader(async fn(_writer) { () })
    stream.write_reader(reader)
    assert_true(stream.is_started())
  })
  with_stream_server(app, client => {
    let response = client.get("/copy")
    assert_eq(response.code, 200)
    assert_eq(client.read_all().text(), "")
  })
}

///|
async test "stream close without writes still sends an empty response" {
  let app = @feather.App::new().stream("/feed", async fn(_ctx, _stream) { () })
  with_stream_server(app, client => {
    let response = client.get("/feed")
    assert_eq(response.code, 200)
    assert_eq(client.read_all().text(), "")
  })
}

///|
async test "stream writes after close are ignored" {
  let app = @feather.App::new().stream("/feed", async fn(_ctx, stream) {
    stream.write("only")
    stream.close()
    assert_true(stream.is_closed())
    stream.write("dropped")
    stream.close()
  })
  with_stream_server(app, client => {
    ignore(client.get("/feed"))
    assert_eq(client.read_all().text(), "only")
  })
}

///|
async test "stream handler failure tears the stream down" {
  let app = @feather.App::new().stream("/feed", async fn(_ctx, stream) {
    stream.write("before")
    raise Failure("boom")
  })
  with_stream_server(app, client => {
    let response = client.get("/feed")
    assert_eq(response.code, 200)
    // The handler failed after the header went out, so the response is
    // truncated before its terminating chunk: the client must see the failure
    // rather than accept a partial body as a complete one.
    let mut truncated = false
    ignore(client.read_all()) catch {
      _ => truncated = true
    }
    assert_true(truncated)
  })
}

///|
async test "stream route parameters and query reach the handler" {
  let app = @feather.App::new().stream("/ticks/:id", async fn(ctx, stream) {
    stream.write(ctx.param("id"))
    stream.write(":")
    stream.write(ctx.query("q"))
  })
  with_stream_server(app, client => {
    ignore(client.get("/ticks/42?q=fast"))
    assert_eq(client.read_all().text(), "42:fast")
  })
}

///|
async test "mount carries stream routes under the prefix" {
  let child = @feather.App::new().stream("/feed", async fn(_ctx, stream) {
    stream.write("mounted")
  })
  let parent = @feather.App::new().mount("/api", child)
  with_stream_server(parent, client => {
    ignore(client.get("/api/feed"))
    assert_eq(client.read_all().text(), "mounted")
  })
}

///|
async test "stream routes do not shadow ordinary routes" {
  let app = @feather.App::new()
    .get("/feed", fn(ctx) { ctx.text(200, "plain") })
    .stream("/live", async fn(_ctx, stream) { stream.write("chunked") })
  with_stream_server(app, client => {
    let plain = client.get("/feed")
    assert_eq(plain.code, 200)
    assert_eq(client.read_all().text(), "plain")
    ignore(client.get("/live"))
    assert_eq(client.read_all().text(), "chunked")
  })
}

///|
async test "unknown stream path falls back to the router" {
  let app = @feather.App::new().stream("/feed", async fn(_ctx, stream) {
    stream.write("live")
  })
  with_stream_server(app, client => {
    let response = client.get("/missing")
    assert_eq(response.code, 404)
    assert_eq(client.read_all().text(), "404 Not Found")
  })
}

///|
async test "stream routes run application middleware and inherit its response" {
  let app = @feather.App::new()
    .use(fn(next) {
      fn(ctx) raise {
        ctx.set_header("X-Middleware", "yes")
        ctx.status(201)
        if ctx.header("X-Token") == "secret" {
          next(ctx)
        } else {
          ctx.text(401, "unauthorized")
        }
      }
    })
    .stream("/feed", async fn(_ctx, stream) {
      stream.write("live")
    })
  with_stream_server(app, client => {
    let rejected = client.get("/feed")
    assert_eq(rejected.code, 401)
    assert_eq(client.read_all().text(), "unauthorized")
    let response = client.get(
      "/feed",
      extra_headers=Map([(@http.CaseInsensitiveString("X-Token"), "secret")]),
    )
    assert_eq(response.code, 201)
    assert_eq(
      response.headers.get(@http.CaseInsensitiveString("X-Middleware")),
      Some("yes"),
    )
    assert_eq(
      response.headers.get(@http.CaseInsensitiveString("Content-Type")),
      Some("text/plain; charset=utf-8"),
    )
    assert_eq(client.read_all().text(), "live")
  })
}

///|
test "Feather stream registers a resolvable stream route" {
  let app = @feather.create_feather(
    { host: "127.0.0.1", port: 0, timeout: 0 },
  ).stream("/feed", async fn(_ctx, stream) { stream.write("x") })
  assert_true(app.app.has_stream("/feed"))
}

///|
async test "stream ignores framing headers set by the handler" {
  let app = @feather.App::new().stream("/feed", async fn(_ctx, stream) {
    stream.set_header("Content-Length", "999")
    stream.set_header("Transfer-Encoding", "identity")
    stream.set_header("Connection", "keep-alive")
    stream.write("abc")
  })
  with_stream_server(app, client => {
    let response = client.get("/feed")
    assert_eq(response.code, 200)
    assert_eq(
      response.headers.get(@http.CaseInsensitiveString("Content-Length")),
      None,
    )
    assert_eq(client.read_all().text(), "abc")
  })
}

///|
async test "stream header names are case-insensitive" {
  let app = @feather.App::new().stream("/feed", async fn(_ctx, stream) {
    stream.set_header("x-feed", "first")
    stream.set_header("X-Feed", "second")
    stream.write("ok")
  })
  with_stream_server(app, client => {
    let response = client.get("/feed")
    assert_eq(
      response.headers.get(@http.CaseInsensitiveString("X-Feed")),
      Some("second"),
    )
    assert_eq(client.read_all().text(), "ok")
  })
}
