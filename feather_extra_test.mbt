///|
test "parse_multipart extracts fields and files" {
  let body = "--X\r\nContent-Disposition: form-data; name=\"title\"\r\n\r\nHello\r\n--X\r\nContent-Disposition: form-data; name=\"upload\"; filename=\"a.txt\"\r\nContent-Type: text/plain\r\n\r\nfile-data\r\n--X--\r\n"
  let parts = @feather
    .parse_multipart(body, "multipart/form-data; boundary=X")
    .unwrap()
  assert_eq(parts.length(), 2)
  assert_eq(parts[0].name, "title")
  assert_eq(parts[0].filename, "")
  assert_eq(parts[0].data, "Hello")
  assert_eq(parts[1].name, "upload")
  assert_eq(parts[1].filename, "a.txt")
  assert_eq(parts[1].content_type, "text/plain")
  assert_eq(parts[1].data, "file-data")
}

///|
test "parse_multipart accepts a part with an empty header block" {
  let body = "--X\r\n\r\nbare\r\n--X\r\nContent-Disposition: form-data; name=\"a\"\r\n\r\nvalue\r\n--X--\r\n"
  let parts = @feather
    .parse_multipart(body, "multipart/form-data; boundary=X")
    .unwrap()
  assert_eq(parts.length(), 2)
  assert_eq(parts[0].name, "")
  assert_eq(parts[0].data, "bare")
  assert_eq(parts[1].name, "a")
  assert_eq(parts[1].data, "value")
}

///|
test "parse_multipart requires the multipart/form-data media type" {
  let body = "--X\r\nContent-Disposition: form-data; name=\"a\"\r\n\r\n1\r\n--X--\r\n"
  assert_eq(
    @feather.parse_multipart(body, "text/plain; boundary=X"),
    None,
  )
  assert_eq(
    @feather.parse_multipart(body, "multipart/form-dataz; boundary=X"),
    None,
  )
}

///|
test "parse_multipart reads attributes around quoted separators" {
  let body = "--X\r\nContent-Disposition: form-data; filename=\"a; name=evil.txt\"; name=\"real\"\r\n\r\n1\r\n--X--\r\n"
  let parts = @feather
    .parse_multipart(body, "multipart/form-data; boundary=X")
    .unwrap()
  assert_eq(parts.length(), 1)
  assert_eq(parts[0].name, "real")
  assert_eq(parts[0].filename, "a; name=evil.txt")
}

///|
test "parse_multipart accepts quoted boundary and ignores trailing data" {
  let body = "--b0\r\nContent-Disposition: form-data; name=\"a\"\r\n\r\n1\r\n--b0--\r\nepilogue"
  let parts = @feather
    .parse_multipart(body, "multipart/form-data; boundary=\"b0\"; charset=utf-8")
    .unwrap()
  assert_eq(parts.length(), 1)
  assert_eq(parts[0].data, "1")
}

///|
test "parse_multipart preserves utf8 payloads and empty values" {
  let body = "--z\r\nContent-Disposition: form-data; name=\"greeting\"\r\n\r\n你好\r\n--z\r\nContent-Disposition: form-data; name=\"empty\"\r\n\r\n\r\n--z--\r\n"
  let parts = @feather
    .parse_multipart(body, "multipart/form-data; boundary=z")
    .unwrap()
  assert_eq(parts[0].data, "你好")
  assert_eq(parts[1].name, "empty")
  assert_eq(parts[1].data, "")
}

///|
test "parse_multipart keeps boundary prefixes inside part data" {
  let body = "--X\r\nContent-Disposition: form-data; name=\"a\"\r\n\r\nhello\r\n--Xtra world\r\n--X--\r\n"
  let parts = @feather
    .parse_multipart(body, "multipart/form-data; boundary=X")
    .unwrap()
  assert_eq(parts.length(), 1)
  assert_eq(parts[0].data, "hello\r\n--Xtra world")
}

///|
test "parse_multipart resumes after boundary prefixes in data" {
  let body = "--X\r\nContent-Disposition: form-data; name=\"a\"\r\n\r\none\r\n--Xtwo\r\n--X\r\nContent-Disposition: form-data; name=\"b\"\r\n\r\ntwo\r\n--X--\r\n"
  let parts = @feather
    .parse_multipart(body, "multipart/form-data; boundary=X")
    .unwrap()
  assert_eq(parts.length(), 2)
  assert_eq(parts[0].data, "one\r\n--Xtwo")
  assert_eq(parts[1].name, "b")
  assert_eq(parts[1].data, "two")
}

///|
test "parse_multipart keeps boundary prefixes with lf separators" {
  let body = "--X\nContent-Disposition: form-data; name=\"a\"\n\nhello\n--Xtra\n--X--\n"
  let parts = @feather
    .parse_multipart(body, "multipart/form-data; boundary=X")
    .unwrap()
  assert_eq(parts.length(), 1)
  assert_eq(parts[0].data, "hello\n--Xtra")
}

///|
test "parse_multipart accepts transport padding after delimiters" {
  let body = "--X \t\r\nContent-Disposition: form-data; name=\"a\"\r\n\r\n1\r\n--X \t\r\nContent-Disposition: form-data; name=\"b\"\r\n\r\n2\r\n--X-- \t\r\n"
  let parts = @feather
    .parse_multipart(body, "multipart/form-data; boundary=X")
    .unwrap()
  assert_eq(parts.length(), 2)
  assert_eq(parts[0].name, "a")
  assert_eq(parts[0].data, "1")
  assert_eq(parts[1].name, "b")
  assert_eq(parts[1].data, "2")
  let lf = "--X \t\nContent-Disposition: form-data; name=\"c\"\n\n3\n--X--"
  let lf_parts = @feather
    .parse_multipart(lf, "multipart/form-data; boundary=X")
    .unwrap()
  assert_eq(lf_parts.length(), 1)
  assert_eq(lf_parts[0].data, "3")
}

///|
test "parse_multipart returns none without a boundary" {
  assert_eq(@feather.parse_multipart("body", "text/plain"), None)
  assert_eq(@feather.parse_multipart("body", "multipart/form-data"), None)
}

///|
test "Context multipart helpers expose values and files" {
  let ctx = @feather.Context::new({
    method: "POST",
    path: "/upload",
    headers: { "Content-Type": "multipart/form-data; boundary=sep" },
    body: "--sep\r\nContent-Disposition: form-data; name=\"name\"\r\n\r\nfeather\r\n--sep\r\nContent-Disposition: form-data; name=\"avatar\"; filename=\"a.bin\"\r\nContent-Type: application/octet-stream\r\n\r\n\u{0}\u{1}\r\n--sep--\r\n",
  })
  assert_eq(ctx.multipart_value("name"), "feather")
  assert_eq(ctx.multipart_value("avatar"), "")
  let file = ctx.multipart_file("avatar").unwrap()
  assert_eq(file.filename, "a.bin")
  assert_eq(file.content_type, "application/octet-stream")
  assert_eq(file.data, "\u{0}\u{1}")
  assert_eq(ctx.multipart_file("missing"), None)
}

///|
test "Context multipart helpers ignore other content types" {
  let ctx = @feather.Context::new({
    method: "POST",
    path: "/upload",
    headers: { "Content-Type": "application/json" },
    body: "--sep\r\nContent-Disposition: form-data; name=\"a\"\r\n\r\n1\r\n--sep--\r\n",
  })
  assert_eq(ctx.multipart().length(), 0)
  assert_eq(ctx.multipart_value("a"), "")
}

///|
test "Context queries exposes all query parameters" {
  let ctx = @feather.Context::new({
    method: "GET",
    path: "/search?q=hello+world&page=2",
    headers: Map([]),
    body: "",
  })
  let queries = ctx.queries()
  assert_eq(queries.get("q"), Some("hello world"))
  assert_eq(queries.get("page"), Some("2"))
  assert_eq(queries.get("missing"), None)
  let none = @feather.create_context()
  assert_eq(none.queries().length(), 0)
}

///|
test "Context form_map exposes all form fields" {
  let ctx = @feather.Context::new({
    method: "POST",
    path: "/form",
    headers: { "Content-Type": "Application/X-WWW-Form-Urlencoded" },
    body: "a=1&b=hello%20world",
  })
  let form = ctx.form_map()
  assert_eq(form.get("a"), Some("1"))
  assert_eq(form.get("b"), Some("hello world"))
  let wrong = @feather.Context::new({
    method: "POST",
    path: "/form",
    headers: { "Content-Type": "text/plain" },
    body: "a=1",
  })
  assert_eq(wrong.form_map().length(), 0)
}

///|
test "json_of serializes any ToJson value" {
  let ctx = @feather.create_context()
  ctx.json_of(201, [1, 2, 3])
  assert_eq(ctx.response.status, 201)
  assert_eq(
    ctx.response.headers.get("Content-Type"),
    Some("application/json; charset=utf-8"),
  )
  assert_eq(ctx.response.body, "[1,2,3]")
}

///|
test "fail_with renders payload fields as json" {
  let app = @feather.App::new().get("/item", fn(ctx) raise {
    ctx.fail_with(
      422,
      "invalid item",
      Json::object({ "field": Json::string("name") }),
    )
  })
  let response = app.respond({
    method: "GET",
    path: "/item",
    headers: Map([]),
    body: "",
  })
  assert_eq(response.status, 422)
  assert_eq(
    response.headers.get("Content-Type"),
    Some("application/json; charset=utf-8"),
  )
  assert_true(response.body.contains("invalid item"))
  assert_true(response.body.contains("\"field\""))
  assert_true(response.body.contains("\"name\""))
}

///|
test "fail_with non-object payload becomes detail" {
  let app = @feather.App::new().get("/item", fn(ctx) raise {
    ctx.fail_with(409, "conflict", Json::string("duplicate"))
  })
  let response = app.respond({
    method: "GET",
    path: "/item",
    headers: Map([]),
    body: "",
  })
  assert_eq(response.status, 409)
  assert_true(response.body.contains("\"detail\""))
  assert_true(response.body.contains("duplicate"))
}

///|
test "method not allowed lists sorted methods" {
  let router = @feather.create_router()
  router.add_route("POST", "/res", fn(ctx) { ctx.text(200, "p") })
  router.add_route("GET", "/res", fn(ctx) { ctx.text(200, "g") })
  match router.route("DELETE", "/res") {
    @feather.RouteMethodNotAllowed(methods) => assert_eq(methods.join(","), "GET,POST")
    _ => fail("expected 405")
  }
}

///|
test "App websocket registry resolves paths and params" {
  let app = @feather.App::new().websocket("/ws/room/:room", fn(_ctx, _ws) {
    ()
  })
  assert_true(app.has_websocket("/ws/room/42"))
  assert_false(app.has_websocket("/ws/room/42/extra"))
  assert_false(app.has_websocket("/other"))
  match app.resolve_websocket("/ws/room/42") {
    Some((_handler, params)) => assert_eq(params.get("room"), Some("42"))
    None => fail("expected websocket route")
  }
  assert_true(app.resolve_websocket("/missing") is None)
}

///|
async fn with_ws_server(
  app : @feather.App,
  run : async (String) -> Unit,
) -> Unit {
  @async.with_task_group(group => {
    let server = @http.Server(@socket.Addr::parse("127.0.0.1:0"))
    let addr = server.addr
    group.spawn_bg(no_wait=true, () => app.serve_with(server))
    @async.sleep(50)
    run("ws://127.0.0.1:\{addr.port()}")
    server.close()
  })
}

///|
async test "server upgrades websocket routes" {
  let app = @feather.App::new().websocket("/ws/echo", fn(_ctx, ws) {
    let msg = ws.recv()
    let text = msg.read_all().text()
    ws..start_message(msg.kind)..write(text).end_message()
  })
  with_ws_server(app, base => {
    let ws = @websocket.connect(base + "/ws/echo")
    defer ws.close()
    ws.send_text("hello")
    let msg = ws.recv()
    assert_eq(msg.read_all().text(), "hello")
    ws.send_close()
  })
}

///|
async test "websocket handlers see route params and request state" {
  let app = @feather.App::new().websocket("/ws/room/:room", fn(ctx, ws) {
    let msg = ws.recv()
    ignore(msg.read_all())
    ws
    ..start_message(@websocket.Text)
    ..write(ctx.param("room") + "|" + ctx.get_path())
    .end_message()
  })
  with_ws_server(app, base => {
    let ws = @websocket.connect(base + "/ws/room/7")
    defer ws.close()
    ws.send_text("ping")
    let msg = ws.recv()
    assert_eq(msg.read_all().text(), "7|/ws/room/7")
    ws.send_close()
  })
}

///|
async test "plain http get on websocket route is rejected" {
  let app = @feather.App::new().websocket("/ws/echo", fn(_ctx, _ws) { () })
  with_server(app, client => {
    let response = client.get("/ws/echo")
    assert_eq(response.code, 400)
    ignore(client.read_all())
  })
}

///|
async test "non GET requests on websocket paths fall through to router" {
  let app = @feather.App::new().websocket("/ws/echo", fn(_ctx, _ws) { () })
  with_server(app, client => {
    let response = client.post("/ws/echo", "")
    assert_eq(response.code, 404)
    ignore(client.read_all())
  })
}

///|
async test "websocket routes run application middleware" {
  let app = @feather.App::new()
    .use(fn(next) {
      fn(ctx) raise {
        match ctx.header("X-Token") {
          "secret" => next(ctx)
          "boom" => raise @feather.HttpError(403, "forbidden")
          _ => ctx.text(401, "unauthorized")
        }
      }
    })
    .websocket("/ws/secure", fn(_ctx, ws) {
      ws.send_text("welcome")
      ws.send_close()
    })
  with_server(app, client => {
    let response = client.get("/ws/secure")
    assert_eq(response.code, 401)
    assert_eq(client.read_all().text(), "unauthorized")
    let raised = client.get(
      "/ws/secure",
      extra_headers=Map([(@http.CaseInsensitiveString("X-Token"), "boom")]),
    )
    assert_eq(raised.code, 403)
    assert_eq(
      client.read_all().text(),
      "{\"status\":403,\"error\":\"forbidden\"}",
    )
  })
  with_ws_server(app, base => {
    let ws = @websocket.connect(
      base + "/ws/secure",
      headers=Map([(@http.CaseInsensitiveString("X-Token"), "secret")]),
    )
    defer ws.close()
    let msg = ws.recv()
    assert_eq(msg.read_all().text(), "welcome")
    ws.send_close()
  })
}

///|
test "Context cookies parse request header" {
  let ctx = @feather.Context::new({
    method: "GET",
    path: "/",
    headers: { "Cookie": "session=abc; theme=dark ; broken" },
    body: "",
  })
  assert_eq(ctx.cookie("session"), Some("abc"))
  assert_eq(ctx.cookie("theme"), Some("dark"))
  assert_eq(ctx.cookie("broken"), None)
  assert_eq(ctx.cookie("missing"), None)
  assert_eq(@feather.create_context().cookies().length(), 0)
}

///|
test "Context cookies trim whitespace around values" {
  let ctx = @feather.Context::new({
    method: "GET",
    path: "/",
    headers: { "Cookie": "a= 1; b= \"quoted\"; c=" },
    body: "",
  })
  assert_eq(ctx.cookie("a"), Some("1"))
  assert_eq(ctx.cookie("b"), Some("quoted"))
  assert_eq(ctx.cookie("c"), Some(""))
}

///|
test "Context set_cookie renders attributes" {
  let ctx = @feather.create_context()
  ctx.set_cookie(
    "sid",
    "42",
    path="/",
    max_age=60L,
    http_only=true,
    secure=true,
  )
  assert_eq(
    ctx.response.headers.get("Set-Cookie"),
    Some("sid=42; Path=/; Max-Age=60; HttpOnly; Secure"),
  )
}

///|
test "Context bearer_token extracts token" {
  let ctx = @feather.Context::new({
    method: "GET",
    path: "/",
    headers: { "Authorization": "Bearer abc.def" },
    body: "",
  })
  assert_eq(ctx.bearer_token(), Some("abc.def"))
  let basic = @feather.Context::new({
    method: "GET",
    path: "/",
    headers: { "Authorization": "Basic xyz" },
    body: "",
  })
  assert_eq(basic.bearer_token(), None)
  assert_eq(@feather.create_context().bearer_token(), None)
}

///|
test "middleware_request_id assigns and records ids" {
  let app = @feather.App::new()
    .use(@feather.middleware_request_id())
    .get("/id", fn(ctx) { ctx.text(200, ctx.request_id()) })
  let first = app.respond({
    method: "GET",
    path: "/id",
    headers: Map([]),
    body: "",
  })
  assert_eq(first.headers.get("X-Request-Id"), Some("feather-1"))
  assert_eq(first.body, "feather-1")
  let second = app.respond({
    method: "GET",
    path: "/id",
    headers: Map([]),
    body: "",
  })
  assert_eq(second.headers.get("X-Request-Id"), Some("feather-2"))
}

///|
test "middleware_request_id honors incoming header" {
  let app = @feather.App::new()
    .use(@feather.middleware_request_id())
    .get("/id", fn(ctx) { ctx.text(200, ctx.request_id()) })
  let response = app.respond({
    method: "GET",
    path: "/id",
    headers: { "X-Request-Id": "trace-9" },
    body: "",
  })
  assert_eq(response.headers.get("X-Request-Id"), Some("trace-9"))
  assert_eq(response.body, "trace-9")
}

///|
async test "server renders HttpErrorPayload responses" {
  let app = @feather.App::new().get("/item", fn(ctx) raise {
    ctx.fail_with(
      403,
      "forbidden",
      Json::object({ "reason": Json::string("expired") }),
    )
  })
  with_server(app, client => {
    let response = client.get("/item")
    assert_eq(response.code, 403)
    let body = client.read_all().text()
    assert_true(body.contains("expired"))
  })
}

///|
async test "server parses multipart form data" {
  let app = @feather.App::new().post("/upload", fn(ctx) {
    let file = ctx.multipart_file("file").unwrap()
    ctx.text(200, ctx.multipart_value("name") + ":" + file.data)
  })
  with_server(app, client => {
    let body = "--B\r\nContent-Disposition: form-data; name=\"name\"\r\n\r\nfeather\r\n--B\r\nContent-Disposition: form-data; name=\"file\"; filename=\"a.txt\"\r\n\r\nhello\r\n--B--\r\n"
    let response = client.post(
      "/upload",
      body,
      extra_headers=Map([
        (
          @http.CaseInsensitiveString("Content-Type"),
          "multipart/form-data; boundary=B",
        ),
      ]),
    )
    assert_eq(response.code, 200)
    assert_eq(client.read_all().text(), "feather:hello")
  })
}

///|
test "Context no_content clears the body" {
  let ctx = @feather.create_context()
  ctx.text(200, "old")
  ctx.no_content()
  assert_eq(ctx.response.status, 204)
  assert_eq(ctx.response.body, "")
  assert_eq(ctx.response.headers.get("Content-Type"), None)
}

///|
test "Feather facade exposes verb and configuration helpers" {
  let feather = create_feather({ host: "127.0.0.1", port: 0, timeout: 0, })
  ignore(
    feather
    .put("/p", fn(ctx) { ctx.text(200, "put") })
    .patch("/p", fn(ctx) { ctx.text(200, "patch") })
    .delete("/p", fn(ctx) { ctx.text(200, "delete") })
    .head("/p", fn(ctx) { ctx.text(200, "head") })
    .options("/p", fn(ctx) { ctx.text(200, "options") })
    .all("/any", fn(ctx) { ctx.text(200, ctx.get_method()) })
    .max_body_size(8)
    .request_timeout(1500),
  )
  assert_eq(
    feather.handle({ method: "PUT", path: "/p", headers: Map([]), body: "" }).body,
    "put",
  )
  assert_eq(
    feather.handle({
      method: "PATCH",
      path: "/p",
      headers: Map([]),
      body: "",
    }).body,
    "patch",
  )
  assert_eq(
    feather.handle({
      method: "DELETE",
      path: "/p",
      headers: Map([]),
      body: "",
    }).body,
    "delete",
  )
  assert_eq(
    feather.handle({
      method: "OPTIONS",
      path: "/p",
      headers: Map([]),
      body: "",
    }).body,
    "options",
  )
  assert_eq(
    feather.handle({
      method: "POST",
      path: "/any",
      headers: Map([]),
      body: "",
    }).body,
    "POST",
  )
  assert_eq(feather.app.max_body_size, 8)
  assert_eq(feather.app.timeout, 1500)
}

///|
test "Feather facade registers fallbacks and websockets" {
  let feather = create_feather({ host: "127.0.0.1", port: 0, timeout: 0, })
  ignore(feather.fallback(fn(ctx) { ctx.text(404, "custom") }))
  ignore(feather.websocket("/ws/live", fn(_ctx, _ws) { () }))
  let response = feather.handle({
    method: "GET",
    path: "/missing",
    headers: Map([]),
    body: "",
  })
  assert_eq(response.status, 404)
  assert_eq(response.body, "custom")
  assert_true(feather.app.has_websocket("/ws/live"))
}

///|
async test "server advertises content length for text responses" {
  let app = @feather.App::new().get("/hello", fn(ctx) {
    ctx.text(200, "héllo")
  })
  with_server(app, client => {
    let response = client.get("/hello")
    assert_eq(response.code, 200)
    assert_eq(
      response.headers.get(@http.CaseInsensitiveString("Content-Length")),
      Some("6"),
    )
    assert_eq(client.read_all().text(), "héllo")
  })
}

///|
async test "static responses advertise content length" {
  let dir = @fs.tmpdir(prefix="feather-static-length")
  @fs.write_file(dir + "/data.txt", "12345")
  let app = @feather.App::new().static_files("/assets", dir)
  with_server(app, client => {
    let response = client.get("/assets/data.txt")
    assert_eq(response.code, 200)
    assert_eq(
      response.headers.get(@http.CaseInsensitiveString("Content-Length")),
      Some("5"),
    )
    assert_eq(client.read_all().text(), "12345")
  })
  @fs.rmdir(dir, recursive=true)
}

///|
test "static_file_for decodes url escaped paths" {
  let app = @feather.App::new().static_files("/assets", "/srv/public")
  assert_eq(
    app.static_file_for("/assets/a%20b.txt"),
    Some("/srv/public/a b.txt"),
  )
  assert_eq(
    app.static_file_for("/assets/f%C3%BCr.txt"),
    Some("/srv/public/für.txt"),
  )
  assert_eq(
    app.static_file_for("/assets/a+b.txt"),
    Some("/srv/public/a+b.txt"),
  )
  assert_eq(app.static_file_for("/assets/%2e%2e/secret"), None)
  assert_eq(app.static_file_for("/assets/..%2fsecret"), None)
  assert_eq(app.static_file_for("/assets/a%00b"), None)
}

///|
async test "explicit routes take precedence over static mounts" {
  let dir = @fs.tmpdir(prefix="feather-static-priority")
  @fs.write_file(dir + "/hello.txt", "from disk")
  let app = @feather.App::new()
    .static_files("/assets", dir)
    .get("/assets/hello.txt", fn(ctx) {
      ctx.text(200, "from route")
    })
  with_server(app, client => {
    let response = client.get("/assets/hello.txt")
    assert_eq(response.code, 200)
    assert_eq(client.read_all().text(), "from route")
  })
  @fs.rmdir(dir, recursive=true)
}

///|
async test "server serves percent encoded static paths" {
  let dir = @fs.tmpdir(prefix="feather-static-encoded")
  @fs.write_file(dir + "/a b.txt", "spaced")
  let app = @feather.App::new().static_files("/assets", dir)
  with_server(app, client => {
    let response = client.get("/assets/a%20b.txt")
    assert_eq(response.code, 200)
    assert_eq(client.read_all().text(), "spaced")
  })
  @fs.rmdir(dir, recursive=true)
}

///|
test "secure headers middleware sets defensive response headers" {
  let app = @feather.App::new()
    .use(@feather.middleware_secure_headers())
    .get("/", fn(ctx) { ctx.text(200, "ok") })
  let ctx = @feather.create_context()
  app.handle(ctx)
  assert_eq(ctx.response.headers.get("X-Content-Type-Options"), Some("nosniff"))
  assert_eq(ctx.response.headers.get("X-Frame-Options"), Some("DENY"))
  assert_eq(ctx.response.headers.get("Referrer-Policy"), Some("no-referrer"))
  let custom = @feather.App::new()
    .use(
      @feather.middleware_secure_headers(
        frame_options="SAMEORIGIN",
        referrer_policy="strict-origin",
      ),
    )
    .get("/", fn(ctx) { ctx.text(200, "ok") })
  let ctx = @feather.create_context()
  custom.handle(ctx)
  assert_eq(ctx.response.headers.get("X-Frame-Options"), Some("SAMEORIGIN"))
  assert_eq(ctx.response.headers.get("Referrer-Policy"), Some("strict-origin"))
}
