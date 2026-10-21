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
  assert_eq(
    response.headers.get("Vary"),
    Some("Access-Control-Request-Method, Access-Control-Request-Headers"),
  )
}

///|
test "cors preflight discards a prepared file response" {
  let app = @feather.App::new()
    .use(fn(next) {
      fn(ctx) {
        ctx.file(200, "/tmp/feather-preflight-file")
        ctx.set_header("Content-Encoding", "gzip")
        ctx.set_header("Content-Range", "bytes 0-1/2")
        next(ctx)
      }
    })
    .use(@feather.middleware_cors())
    .get("/res", fn(ctx) { ctx.text(200, "g") })
  let ctx = @feather.Context::new({
    method: "OPTIONS",
    path: "/res",
    headers: Map([
      ("Origin", "https://app.test"),
      ("Access-Control-Request-Method", "GET"),
    ]),
    body: "",
  })
  app.handle(ctx)
  assert_eq(ctx.response.status, 204)
  assert_eq(ctx.response.body, "")
  assert_true(ctx.file_response() is None)
  assert_eq(ctx.response.headers.get("Content-Encoding"), None)
  assert_eq(ctx.response.headers.get("Content-Range"), None)
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
async test "dynamic responses drop handler framing headers" {
  let app = @feather.App::new()
    .use(fn(next) {
      fn(ctx) {
        ctx.set_header("Transfer-Encoding", "chunked")
        ctx.set_header("Connection", "keep-alive")
        next(ctx)
      }
    })
    .get("/text", fn(ctx) { ctx.text(200, "hello") })
  with_server(app, client => {
    let response = client.get("/text")
    assert_eq(response.code, 200)
    assert_eq(
      response.headers.get(@http.CaseInsensitiveString("Transfer-Encoding")),
      None,
    )
    assert_eq(
      response.headers.get(@http.CaseInsensitiveString("Connection")),
      None,
    )
    assert_eq(
      response.headers.get(@http.CaseInsensitiveString("Content-Length")),
      Some("5"),
    )
    assert_eq(client.read_all().text(), "hello")
  })
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
async test "streaming responses drop stale representation headers" {
  let stale : @feather.Middleware = fn(next) {
    fn(ctx) raise {
      ctx.set_header("Content-Encoding", "gzip")
      ctx.set_header("Content-Range", "bytes 0-1/2")
      next(ctx)
    }
  }
  let stream_app = @feather.App::new()
    .use(stale)
    .stream("/feed", async fn(_ctx, stream) { stream.write("chunk") })
  with_stream_server(stream_app, client => {
    let response = client.get("/feed")
    assert_eq(response.code, 200)
    assert_eq(
      response.headers.get(@http.CaseInsensitiveString("Content-Encoding")),
      None,
    )
    assert_eq(
      response.headers.get(@http.CaseInsensitiveString("Content-Range")),
      None,
    )
    assert_eq(client.read_all().text(), "chunk")
  })
  let sse_app = @feather.App::new()
    .use(stale)
    .sse("/events", async fn(_ctx, sse) { sse.send("hi") })
  with_sse_server(sse_app, client => {
    let response = client.get("/events")
    assert_eq(response.code, 200)
    assert_eq(
      response.headers.get(@http.CaseInsensitiveString("Content-Encoding")),
      None,
    )
    assert_eq(
      response.headers.get(@http.CaseInsensitiveString("Content-Range")),
      None,
    )
    assert_eq(client.read_all().text(), "data: hi\n\n")
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
async test "static mounts run the middleware chain" {
  let dir = @fs.tmpdir(prefix="feather-static-middleware")
  @fs.write_file(dir + "/secret.txt", "classified")
  let app = @feather.App::new()
    .static_files("/assets", dir)
    .use(@feather.middleware_cors())
    .use(fn(next) {
      fn(ctx) {
        ctx.set_cookie("seen", "yes", path="/")
        if ctx.header("Authorization") != "Bearer key" {
          ctx.text(401, "unauthorized")
          return
        }
        next(ctx)
      }
    })
  with_server(app, client => {
    let denied = client.get("/assets/secret.txt")
    assert_eq(denied.code, 401)
    assert_eq(denied.cookies.length(), 1)
    assert_eq(client.read_all().text(), "unauthorized")
    let allowed = client.get(
      "/assets/secret.txt",
      extra_headers=Map([
        (@http.CaseInsensitiveString("Authorization"), "Bearer key"),
      ]),
    )
    assert_eq(allowed.code, 200)
    assert_eq(allowed.cookies.length(), 1)
    assert_eq(
      allowed.headers.get(
        @http.CaseInsensitiveString("Access-Control-Allow-Origin"),
      ),
      Some("*"),
    )
    assert_eq(client.read_all().text(), "classified")
  })
  @fs.rmdir(dir, recursive=true)
}

///|
async test "static misses keep middleware headers and cookies" {
  let dir = @fs.tmpdir(prefix="feather-static-missing")
  let app = @feather.App::new()
    .static_files("/assets", dir)
    .use(fn(next) {
      fn(ctx) {
        ctx.set_header("X-App", "feather")
        ctx.set_cookie("seen", "yes", path="/")
        next(ctx)
      }
    })
  with_server(app, client => {
    let missing = client.get("/assets/missing.css")
    assert_eq(missing.code, 404)
    assert_eq(
      missing.headers.get(@http.CaseInsensitiveString("X-App")),
      Some("feather"),
    )
    assert_eq(missing.cookies.length(), 1)
    assert_eq(client.read_all().text(), "404 Not Found")
  })
  @fs.rmdir(dir, recursive=true)
}

///|
async test "static errors drop stale representation headers" {
  let dir = @fs.tmpdir(prefix="feather-static-error-encoding")
  let app = @feather.App::new()
    .use(fn(next) {
      fn(ctx) {
        ctx.set_header("Content-Encoding", "gzip")
        ctx.set_header("Content-Range", "bytes 0-1/2")
        next(ctx)
      }
    })
    .static_files("/assets", dir)
  with_server(app, client => {
    let missing = client.get("/assets/missing.css")
    assert_eq(missing.code, 404)
    assert_eq(
      missing.headers.get(@http.CaseInsensitiveString("Content-Encoding")),
      None,
    )
    assert_eq(
      missing.headers.get(@http.CaseInsensitiveString("Content-Range")),
      None,
    )
    assert_eq(client.read_all().text(), "404 Not Found")
  })
  @fs.rmdir(dir, recursive=true)
}

///|
async test "dynamic errors drop stale representation headers" {
  let app = @feather.App::new()
    .use(fn(next) {
      fn(ctx) {
        ctx.set_header("Content-Encoding", "gzip")
        ctx.set_header("Content-Range", "bytes 0-1/2")
        ctx.set_header("Content-Length", "999")
        next(ctx)
      }
    })
    .get("/boom", fn(_ctx) { raise @feather.HttpError(503, "down") })
  with_server(app, client => {
    let failed = client.get("/boom")
    assert_eq(failed.code, 503)
    assert_eq(
      failed.headers.get(@http.CaseInsensitiveString("Content-Encoding")),
      None,
    )
    assert_eq(
      failed.headers.get(@http.CaseInsensitiveString("Content-Range")),
      None,
    )
    assert_eq(client.read_all().text(), "{\"status\":503,\"error\":\"down\"}")
    let missing = client.get("/missing")
    assert_eq(missing.code, 404)
    assert_eq(
      missing.headers.get(@http.CaseInsensitiveString("Content-Encoding")),
      None,
    )
    assert_eq(
      missing.headers.get(@http.CaseInsensitiveString("Content-Range")),
      None,
    )
    assert_eq(client.read_all().text(), "404 Not Found")
  })
}

///|
async test "file responses drop stale representation and framing headers" {
  let dir = @fs.tmpdir(prefix="feather-file-encoding")
  @fs.write_file(dir + "/digits.txt", "0123456789")
  let app = @feather.App::new()
    .use(fn(next) {
      fn(ctx) {
        ctx.set_header("Content-Encoding", "gzip")
        ctx.set_header("Content-Range", "bytes 0-1/2")
        ctx.set_header("Transfer-Encoding", "chunked")
        next(ctx)
      }
    })
    .get("/download", fn(ctx) {
      ctx.set_header("ETag", "\"v1\"")
      ctx.file(200, dir + "/digits.txt")
    })
  with_server(app, client => {
    let full = client.get("/download")
    assert_eq(full.code, 200)
    assert_eq(
      full.headers.get(@http.CaseInsensitiveString("Content-Encoding")),
      None,
    )
    assert_eq(
      full.headers.get(@http.CaseInsensitiveString("Content-Range")),
      None,
    )
    assert_eq(
      full.headers.get(@http.CaseInsensitiveString("Transfer-Encoding")),
      None,
    )
    assert_eq(client.read_all().text(), "0123456789")
    let invalid = client.get(
      "/download",
      extra_headers=Map([(@http.CaseInsensitiveString("Range"), "bytes=99-")]),
    )
    assert_eq(invalid.code, 416)
    assert_eq(
      invalid.headers.get(@http.CaseInsensitiveString("Content-Encoding")),
      None,
    )
    assert_eq(
      invalid.headers.get(@http.CaseInsensitiveString("Content-Range")),
      Some("bytes */10"),
    )
    ignore(client.read_all())
    let cached = client.get(
      "/download",
      extra_headers=Map([
        (@http.CaseInsensitiveString("If-None-Match"), "\"v1\""),
      ]),
    )
    assert_eq(cached.code, 304)
    assert_eq(
      cached.headers.get(@http.CaseInsensitiveString("Content-Encoding")),
      None,
    )
    assert_eq(
      cached.headers.get(@http.CaseInsensitiveString("Content-Range")),
      None,
    )
    assert_eq(
      cached.headers.get(@http.CaseInsensitiveString("Content-Length")),
      None,
    )
    ignore(client.read_all())
  })
  @fs.rmdir(dir, recursive=true)
}

///|
async test "dynamic precondition failures drop stale content range" {
  let app = @feather.App::new()
    .use(fn(next) {
      fn(ctx) {
        ctx.set_header("Content-Range", "bytes 0-1/2")
        next(ctx)
      }
    })
    .etag()
    .get("/item", fn(ctx) {
      ctx.set_header("ETag", "\"v1\"")
      ctx.text(200, "hello")
    })
  with_server(app, client => {
    let response = client.get(
      "/item",
      extra_headers=Map([(@http.CaseInsensitiveString("If-Match"), "\"stale\"")]),
    )
    assert_eq(response.code, 412)
    assert_eq(
      response.headers.get(@http.CaseInsensitiveString("Content-Range")),
      None,
    )
    assert_eq(client.read_all().text(), "412 Precondition Failed")
  })
}

///|
test "body-replacing response helpers drop stale framing headers" {
  let ctx = @feather.create_context()
  ctx.set_header("Content-Length", "999")
  ctx.set_header("Content-Encoding", "gzip")
  ctx.set_header("Content-Range", "bytes 0-1/2")
  ctx.no_content()
  assert_eq(ctx.response.headers.get("Content-Length"), None)
  assert_eq(ctx.response.headers.get("Content-Encoding"), None)
  assert_eq(ctx.response.headers.get("Content-Range"), None)
  ctx.set_header("Content-Length", "999")
  ctx.set_header("Content-Encoding", "gzip")
  ctx.set_header("Content-Range", "bytes 0-1/2")
  ctx.redirect(302, "/next")
  assert_eq(ctx.response.headers.get("Content-Length"), None)
  assert_eq(ctx.response.headers.get("Content-Encoding"), None)
  assert_eq(ctx.response.headers.get("Content-Range"), None)
}

///|
test "middleware denials drop stale representation headers" {
  let stale : @feather.Middleware = fn(next) {
    fn(ctx) raise {
      ctx.set_header("Content-Length", "999")
      ctx.set_header("Content-Encoding", "gzip")
      ctx.set_header("Content-Range", "bytes 0-1/2")
      next(ctx)
    }
  }
  let store = @feather.SessionStore::new()
  let csrf_app = @feather.App::new()
    .use(@feather.middleware_session(store))
    .use(stale)
    .use(@feather.middleware_csrf())
    .post("/act", fn(ctx) { ctx.text(200, "ok") })
  let denied = csrf_app.respond({
    method: "POST",
    path: "/act",
    headers: Map([]),
    body: "",
  })
  assert_eq(denied.status, 403)
  assert_eq(denied.headers.get("Content-Length"), None)
  assert_eq(denied.headers.get("Content-Encoding"), None)
  assert_eq(denied.headers.get("Content-Range"), None)
  assert_eq(denied.body, "403 Forbidden")
  let limiter = @feather.RateLimiter::new(max=1)
  let limited_app = @feather.App::new()
    .use(stale)
    .use(@feather.middleware_rate_limit(limiter))
    .get("/limited", fn(ctx) { ctx.text(200, "ok") })
  let allowed = limited_app.respond({
    method: "GET",
    path: "/limited",
    headers: Map([]),
    body: "",
  })
  assert_eq(allowed.status, 200)
  let throttled = limited_app.respond({
    method: "GET",
    path: "/limited",
    headers: Map([]),
    body: "",
  })
  assert_eq(throttled.status, 429)
  assert_eq(throttled.headers.get("Content-Length"), None)
  assert_eq(throttled.headers.get("Content-Encoding"), None)
  assert_eq(throttled.headers.get("Content-Range"), None)
  assert_eq(throttled.body, "429 Too Many Requests")
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
