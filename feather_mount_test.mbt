///|
test "mount exposes child routes under the prefix" {
  let child = @feather.App::new().get("/users/:id", fn(ctx) {
    ctx.text(200, "user " + ctx.param("id"))
  })
  let app = @feather.App::new().get("/", fn(ctx) { ctx.text(200, "root") }).mount(
    "/api",
    child,
  )
  let mounted = app.respond({
    method: "GET",
    path: "/api/users/42",
    headers: Map([]),
    body: "",
  })
  assert_eq(mounted.status, 200)
  assert_eq(mounted.body, "user 42")
  let root = app.respond({
    method: "GET",
    path: "/",
    headers: Map([]),
    body: "",
  })
  assert_eq(root.body, "root")
  let missing = app.respond({
    method: "GET",
    path: "/users/42",
    headers: Map([]),
    body: "",
  })
  assert_eq(missing.status, 404)
}

///|
fn tag_header(name : String, value : String) -> @feather.Middleware {
  fn(next) {
    fn(ctx) {
      ctx.set_header(name, value)
      next(ctx)
    }
  }
}

///|
test "mount keeps child middleware scoped to the prefix" {
  let child = @feather.App::new()
    .use(tag_header("X-Child", "yes"))
    .get("/thing", fn(ctx) { ctx.text(200, "child") })
  let app = @feather.App::new()
    .mount("/sub", child)
    .get("/thing", fn(ctx) { ctx.text(200, "parent") })
  let mounted = app.respond({
    method: "GET",
    path: "/sub/thing",
    headers: Map([]),
    body: "",
  })
  assert_eq(mounted.headers.get("X-Child"), Some("yes"))
  let parent = app.respond({
    method: "GET",
    path: "/thing",
    headers: Map([]),
    body: "",
  })
  assert_eq(parent.headers.get("X-Child"), None)
}

///|
test "mount applies parent middleware to mounted routes" {
  let child = @feather.App::new().get("/ping", fn(ctx) { ctx.text(200, "pong") })
  let app = @feather.App::new()
    .use(tag_header("X-Parent", "on"))
    .mount("/api", child)
  let response = app.respond({
    method: "GET",
    path: "/api/ping",
    headers: Map([]),
    body: "",
  })
  assert_eq(response.body, "pong")
  assert_eq(response.headers.get("X-Parent"), Some("on"))
}

///|
test "mount supports nested applications" {
  let grandchild = @feather.App::new().get("/deep", fn(ctx) {
    ctx.text(200, "deep")
  })
  let child = @feather.App::new().mount("/v1", grandchild)
  let app = @feather.App::new().mount("/api", child)
  let response = app.respond({
    method: "GET",
    path: "/api/v1/deep",
    headers: Map([]),
    body: "",
  })
  assert_eq(response.status, 200)
  assert_eq(response.body, "deep")
}

///|
test "mount rewrites named routes" {
  let child = @feather.App::new().route_named(
    "user",
    "GET",
    "/users/:id",
    fn(ctx) { ctx.text(200, "ok") },
  )
  let app = @feather.App::new().mount("/api", child)
  assert_eq(
    app.url_for("user", params=Map([("id", "7")])),
    Some("/api/users/7"),
  )
}

///|
test "mount rewrites websocket registrations" {
  let child = @feather.App::new().websocket("/ws/room/:room", fn(_ctx, _ws) {
    ()
  })
  let app = @feather.App::new().mount("/api", child)
  assert_true(app.has_websocket("/api/ws/room/9"))
  assert_false(app.has_websocket("/ws/room/9"))
  match app.resolve_websocket("/api/ws/room/9") {
    Some((_handler, params)) => assert_eq(params.get("room"), Some("9"))
    None => fail("expected mounted websocket")
  }
}

///|
test "mount drops the child fallback" {
  let child = @feather.App::new()
    .get("/known", fn(ctx) { ctx.text(200, "known") })
    .fallback(fn(ctx) { ctx.text(200, "child fallback") })
  let app = @feather.App::new()
    .fallback(fn(ctx) { ctx.text(200, "parent fallback") })
    .mount("/api", child)
  let known = app.respond({
    method: "GET",
    path: "/api/known",
    headers: Map([]),
    body: "",
  })
  assert_eq(known.body, "known")
  let unknown = app.respond({
    method: "GET",
    path: "/api/nope",
    headers: Map([]),
    body: "",
  })
  assert_eq(unknown.body, "parent fallback")
}

///|
async test "mount serves child static files under the prefix" {
  let dir = @fs.tmpdir(prefix="feather-mount-static")
  @fs.write_file(dir + "/hello.txt", "mounted file")
  let child = @feather.App::new().static_files("/assets", dir)
  let app = @feather.App::new().mount("/api", child)
  with_server(app, client => {
    client.request(@http.RequestMethod::Get, "/api/assets/hello.txt")
    let response = client.end_request()
    assert_eq(response.code, 200)
    assert_eq(client.read_all().text(), "mounted file")
    client.request(@http.RequestMethod::Get, "/assets/hello.txt")
    let missing = client.end_request()
    assert_eq(missing.code, 404)
    ignore(client.read_all())
  })
  @fs.rmdir(dir, recursive=true)
}

///|
test "mount at the root keeps child paths" {
  let child = @feather.App::new()
    .get("/plain", fn(ctx) { ctx.text(200, "plain") })
    .static_files("", "/tmp/feather-root-mount")
  let app = @feather.App::new().mount("", child)
  let response = app.respond({
    method: "GET",
    path: "/plain",
    headers: Map([]),
    body: "",
  })
  assert_eq(response.status, 200)
  assert_eq(response.body, "plain")
}

///|
async test "mount applies child middleware to async endpoints" {
  let auth : @feather.Middleware = fn(next) {
    fn(ctx) raise {
      ctx.set_header("X-Child", "yes")
      if ctx.header("X-Token") == "secret" {
        next(ctx)
      } else {
        ctx.text(401, "unauthorized")
      }
    }
  }
  let child = @feather.App::new()
    .use(auth)
    .websocket("/ws", fn(_ctx, ws) {
      ws.send_text("ws")
      ws.send_close()
    })
    .sse("/events", async fn(_ctx, sse) { sse.send("sse") })
    .stream("/feed", async fn(_ctx, stream) { stream.write("stream") })
  let app = @feather.App::new()
    .use(tag_header("X-Parent", "on"))
    .mount("/api", child)
  with_server(app, client => {
    for path in ["/api/ws", "/api/events", "/api/feed"] {
      let response = client.get(path)
      assert_eq(response.code, 401)
      assert_eq(
        response.headers.get(@http.CaseInsensitiveString("X-Parent")),
        Some("on"),
      )
      assert_eq(
        response.headers.get(@http.CaseInsensitiveString("X-Child")),
        Some("yes"),
      )
      assert_eq(client.read_all().text(), "unauthorized")
    }
  })
  with_ws_server(app, base => {
    let ws = @websocket.connect(
      base + "/api/ws",
      headers=Map([(@http.CaseInsensitiveString("X-Token"), "secret")]),
    )
    defer ws.close()
    assert_eq(ws.recv().read_all().text(), "ws")
    ws.send_close()
  })
  with_sse_server(app, client => {
    let response = client.get(
      "/api/events",
      extra_headers=Map([(@http.CaseInsensitiveString("X-Token"), "secret")]),
    )
    assert_eq(
      response.headers.get(@http.CaseInsensitiveString("X-Child")),
      Some("yes"),
    )
    assert_eq(client.read_all().text(), "data: sse\n\n")
  })
  with_stream_server(app, client => {
    let response = client.get(
      "/api/feed",
      extra_headers=Map([(@http.CaseInsensitiveString("X-Token"), "secret")]),
    )
    assert_eq(
      response.headers.get(@http.CaseInsensitiveString("X-Child")),
      Some("yes"),
    )
    assert_eq(client.read_all().text(), "stream")
  })
}

///|
test "feather facade mounts applications" {
  let child = @feather.create_feather({
    host: "127.0.0.1",
    port: 0,
    timeout: 0,
  }).get("/health", fn(ctx) { ctx.text(200, "ok") })
  let feather = @feather.create_feather({
    host: "127.0.0.1",
    port: 0,
    timeout: 0,
  }).mount("/svc", child)
  let response = feather.handle({
    method: "GET",
    path: "/svc/health",
    headers: Map([]),
    body: "",
  })
  assert_eq(response.status, 200)
  assert_eq(response.body, "ok")
}

///|
async test "mount applies child middleware to static files" {
  let dir = @fs.tmpdir(prefix="feather-mount-static-middleware")
  @fs.write_file(dir + "/hello.txt", "mounted file")
  let child = @feather.App::new()
    .use(tag_header("X-Child", "yes"))
    .static_files("/assets", dir)
  let app = @feather.App::new()
    .use(tag_header("X-Parent", "on"))
    .mount("/api", child)
  with_server(app, client => {
    let response = client.get("/api/assets/hello.txt")
    assert_eq(response.code, 200)
    assert_eq(
      response.headers.get(@http.CaseInsensitiveString("X-Parent")),
      Some("on"),
    )
    assert_eq(
      response.headers.get(@http.CaseInsensitiveString("X-Child")),
      Some("yes"),
    )
    assert_eq(client.read_all().text(), "mounted file")
  })
  @fs.rmdir(dir, recursive=true)
}

///|
async test "nested mounts apply every child middleware to static files" {
  let dir = @fs.tmpdir(prefix="feather-nested-static-middleware")
  @fs.write_file(dir + "/hello.txt", "nested file")
  let grandchild = @feather.App::new()
    .use(tag_header("X-Grandchild", "deep"))
    .static_files("/files", dir)
  let child = @feather.App::new()
    .use(tag_header("X-Child", "yes"))
    .mount("/v1", grandchild)
  let app = @feather.App::new()
    .use(tag_header("X-Parent", "on"))
    .mount("/api", child)
  with_server(app, client => {
    let response = client.get("/api/v1/files/hello.txt")
    assert_eq(response.code, 200)
    for name in ["X-Parent", "X-Child", "X-Grandchild"] {
      assert_true(
        response.headers.get(@http.CaseInsensitiveString(name)) is Some(_),
      )
    }
    assert_eq(client.read_all().text(), "nested file")
  })
  @fs.rmdir(dir, recursive=true)
}

///|
async test "mounted static middleware can short-circuit file serving" {
  let dir = @fs.tmpdir(prefix="feather-mount-static-auth")
  @fs.write_file(dir + "/hidden.txt", "classified")
  let child = @feather.App::new()
    .use(fn(next) {
      fn(ctx) {
        if ctx.header("X-Token") != "secret" {
          ctx.text(403, "forbidden")
          return
        }
        next(ctx)
      }
    })
    .static_files("/assets", dir)
  let app = @feather.App::new().mount("/api", child)
  with_server(app, client => {
    let denied = client.get("/api/assets/hidden.txt")
    assert_eq(denied.code, 403)
    assert_eq(client.read_all().text(), "forbidden")
    let allowed = client.get(
      "/api/assets/hidden.txt",
      extra_headers=Map([(@http.CaseInsensitiveString("X-Token"), "secret")]),
    )
    assert_eq(allowed.code, 200)
    assert_eq(client.read_all().text(), "classified")
  })
  @fs.rmdir(dir, recursive=true)
}
