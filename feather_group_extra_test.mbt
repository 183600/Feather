///|
test "group registers async endpoints under its prefix" {
  let app = @feather.App::new()
  let api = app.group("/api").group("v1")
  ignore(
    api.websocket("/ws/:room", fn(_ctx, ws) {
      ws.send_text("ws")
      ws.send_close()
    }),
  )
  ignore(api.sse("/events", async fn(_ctx, sse) { sse.send("sse") }))
  ignore(api.stream("/feed", async fn(_ctx, stream) { stream.write("stream") }))
  assert_true(app.has_websocket("/api/v1/ws/7"))
  assert_true(app.has_sse("/api/v1/events"))
  assert_true(app.has_stream("/api/v1/feed"))
  assert_false(app.has_websocket("/ws/7"))
  assert_false(app.has_sse("/events"))
  assert_false(app.has_stream("/feed"))
  match app.resolve_websocket("/api/v1/ws/7") {
    Some((_handler, params)) => assert_eq(params.get("room"), Some("7"))
    None => fail("expected the group websocket to resolve")
  }
}

///|
async test "group middleware guards group websocket endpoints" {
  let app = @feather.App::new()
  let api = app.group("/api")
  ignore(
    api.use(fn(next) {
      fn(ctx) {
        if ctx.header("X-Token") != "secret" {
          ctx.text(401, "unauthorized")
          return
        }
        next(ctx)
      }
    }),
  )
  ignore(
    api.websocket("/ws/:room", fn(ctx, ws) {
      ws.send_text(ctx.param("room"))
      ws.send_close()
    }),
  )
  with_ws_server(app, base => {
    let denied = @http.Client(base.replace(old="ws://", new="http://"))
    defer denied.close()
    let response = denied.get("/api/ws/1")
    assert_eq(response.code, 401)
    assert_eq(denied.read_all().text(), "unauthorized")
  })
  with_ws_server(app, base => {
    let ws = @websocket.connect(
      base + "/api/ws/1",
      headers=Map([(@http.CaseInsensitiveString("X-Token"), "secret")]),
    )
    defer ws.close()
    assert_eq(ws.recv().read_all().text(), "1")
    ws.send_close()
  })
}

///|
async test "group middleware decorates group sse and stream endpoints" {
  let app = @feather.App::new()
  let api = app.group("/api").use(tag_header("X-Group", "yes"))
  ignore(api.sse("/events", async fn(_ctx, sse) { sse.send("sse") }))
  ignore(api.stream("/feed", async fn(_ctx, stream) { stream.write("stream") }))
  with_sse_server(app, client => {
    let response = client.get("/api/events")
    assert_eq(response.code, 200)
    assert_eq(
      response.headers.get(@http.CaseInsensitiveString("X-Group")),
      Some("yes"),
    )
    assert_eq(client.read_all().text(), "data: sse\n\n")
  })
  with_stream_server(app, client => {
    let response = client.get("/api/feed")
    assert_eq(response.code, 200)
    assert_eq(
      response.headers.get(@http.CaseInsensitiveString("X-Group")),
      Some("yes"),
    )
    assert_eq(client.read_all().text(), "stream")
  })
}

///|
async test "group static_files nests under the group prefix" {
  let dir = @fs.tmpdir(prefix="feather-group-static")
  @fs.write_file(dir + "/hello.txt", "group file")
  let app = @feather.App::new()
  ignore(app.group("/api").static_files("/assets", dir))
  with_server(app, client => {
    let response = client.get("/api/assets/hello.txt")
    assert_eq(response.code, 200)
    assert_eq(client.read_all().text(), "group file")
    let missing = client.get("/assets/hello.txt")
    assert_eq(missing.code, 404)
    ignore(client.read_all())
  })
  @fs.rmdir(dir, recursive=true)
}

///|
test "group mount applies group middleware to mounted routes" {
  let child = @feather.App::new()
    .get("/ping", fn(ctx) { ctx.text(200, "pong") })
    .websocket("/ws", fn(_ctx, ws) {
      ws.send_text("ws")
      ws.send_close()
    })
  let app = @feather.App::new()
  let api = app.group("/api").use(tag_header("X-Group", "yes"))
  ignore(api.mount("/v1", child))
  let response = app.respond({
    method: "GET",
    path: "/api/v1/ping",
    headers: Map([]),
    body: "",
  })
  assert_eq(response.status, 200)
  assert_eq(response.body, "pong")
  assert_eq(response.headers.get("X-Group"), Some("yes"))
  assert_true(app.has_websocket("/api/v1/ws"))
  assert_false(app.has_websocket("/api/ws"))
}

///|
test "group mount_with nests group middleware outside mount middleware" {
  let child = @feather.App::new()
    .use(fn(next) {
      fn(ctx) {
        ctx.set("order", ctx.get("order") + "C")
        next(ctx)
      }
    })
    .get("/ping", fn(ctx) { ctx.text(200, ctx.get("order")) })
  let app = @feather.App::new()
  let api = app.group("/api").use(fn(next) {
    fn(ctx) {
      ctx.set("order", ctx.get("order") + "G")
      next(ctx)
    }
  })
  ignore(
    api.mount_with("/v1", child, [
      fn(next) {
        fn(ctx) {
          ctx.set("order", ctx.get("order") + "M")
          next(ctx)
        }
      },
    ]),
  )
  let response = app.respond({
    method: "GET",
    path: "/api/v1/ping",
    headers: Map([]),
    body: "",
  })
  assert_eq(response.status, 200)
  assert_eq(response.body, "GMC")
}

///|
async test "mount_with middleware wraps mounted routes and static files" {
  let dir = @fs.tmpdir(prefix="feather-mount-with")
  @fs.write_file(dir + "/hello.txt", "outer file")
  let child = @feather.App::new()
    .get("/ping", fn(ctx) { ctx.text(200, "pong") })
    .static_files("/assets", dir)
  let app = @feather.App::new()
    .get("/ping", fn(ctx) { ctx.text(200, "parent") })
    .mount_with("/api", child, [
      fn(next) {
        fn(ctx) {
          if ctx.header("X-Key") != "open" {
            ctx.text(403, "forbidden")
            return
          }
          ctx.set_header("X-Outer", "on")
          next(ctx)
        }
      },
    ])
  let mounted = app.respond({
    method: "GET",
    path: "/api/ping",
    headers: Map([("X-Key", "open")]),
    body: "",
  })
  assert_eq(mounted.status, 200)
  assert_eq(mounted.body, "pong")
  assert_eq(mounted.headers.get("X-Outer"), Some("on"))
  let denied = app.respond({
    method: "GET",
    path: "/api/ping",
    headers: Map([]),
    body: "",
  })
  assert_eq(denied.status, 403)
  assert_eq(denied.body, "forbidden")
  let parent = app.respond({
    method: "GET",
    path: "/ping",
    headers: Map([]),
    body: "",
  })
  assert_eq(parent.status, 200)
  assert_eq(parent.body, "parent")
  assert_eq(parent.headers.get("X-Outer"), None)
  with_server(app, client => {
    let response = client.get(
      "/api/assets/hello.txt",
      extra_headers=Map([(@http.CaseInsensitiveString("X-Key"), "open")]),
    )
    assert_eq(response.code, 200)
    assert_eq(
      response.headers.get(@http.CaseInsensitiveString("X-Outer")),
      Some("on"),
    )
    assert_eq(client.read_all().text(), "outer file")
  })
  @fs.rmdir(dir, recursive=true)
}

///|
test "feather facade mounts applications with outer middleware" {
  let child = @feather.create_feather({
    host: "127.0.0.1",
    port: 0,
    timeout: 0,
  }).get("/health", fn(ctx) { ctx.text(200, "ok") })
  let feather = @feather.create_feather({
    host: "127.0.0.1",
    port: 0,
    timeout: 0,
  }).mount_with("/svc", child, [tag_header("X-Outer", "on")])
  let response = feather.handle({
    method: "GET",
    path: "/svc/health",
    headers: Map([]),
    body: "",
  })
  assert_eq(response.status, 200)
  assert_eq(response.body, "ok")
  assert_eq(response.headers.get("X-Outer"), Some("on"))
}

///|
test "group prefixes ignore query and fragment suffixes" {
  let app = @feather.App::new()
  let api = app.group("/api?x=1#frag")
  ignore(api.get("/ping", fn(ctx) { ctx.text(200, "pong") }))
  assert_true(app.has_route("GET", "/api/ping"))
  assert_eq(app.routes(), [("GET", "/api/ping")])
  let response = app.respond({
    method: "GET",
    path: "/api/ping",
    headers: Map([]),
    body: "",
  })
  assert_eq(response.status, 200)
  assert_eq(response.body, "pong")
}
