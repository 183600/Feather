///|
async fn with_sse_server(
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
test "App has_sse reports registered streams" {
  let app = @feather.App::new().sse("/events", async fn(_ctx, _sse) { () })
  assert_true(app.has_sse("/events"))
  assert_false(app.has_sse("/other"))
}

///|
test "resolve_sse binds route parameters" {
  let app = @feather.App::new().sse("/stream/:room", async fn(_ctx, _sse) { () })
  match app.resolve_sse("/stream/lobby") {
    Some((_, params)) => assert_eq(params.get("room"), Some("lobby"))
    None => fail("expected the sse route to resolve")
  }
  match app.resolve_sse("/stream") {
    Some(_) => fail("expected a shorter path not to resolve")
    None => ()
  }
}

///|
async test "server streams server-sent events" {
  let app = @feather.App::new().sse("/events", async fn(_ctx, sse) {
    sse.send("one")
    sse.send("two")
    sse.close()
  })
  with_sse_server(app, client => {
    let response = client.get("/events")
    assert_eq(response.code, 200)
    assert_eq(
      response.headers.get(@http.CaseInsensitiveString("Content-Type")),
      Some("text/event-stream; charset=utf-8"),
    )
    assert_eq(
      response.headers.get(@http.CaseInsensitiveString("Cache-Control")),
      Some("no-cache"),
    )
    assert_eq(client.read_all().text(), "data: one\n\ndata: two\n\n")
  })
}

///|
async test "sse events carry event id and retry fields" {
  let app = @feather.App::new().sse("/events", async fn(_ctx, sse) {
    sse.send("payload", event="update", id="2", retry=3000)
  })
  with_sse_server(app, client => {
    let response = client.get("/events")
    assert_eq(response.code, 200)
    assert_eq(
      client.read_all().text(),
      "event: update\nid: 2\nretry: 3000\ndata: payload\n\n",
    )
  })
}

///|
async test "sse data spans multiple lines" {
  let app = @feather.App::new().sse("/events", async fn(_ctx, sse) {
    sse.send("first\r\nsecond\nthird")
  })
  with_sse_server(app, client => {
    ignore(client.get("/events"))
    assert_eq(
      client.read_all().text(),
      "data: first\ndata: second\ndata: third\n\n",
    )
  })
}

///|
async test "sse empty data still dispatches an event" {
  let app = @feather.App::new().sse("/events", async fn(_ctx, sse) {
    sse.send("")
  })
  with_sse_server(app, client => {
    ignore(client.get("/events"))
    assert_eq(client.read_all().text(), "data: \n\n")
  })
}

///|
async test "sse comments act as keep-alives" {
  let app = @feather.App::new().sse("/events", async fn(_ctx, sse) {
    sse.comment("keep-alive")
    sse.send("x")
  })
  with_sse_server(app, client => {
    ignore(client.get("/events"))
    assert_eq(client.read_all().text(), ": keep-alive\ndata: x\n\n")
  })
}

///|
async test "sse send_json encodes typed payloads" {
  let app = @feather.App::new().sse("/events", async fn(_ctx, sse) {
    sse.send_json({ "ok": true }, event="status", id="1")
  })
  with_sse_server(app, client => {
    ignore(client.get("/events"))
    assert_eq(
      client.read_all().text(),
      "event: status\nid: 1\ndata: {\"ok\":true}\n\n",
    )
  })
}

///|
async test "sse send after close is ignored" {
  let app = @feather.App::new().sse("/events", async fn(_ctx, sse) {
    sse.send("only")
    sse.close()
    assert_true(sse.is_closed())
    sse.send("dropped")
  })
  with_sse_server(app, client => {
    ignore(client.get("/events"))
    assert_eq(client.read_all().text(), "data: only\n\n")
  })
}

///|
async test "sse handlers see query parameters" {
  let app = @feather.App::new().sse("/events", async fn(ctx, sse) {
    sse.send(ctx.query("q"))
  })
  with_sse_server(app, client => {
    ignore(client.get("/events?q=feather%20sse"))
    assert_eq(client.read_all().text(), "data: feather sse\n\n")
  })
}

///|
async test "sse route parameters reach the handler" {
  let app = @feather.App::new().sse("/ticks/:id", async fn(ctx, sse) {
    sse.send("tick " + ctx.param("id"))
  })
  with_sse_server(app, client => {
    ignore(client.get("/ticks/42"))
    assert_eq(client.read_all().text(), "data: tick 42\n\n")
  })
}

///|
async test "sse routes do not shadow ordinary routes" {
  let app = @feather.App::new()
    .get("/events", fn(ctx) { ctx.text(200, "plain") })
    .sse("/stream", async fn(_ctx, sse) { sse.send("live") })
  with_sse_server(app, client => {
    let plain = client.get("/events")
    assert_eq(plain.code, 200)
    assert_eq(client.read_all().text(), "plain")
    ignore(client.get("/stream"))
    assert_eq(client.read_all().text(), "data: live\n\n")
  })
}

///|
async test "mount carries sse routes under the prefix" {
  let child = @feather.App::new().sse("/events", async fn(_ctx, sse) {
    sse.send("mounted")
  })
  let parent = @feather.App::new().mount("/api", child)
  with_sse_server(parent, client => {
    ignore(client.get("/api/events"))
    assert_eq(client.read_all().text(), "data: mounted\n\n")
  })
}

///|
async test "unknown sse path falls back to the router" {
  let app = @feather.App::new().sse("/events", async fn(_ctx, sse) {
    sse.send("live")
  })
  with_sse_server(app, client => {
    let response = client.get("/missing")
    assert_eq(response.code, 404)
    assert_eq(client.read_all().text(), "404 Not Found")
  })
}

///|
async test "sse handler failure tears the stream down" {
  let app = @feather.App::new().sse("/events", async fn(_ctx, sse) {
    sse.send("before")
    raise Failure("boom")
  })
  with_sse_server(app, client => {
    let response = client.get("/events")
    assert_eq(response.code, 200)
    assert_eq(client.read_all().text(), "data: before\n\n")
  })
}

///|
async test "sse comments strip carriage returns" {
  let app = @feather.App::new().sse("/events", async fn(_ctx, sse) {
    sse.comment("x\rdata: forged")
  })
  with_sse_server(app, client => {
    ignore(client.get("/events"))
    assert_eq(client.read_all().text(), ": xdata: forged\n")
  })
}

///|
async test "sse data keeps a trailing line break" {
  let app = @feather.App::new().sse("/events", async fn(_ctx, sse) {
    sse.send("line\n")
  })
  with_sse_server(app, client => {
    ignore(client.get("/events"))
    assert_eq(client.read_all().text(), "data: line\ndata: \n\n")
  })
}

///|
async test "sse routes run application middleware and merge its headers" {
  let app = @feather.App::new()
    .use(fn(next) {
      fn(ctx) raise {
        ctx.set_header("X-Middleware", "yes")
        ctx.set_cookie("probe", "1")
        if ctx.header("X-Token") == "secret" {
          next(ctx)
        } else {
          ctx.text(401, "unauthorized")
        }
      }
    })
    .sse("/events", async fn(_ctx, sse) { sse.send("live") })
  with_sse_server(app, client => {
    let rejected = client.get("/events")
    assert_eq(rejected.code, 401)
    assert_eq(client.read_all().text(), "unauthorized")
    let response = client.get(
      "/events",
      extra_headers=Map([(@http.CaseInsensitiveString("X-Token"), "secret")]),
    )
    assert_eq(response.code, 200)
    assert_eq(
      response.headers.get(@http.CaseInsensitiveString("X-Middleware")),
      Some("yes"),
    )
    assert_eq(response.cookies.length(), 1)
    assert_eq(response.cookies[0].name, "probe")
    assert_eq(response.cookies[0].value, "1")
    assert_eq(
      response.headers.get(@http.CaseInsensitiveString("Content-Type")),
      Some("text/event-stream; charset=utf-8"),
    )
    assert_eq(client.read_all().text(), "data: live\n\n")
  })
}
