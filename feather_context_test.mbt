///|
test "Context defer_cleanup runs in reverse order after handler" {
  let order : Array[String] = []
  let app = @feather.App::new().get("/cleanup", fn(ctx) {
    ctx.defer_cleanup(fn() {
      order.push("first")
    })
    ctx.defer_cleanup(fn() {
      order.push("second")
    })
    order.push("handler")
    ctx.text(200, "ok")
  })
  let response = app.respond({
    method: "GET",
    path: "/cleanup",
    headers: Map([]),
    body: "",
  })
  assert_eq(response.status, 200)
  assert_eq(order.join(","), "handler,second,first")
}

///|
test "Context defer_cleanup runs when the handler fails" {
  let cleaned : Array[String] = []
  let app = @feather.App::new().get("/boom", fn(ctx) raise {
    ctx.defer_cleanup(fn() {
      cleaned.push("done")
    })
    ctx.fail(503, "unavailable")
  })
  let response = app.respond({
    method: "GET",
    path: "/boom",
    headers: Map([]),
    body: "",
  })
  assert_eq(response.status, 503)
  assert_eq(cleaned.join(","), "done")
}

///|
test "cleanups registered during cleanup still run" {
  let order : Array[String] = []
  let app = @feather.App::new().get("/nested", fn(ctx) {
    ctx.defer_cleanup(fn() {
      order.push("outer")
      ctx.defer_cleanup(fn() {
        order.push("inner")
      })
    })
    ctx.text(200, "ok")
  })
  let response = app.respond({
    method: "GET",
    path: "/nested",
    headers: Map([]),
    body: "",
  })
  assert_eq(response.status, 200)
  assert_eq(order.join(","), "outer,inner")
}

///|
async test "server runs deferred cleanups for every request" {
  let cleaned : Array[String] = []
  let app = @feather.App::new().get("/record", fn(ctx) {
    ctx.defer_cleanup(fn() {
      cleaned.push(ctx.request.path)
    })
    ctx.text(200, "ok")
  })
  with_server(app, client => {
    ignore(client.get("/record"))
    ignore(client.read_all())
    ignore(client.get("/record"))
    ignore(client.read_all())
  })
  assert_eq(cleaned.join(","), "/record,/record")
}

///|
test "Context params collects every captured route parameter" {
  let router = @feather.create_router()
  router.add_route("GET", "/users/:id/posts/:pid", fn(ctx) {
    ctx.text(200, "ok")
  })
  let ctx = @feather.Context::new({
    method: "GET",
    path: "/users/7/posts/9",
    headers: Map([]),
    body: "",
  })
  router.dispatch(ctx)
  let params = ctx.params()
  assert_eq(params.get("id"), Some("7"))
  assert_eq(params.get("pid"), Some("9"))
  assert_eq(params.length(), 2)
  let empty = @feather.create_context()
  assert_eq(empty.params().length(), 0)
}

///|
test "file download names escape quotes and encode unicode" {
  let quoted = @feather.create_context()
  quoted.file(200, "/srv/a.txt", download_name="a\"b.txt")
  assert_eq(
    quoted.response.headers.get("Content-Disposition"),
    Some("attachment; filename=\"a\\\"b.txt\""),
  )
  let unicode = @feather.create_context()
  unicode.file(200, "/srv/b.txt", download_name="报告.txt")
  assert_eq(
    unicode.response.headers.get("Content-Disposition"),
    Some(
      "attachment; filename=\"__.txt\"; filename*=UTF-8''%E6%8A%A5%E5%91%8A.txt",
    ),
  )
  let injected = @feather.create_context()
  injected.file(200, "/srv/c.txt", download_name="a\r\nX-Evil: 1")
  assert_eq(
    injected.response.headers.get("Content-Disposition"),
    Some("attachment; filename=\"aX-Evil: 1\""),
  )
}

///|
test "cookies strip control characters from values and attributes" {
  let ctx = @feather.create_context()
  ctx.set_cookie("sid", "a\r\nX-Evil: 1", path="/a\r\nb", same_site="Lax\n")
  assert_eq(
    ctx.response.headers.get("Set-Cookie"),
    Some("sid=aX-Evil: 1; Path=/ab; SameSite=Lax"),
  )
  let added = @feather.create_context()
  added.add_cookie("tok", "v\u{0}al", domain="ex\r\nample.com")
  assert_eq(
    added.response.headers.get("Set-Cookie"),
    None,
  )
  assert_eq(added.response.cookies.length(), 1)
}

///|
test "cookies strip separators from names and attribute values" {
  let ctx = @feather.create_context()
  ctx.set_cookie("a;b c=d", "v", path="/p;q")
  assert_eq(ctx.response.headers.get("Set-Cookie"), Some("abcd=v; Path=/pq"))
}

///|
test "cookie values keep base64 padding" {
  let ctx = @feather.create_context()
  ctx.set_cookie("token", "YWJjZA==", path="/")
  assert_eq(
    ctx.response.headers.get("Set-Cookie"),
    Some("token=YWJjZA==; Path=/"),
  )
}

///|
test "cookies drop invalid same-site values and sanitize domains" {
  let ctx = @feather.create_context()
  ctx.set_cookie("sid", "v", domain="a;b=c d", same_site="lax y")
  assert_eq(ctx.response.headers.get("Set-Cookie"), Some("sid=v; Domain=abcd"))
  let strict = @feather.create_context()
  strict.set_cookie("sid", "v", same_site=" STRICT ")
  assert_eq(
    strict.response.headers.get("Set-Cookie"),
    Some("sid=v; SameSite=Strict"),
  )
}

///|
test "url_encode encodes supplementary pairs and replaces lone surrogates" {
  let pair = String::from_array([
    Char::from_int(0xD83D),
    Char::from_int(0xDE00),
  ])
  assert_eq(@feather.url_encode(pair), "%F0%9F%98%80")
  let lone = String::from_array([Char::from_int(0xD800)])
  assert_eq(@feather.url_encode(lone), "%EF%BF%BD")
  let low = String::from_array([Char::from_int(0xDC00)])
  assert_eq(@feather.url_encode(low), "%EF%BF%BD")
}

///|
test "cors echoes origin when credentials are enabled" {
  let app = @feather.App::new()
    .use(@feather.middleware_cors(allow_credentials=true))
    .get("/me", fn(ctx) { ctx.text(200, "ok") })
  let ctx = @feather.Context::new({
    method: "GET",
    path: "/me",
    headers: Map([("Origin", "https://app.example")]),
    body: "",
  })
  app.handle(ctx)
  assert_eq(
    ctx.response.headers.get("Access-Control-Allow-Origin"),
    Some("https://app.example"),
  )
  assert_eq(
    ctx.response.headers.get("Access-Control-Allow-Credentials"),
    Some("true"),
  )
  assert_eq(ctx.response.headers.get("Vary"), Some("Origin"))
  let anonymous = @feather.create_context()
  app.handle(anonymous)
  assert_eq(
    anonymous.response.headers.get("Access-Control-Allow-Origin"),
    Some("*"),
  )
}

///|
test "cors appends to an existing Vary header" {
  let app = @feather.App::new()
    .use(fn(next) {
      fn(ctx) raise {
        ctx.response.headers.set("Vary", "Accept-Encoding")
        next(ctx)
      }
    })
    .use(@feather.middleware_cors(allow_origin="https://example.com"))
    .get("/v", fn(ctx) { ctx.text(200, "ok") })
  let ctx = @feather.create_context()
  app.handle(ctx)
  assert_eq(ctx.response.headers.get("Vary"), Some("Accept-Encoding, Origin"))
}

///|
test "listen_address renders ipv6 hosts with brackets" {
  let ipv6 = @feather.create_feather({
    host: "::1",
    port: 9000,
    timeout: 0,
  })
  assert_eq(ipv6.listen_address(), "[::1]:9000")
  let bracketed = @feather.create_feather({
    host: "[::1]",
    port: 9000,
    timeout: 0,
  })
  assert_eq(bracketed.listen_address(), "[::1]:9000")
  let plain = @feather.create_feather({
    host: "127.0.0.1",
    port: 8080,
    timeout: 0,
  })
  assert_eq(plain.listen_address(), "127.0.0.1:8080")
}

///|
test "Context typed param and query accessors" {
  let router = @feather.create_router()
  router.add_route("GET", "/items/:id/:flag", fn(ctx) {
    ctx.text(200, "ok")
  })
  let ctx = @feather.Context::new({
    method: "GET",
    path: "/items/42/true?id=7&flag=0&bad=abc&big=99999999999",
    headers: Map([]),
    body: "",
  })
  router.dispatch(ctx)
  assert_eq(ctx.param_int("id"), Some(42))
  assert_eq(ctx.param_bool("flag"), Some(true))
  assert_eq(ctx.param_int("flag"), None)
  assert_eq(ctx.param_bool("id"), None)
  assert_eq(ctx.param_int("missing"), None)
  assert_eq(ctx.query_int("id"), Some(7))
  assert_eq(ctx.query_bool("flag"), Some(false))
  assert_eq(ctx.query_int("bad"), None)
  assert_eq(ctx.query_bool("bad"), None)
  assert_eq(ctx.query_int("big"), None)
  assert_eq(ctx.query_int("missing"), None)
}

///|
test "Context typed accessors accept signed values" {
  let router = @feather.create_router()
  router.add_route("GET", "/n/:value", fn(ctx) {
    ctx.text(200, "ok")
  })
  let negative = @feather.Context::new({
    method: "GET",
    path: "/n/-12",
    headers: Map([]),
    body: "",
  })
  router.dispatch(negative)
  assert_eq(negative.param_int("value"), Some(-12))
  let plus = @feather.create_context()
  plus.state.set(@feather.PARAM_PREFIX + "value", "+8")
  assert_eq(plus.param_int("value"), Some(8))
  plus.state.set(@feather.PARAM_PREFIX + "value", "-")
  assert_eq(plus.param_int("value"), None)
}

///|
test "Context json_state round trips structured values" {
  let ctx = @feather.create_context()
  assert_eq(ctx.get_json("user"), None)
  ctx.set_json("user", Json::object({
    "name": Json::string("feather"),
    "admin": Json::boolean(true),
  }))
  match ctx.get_json("user") {
    Some(Json::Object(fields)) =>
      match fields.get("name") {
        Some(Json::String(name)) => assert_eq(name, "feather")
        _ => fail("expected name field")
      }
    _ => fail("expected object")
  }
  assert_eq(ctx.get_json("missing"), None)
}

///|
test "Context file records a pending file response" {
  let ctx = @feather.create_context()
  ctx.file(200, "/srv/report.txt", download_name="report.txt")
  assert_eq(ctx.response.status, 200)
  assert_eq(
    ctx.response.headers.get("Content-Type"),
    Some("text/plain; charset=utf-8"),
  )
  assert_eq(
    ctx.response.headers.get("Content-Disposition"),
    Some("attachment; filename=\"report.txt\""),
  )
  assert_eq(ctx.response.body, "")
  match ctx.file_response() {
    Some(file) => {
      assert_eq(file.path, "/srv/report.txt")
      assert_eq(file.content_type, "text/plain; charset=utf-8")
    }
    None => fail("expected pending file")
  }
  ctx.text(200, "text wins")
  assert_eq(ctx.file_response() is None, true)
}

///|
test "parse_http_date accepts legacy rfc850 and asctime formats" {
  assert_eq(
    @feather.parse_http_date("Sunday, 06-Nov-94 08:49:37 GMT"),
    Some(784111777L),
  )
  assert_eq(
    @feather.parse_http_date("Sunday, 06-Nov-2024 08:49:37 GMT"),
    Some(1730882977L),
  )
  assert_eq(
    @feather.parse_http_date("Sun Nov  6 08:49:37 1994"),
    Some(784111777L),
  )
  assert_eq(@feather.parse_http_date("Sunday, 06-Nov-94 08:49 GMT"), None)
  assert_eq(@feather.parse_http_date("Sun Xxx  6 08:49:37 1994"), None)
}

///|
test "status_text knows common status codes" {
  assert_eq(@feather.status_text(418), "I'm a Teapot")
  assert_eq(@feather.status_text(451), "Unavailable For Legal Reasons")
  assert_eq(@feather.status_text(511), "Network Authentication Required")
  assert_eq(@feather.status_text(999), "Unknown")
}

///|
async test "server streams files queued by handlers" {
  let dir = @fs.tmpdir(prefix="feather-file-response")
  @fs.write_file(dir + "/report.txt", "file-body")
  let app = @feather.App::new().get("/report", fn(ctx) {
    ctx.file(200, dir + "/report.txt", download_name="report.txt")
  })
  with_server(app, client => {
    let response = client.get("/report")
    assert_eq(response.code, 200)
    assert_eq(
      response.headers.get(@http.CaseInsensitiveString("Content-Type")),
      Some("text/plain; charset=utf-8"),
    )
    assert_eq(
      response.headers.get(@http.CaseInsensitiveString("Content-Length")),
      Some("9"),
    )
    assert_eq(
      response.headers.get(@http.CaseInsensitiveString("Content-Disposition")),
      Some("attachment; filename=\"report.txt\""),
    )
    assert_eq(client.read_all().text(), "file-body")
  })
  @fs.rmdir(dir, recursive=true)
}

///|
async test "server returns 404 for missing queued files" {
  let app = @feather.App::new().get("/missing", fn(ctx) {
    ctx.file(200, "/definitely/not/here.txt")
  })
  with_server(app, client => {
    let response = client.get("/missing")
    assert_eq(response.code, 404)
    assert_eq(client.read_all().text(), "404 Not Found")
  })
}

///|
async test "missing queued files keep middleware headers and cookies" {
  let app = @feather.App::new()
    .use(fn(next) {
      fn(ctx) raise {
        ctx.set_header("X-Feather-Test", "kept")
        ctx.set_cookie("sid", "abc", http_only=true)
        next(ctx)
      }
    })
    .get("/missing", fn(ctx) { ctx.file(200, "/definitely/not/here.txt") })
  with_server(app, client => {
    let response = client.get("/missing")
    assert_eq(response.code, 404)
    assert_eq(
      response.headers.get(@http.CaseInsensitiveString("X-Feather-Test")),
      Some("kept"),
    )
    assert_eq(response.cookies.length(), 1)
    assert_eq(response.cookies[0].name, "sid")
    assert_eq(response.cookies[0].value, "abc")
    assert_eq(response.cookies[0].http_only, true)
    assert_eq(client.read_all().text(), "404 Not Found")
  })
}

///|
async test "server answers head requests for queued files" {
  let dir = @fs.tmpdir(prefix="feather-file-head")
  @fs.write_file(dir + "/data.bin", "0123456789")
  let app = @feather.App::new().get("/data", fn(ctx) {
    ctx.file(200, dir + "/data.bin", content_type="application/octet-stream")
  })
  with_server(app, client => {
    client.request(@http.RequestMethod::Head, "/data")
    let response = client.end_request()
    assert_eq(response.code, 200)
    assert_eq(
      response.headers.get(@http.CaseInsensitiveString("Content-Length")),
      Some("10"),
    )
    assert_eq(client.read_all().text(), "")
  })
  @fs.rmdir(dir, recursive=true)
}

///|
test "cors replaces case-variant response headers" {
  let app = @feather.App::new()
    .use(fn(next) {
      fn(ctx) raise {
        ctx.set_header("access-control-allow-origin", "https://old.example")
        ctx.set_header("access-control-allow-methods", "OLD")
        next(ctx)
      }
    })
    .use(@feather.middleware_cors(allow_methods="GET"))
    .get("/", fn(ctx) { ctx.text(200, "ok") })
  let ctx = @feather.create_context()
  app.handle(ctx)
  let mut origins = 0
  for key, _ in ctx.response.headers {
    if key.view().equal_ignore_ascii_case("access-control-allow-origin".view()) {
      origins = origins + 1
    }
  }
  assert_eq(origins, 1)
  assert_eq(ctx.response.headers.get("Access-Control-Allow-Origin"), Some("*"))
}
