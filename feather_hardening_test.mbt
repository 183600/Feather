///|
test "parse_http_date rejects impossible calendar days" {
  assert_eq(@feather.parse_http_date("Sun, 31 Feb 2025 00:00:00 GMT"), None)
  assert_eq(@feather.parse_http_date("Sat, 29 Feb 2025 00:00:00 GMT"), None)
  assert_true(
    @feather.parse_http_date("Thu, 29 Feb 2024 00:00:00 GMT") is Some(_),
  )
  assert_eq(@feather.parse_http_date("Sun, 31 Apr 2025 00:00:00 GMT"), None)
  assert_eq(
    @feather.parse_http_date("Sun, 31 Mar 2025 00:00:00 GMT"),
    Some(1743379200L),
  )
  assert_eq(@feather.parse_http_date("Monday, 31-Feb-25 00:00:00 GMT"), None)
  assert_true(@feather.parse_http_date("Sun Nov  6 08:49:37 1994") is Some(_))
  assert_eq(@feather.parse_http_date("Sun Nov 31 08:49:37 1994"), None)
  assert_true(
    @feather.parse_http_date("Friday, 31-Feb-25 00:00:00 GMT") is None,
  )
}

///|
test "url_for stops at the wildcard and normalizes captured segments" {
  let router = @feather.create_router()
  router.add_named_route("files", "GET", "/files/*rest/download", fn(_ctx) {
    ()
  })
  assert_eq(
    router.url_for("files", params=Map([("rest", "a/b")])),
    Some("/files/a/b"),
  )
  assert_eq(
    router.url_for("files", params=Map([("rest", "a//b/")])),
    Some("/files/a/b"),
  )
  match router.route("GET", "/files/a/b") {
    @feather.RouteFound(route) =>
      assert_eq(route.params.get("rest"), Some("a/b"))
    _ => fail("expected the wildcard route to match")
  }
}

///|
test "clear cookie can target a domain scoped cookie" {
  let ctx = @feather.create_context()
  ctx.clear_cookie("sid", path="/", domain="example.com")
  let cookie = ctx.response.cookies[0]
  assert_eq(cookie.name, "sid")
  assert_eq(cookie.path, Some("/"))
  assert_eq(cookie.domain, Some("example.com"))
  assert_eq(cookie.max_age, Some(0L))
}

///|
test "csrf middleware treats trace as a safe method" {
  let store = @feather.SessionStore::new()
  let handler = @feather.apply_middleware(
    [@feather.middleware_session(store), @feather.middleware_csrf()],
    fn(ctx) { ctx.text(200, "ok") },
  )
  let ctx = @feather.Context::new({
    method: "TRACE",
    path: "/",
    headers: Map([]),
    body: "",
  })
  handler(ctx)
  assert_eq(ctx.response.status, 200)
  assert_eq(ctx.response.body, "ok")
}

///|
test "cors middleware runs explicit options handlers and decorates them" {
  let app = @feather.App::new()
    .use(@feather.middleware_cors(allow_methods="GET, OPTIONS"))
    .options("/res", fn(ctx) { ctx.text(200, "custom") })
    .get("/res", fn(ctx) { ctx.text(200, "g") })
  let response = app.respond({
    method: "OPTIONS",
    path: "/res",
    headers: Map([]),
    body: "",
  })
  assert_eq(response.status, 200)
  assert_eq(response.body, "custom")
  assert_eq(
    response.headers.get("Access-Control-Allow-Methods"),
    Some("GET, OPTIONS"),
  )
}

///|
test "cors preflight short-circuits without running the handler" {
  let app = @feather.App::new()
    .use(@feather.middleware_cors(allow_methods="GET, POST", max_age=60))
    .options("/res", fn(ctx) { ctx.text(200, "custom") })
  let response = app.respond({
    method: "OPTIONS",
    path: "/res",
    headers: Map([
      ("Origin", "https://app.test"),
      ("Access-Control-Request-Method", "POST"),
    ]),
    body: "",
  })
  assert_eq(response.status, 204)
  assert_eq(response.body, "")
  assert_eq(
    response.headers.get("Access-Control-Allow-Methods"),
    Some("GET, POST"),
  )
  assert_eq(response.headers.get("Access-Control-Max-Age"), Some("60"))
}

///|
async test "head and get agree on framing for missing static files" {
  let dir = @fs.tmpdir(prefix="feather-static-head-parity")
  let app = @feather.App::new().static_files("/assets", dir)
  with_server(app, client => {
    let get_response = client.get("/assets/missing.txt")
    assert_eq(get_response.code, 404)
    let get_length = get_response.headers.get(
      @http.CaseInsensitiveString("Content-Length"),
    )
    assert_true(get_length is Some(_))
    assert_eq(client.read_all().text(), "404 Not Found")
    client.request(@http.RequestMethod::Head, "/assets/missing.txt")
    let head_response = client.end_request()
    assert_eq(head_response.code, 404)
    assert_eq(
      head_response.headers.get(@http.CaseInsensitiveString("Content-Length")),
      get_length,
    )
    assert_eq(client.read_all().text(), "")
  })
  @fs.rmdir(dir, recursive=true)
}

///|
async test "server strips bodies from reset content responses" {
  let app = @feather.App::new().get("/reset", fn(ctx) {
    ctx.text(205, "payload")
  })
  with_server(app, client => {
    let response = client.get("/reset")
    assert_eq(response.code, 205)
    let length = response.headers.get(
      @http.CaseInsensitiveString("Content-Length"),
    )
    assert_true(length is None || length == Some("0"))
    assert_eq(client.read_all().text(), "")
  })
}

///|
async test "server ignores ranges for non-get file responses" {
  let dir = @fs.tmpdir(prefix="feather-file-post-range")
  @fs.write_file(dir + "/digits.txt", "0123456789")
  let app = @feather.App::new().post("/download", fn(ctx) {
    ctx.file(200, dir + "/digits.txt")
  })
  with_server(app, client => {
    let response = client.post(
      "/download",
      "",
      extra_headers=Map([(@http.CaseInsensitiveString("Range"), "bytes=0-1")]),
    )
    assert_eq(response.code, 200)
    assert_eq(
      response.headers.get(@http.CaseInsensitiveString("Content-Range")),
      None,
    )
    assert_eq(client.read_all().text(), "0123456789")
  })
  @fs.rmdir(dir, recursive=true)
}

///|
async test "if-range tolerates surrounding whitespace" {
  let dir = @fs.tmpdir(prefix="feather-file-if-range-ows")
  @fs.write_file(dir + "/digits.txt", "0123456789")
  let app = @feather.App::new().get("/download", fn(ctx) {
    ctx.set_header("ETag", "\"v1\"")
    ctx.file(200, dir + "/digits.txt")
  })
  with_server(app, client => {
    ignore(client.get("/download"))
    ignore(client.read_all())
    let ranged = client.get(
      "/download",
      extra_headers=Map([
        (@http.CaseInsensitiveString("Range"), "bytes=0-1"),
        (@http.CaseInsensitiveString("If-Range"), "\"v1\" "),
      ]),
    )
    assert_eq(ranged.code, 206)
    assert_eq(client.read_all().text(), "01")
  })
  @fs.rmdir(dir, recursive=true)
}

///|
async test "stream failure before the first write yields 500" {
  let app = @feather.App::new().stream("/feed", async fn(_ctx, _stream) {
    @async.sleep(1)
    raise Failure("boom")
  })
  with_stream_server(app, client => {
    let response = client.get("/feed")
    assert_eq(response.code, 500)
    assert_eq(client.read_all().text(), "500 Internal Server Error")
  })
}

///|
async test "sse routes are not shadowed by static files" {
  let dir = @fs.tmpdir(prefix="feather-sse-static")
  @fs.write_file(dir + "/feed", "not an event stream")
  let app = @feather.App::new()
    .static_files("/", dir)
    .sse("/feed", async fn(_ctx, sse) { sse.send("hi") })
  with_sse_server(app, client => {
    let response = client.get("/feed")
    assert_eq(response.code, 200)
    assert_eq(
      response.headers.get(@http.CaseInsensitiveString("Content-Type")),
      Some("text/event-stream; charset=utf-8"),
    )
    assert_eq(client.read_all().text(), "data: hi\n\n")
  })
  @fs.rmdir(dir, recursive=true)
}

///|
async test "sse fields strip injected line breaks" {
  let app = @feather.App::new().sse("/events", async fn(_ctx, sse) {
    sse.send("real", event="tick\ndata: forged", id="1\n\ndata: hijack")
  })
  with_sse_server(app, client => {
    let response = client.get("/events")
    assert_eq(response.code, 200)
    assert_eq(
      client.read_all().text(),
      "event: tickdata: forged\nid: 1data: hijack\ndata: real\n\n",
    )
  })
}

///|
async test "etag answers unsafe conditional requests with 412" {
  let app = @feather.App::new()
    .etag()
    .get("/api", fn(ctx) {
      ctx.set_header("ETag", "\"v1\"")
      ctx.text(200, "hello")
    })
    .post("/api", fn(ctx) {
      ctx.set_header("ETag", "\"v1\"")
      ctx.text(200, "hello")
    })
  with_server(app, client => {
    let cached = client.get(
      "/api",
      extra_headers=Map([(if_none_match_key, "\"v1\"")]),
    )
    assert_eq(cached.code, 304)
    assert_eq(client.read_all().text(), "")
    let conflict = client.post(
      "/api",
      "",
      extra_headers=Map([(if_none_match_key, "\"v1\"")]),
    )
    assert_eq(conflict.code, 412)
    assert_eq(client.read_all().text(), "412 Precondition Failed")
  })
}

///|
async test "etag evaluates if-none-match before ranges" {
  let dir = @fs.tmpdir(prefix="feather-etag-range")
  @fs.write_file(dir + "/digits.txt", "0123456789")
  let app = @feather.App::new()
    .etag()
    .get("/download", fn(ctx) {
      ctx.set_header("ETag", "\"v1\"")
      ctx.file(200, dir + "/digits.txt")
    })
  with_server(app, client => {
    let cached = client.get(
      "/download",
      extra_headers=Map([
        (@http.CaseInsensitiveString("Range"), "bytes=4-6"),
        (if_none_match_key, "\"v1\""),
      ]),
    )
    assert_eq(cached.code, 304)
    assert_eq(client.read_all().text(), "")
    let ranged = client.get(
      "/download",
      extra_headers=Map([(@http.CaseInsensitiveString("Range"), "bytes=4-6")]),
    )
    assert_eq(ranged.code, 206)
    assert_eq(
      ranged.headers.get(@http.CaseInsensitiveString("Content-Range")),
      Some("bytes 4-6/10"),
    )
    assert_eq(client.read_all().text(), "456")
  })
  @fs.rmdir(dir, recursive=true)
}

///|
async test "compression leaves ranged responses alone" {
  let dir = @fs.tmpdir(prefix="feather-compress-range")
  @fs.write_file(dir + "/digits.txt", "0123456789")
  let app = @feather.App::new()
    .compress(min_size=0)
    .get("/download", fn(ctx) { ctx.file(200, dir + "/digits.txt") })
  with_server(app, client => {
    let ranged = client.get(
      "/download",
      extra_headers=Map([
        (@http.CaseInsensitiveString("Range"), "bytes=4-6"),
        (accept_encoding_key, "gzip"),
      ]),
    )
    assert_eq(ranged.code, 206)
    assert_eq(ranged.headers.get(content_encoding_key), None)
    assert_eq(
      ranged.headers.get(@http.CaseInsensitiveString("Content-Range")),
      Some("bytes 4-6/10"),
    )
    assert_eq(client.read_all().text(), "456")
  })
  @fs.rmdir(dir, recursive=true)
}

///|
async test "compression weakens handler supplied etags" {
  let payload = "feather compression payload ".repeat(128)
  let app = @feather.App::new()
    .compress(min_size=16)
    .get("/big", fn(ctx) {
      ctx.set_header("ETag", "\"handler\"")
      ctx.text(200, payload)
    })
  with_server(app, client => {
    let response = client.get(
      "/big",
      extra_headers=Map([(accept_encoding_key, "gzip")]),
    )
    assert_eq(response.code, 200)
    assert_eq(response.headers.get(content_encoding_key), Some("gzip"))
    assert_eq(
      response.headers.get(@http.CaseInsensitiveString("ETag")),
      Some("W/\"handler\""),
    )
    let decoded = decode_gzip_body(client.read_all().binary())
    assert_eq(@utf8.decode_lossy(decoded), payload)
  })
}
