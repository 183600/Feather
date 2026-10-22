///|
fn host_test_headers(host : String?) -> Map[String, String] {
  let headers : Map[String, String] = Map([])
  match host {
    Some(value) => headers.set("Host", value)
    None => ()
  }
  headers
}

///|
fn host_test_context(headers : Map[String, String]) -> @feather.Context {
  @feather.Context::new({
    method: "GET",
    path: "/",
    headers,
    body: "",
  })
}

///|
fn host_test_app(hosts : Array[String], allow_missing~ : Bool = false) -> (
  @feather.App,
  Ref[Int32],
) {
  let calls = Ref(0)
  let app = @feather.App::new()
    .use(
      @feather.middleware_allowed_hosts(hosts, allow_missing~),
    )
    .get("/", fn(ctx) raise {
      calls.val = calls.val + 1
      ctx.text(200, "ok")
    })
  (app, calls)
}

///|
test "allowed hosts matches exact names ignoring case ports and trailing dot" {
  let (app, calls) = host_test_app(
    ["example.com", "[::1]", "api.test"],
  )
  for host in [
    "example.com",
    "Example.COM:8080",
    "example.com.",
    "EXAMPLE.com.",
    "[::1]",
    "[::1]:8443",
    "api.test:443",
  ] {
    let ctx = host_test_context(host_test_headers(Some(host)))
    app.handle(ctx)
    assert_eq(ctx.response.status, 200)
    assert_eq(ctx.response.body, "ok")
  }
  assert_eq(calls.val, 7)
}

///|
test "allowed hosts wildcard accepts subdomains but not the apex" {
  let (app, calls) = host_test_app(["*.example.com", "api.test"])
  for host in [
    "a.example.com",
    "a.b.example.com",
    "A.EXAMPLE.COM:8443",
    "api.test",
  ] {
    let ctx = host_test_context(host_test_headers(Some(host)))
    app.handle(ctx)
    assert_eq(ctx.response.status, 200)
  }
  for host in [
    "example.com",
    "example.com:80",
    "notexample.com",
    "example.com.evil",
    "api.test.evil",
    "a.example.com.evil",
  ] {
    let ctx = host_test_context(host_test_headers(Some(host)))
    app.handle(ctx)
    assert_eq(ctx.response.status, 400)
    assert_eq(ctx.response.body, "400 Bad Request")
  }
  assert_eq(calls.val, 4)
}

///|
test "allowed hosts rejects malformed and missing Host values" {
  let (app, calls) = host_test_app(["example.com", "[::1]"])
  for host in [
    "",
    " ",
    "example.com:bad",
    "example.com:",
    "example.com:65536",
    "example.com:80x",
    "exa mple.com",
    "example.com\r\nX-Injected: yes",
    "example.com,evil.com",
    "user@example.com",
    "::1",
    "[::1",
    "[::1]junk",
    ".example.com",
  ] {
    let ctx = host_test_context(host_test_headers(Some(host)))
    app.handle(ctx)
    assert_eq(ctx.response.status, 400)
    assert_eq(ctx.response.body, "400 Bad Request")
  }
  let missing = host_test_context(host_test_headers(None))
  app.handle(missing)
  assert_eq(missing.response.status, 400)
  assert_eq(calls.val, 0)
}

///|
test "allowed hosts can permit a missing Host header" {
  let (app, calls) = host_test_app(["example.com"], allow_missing=true)
  let missing = host_test_context(host_test_headers(None))
  app.handle(missing)
  assert_eq(missing.response.status, 200)
  assert_eq(missing.response.body, "ok")
  assert_eq(calls.val, 1)
}

///|
test "allowed hosts wildcard entry accepts any well formed authority" {
  let (app, _) = host_test_app(["*"])
  for host in ["example.com", "anything.example:8080", "[::2]"] {
    let ctx = host_test_context(host_test_headers(Some(host)))
    app.handle(ctx)
    assert_eq(ctx.response.status, 200)
  }
  let malformed = host_test_context(host_test_headers(Some("bad host")))
  app.handle(malformed)
  assert_eq(malformed.response.status, 400)
  let missing = host_test_context(host_test_headers(None))
  app.handle(missing)
  assert_eq(missing.response.status, 400)
}

///|
test "allowed hosts validates bracketed IP literals structurally" {
  let (app, _) = host_test_app(["*"])
  for host in [
    "[::]",
    "[::1]",
    "[2001:db8::1]",
    "[1:2:3:4:5:6:7:8]",
    "[::ffff:192.0.2.1]",
    "[fe80::1%25eth0]",
    "[v1.foo]",
    "[v1.foo~bar]",
  ] {
    let ctx = host_test_context(host_test_headers(Some(host)))
    app.handle(ctx)
    assert_eq(ctx.response.status, 200)
  }
  for host in [
    "[]",
    "[:::]",
    "[::::]",
    "[gggg::1]",
    "[1:2:3:4:5:6:7]",
    "[1:2:3:4:5:6:7:8:9]",
    "[1::2::3]",
    "[1:2:3:4:5:6:7:8::]",
    "[::ffff:192.0.2.999]",
    "[192.0.2.1]",
    "[::1%]",
  ] {
    let ctx = host_test_context(host_test_headers(Some(host)))
    app.handle(ctx)
    assert_eq(ctx.response.status, 400)
  }
}

///|
test "allowed hosts ignores malformed configured patterns" {
  let (app, _) = host_test_app(["", "*.", "bad host", "example.com:bad"])
  let ctx = host_test_context(host_test_headers(Some("example.com")))
  app.handle(ctx)
  assert_eq(ctx.response.status, 400)
}

///|
test "allowed hosts cannot be bypassed with a forwarded host header" {
  let (app, calls) = host_test_app(["allowed.example"])
  let headers = Map([
    ("Host", "evil.example"),
    ("X-Forwarded-Host", "allowed.example"),
  ])
  let ctx = host_test_context(headers)
  app.handle(ctx)
  assert_eq(ctx.response.status, 400)
  assert_eq(ctx.response.body, "400 Bad Request")
  assert_eq(calls.val, 0)
}

///|
test "allowed hosts rejects empty interior host labels" {
  let (app, calls) = host_test_app(["*", "*.example.com"])
  for host in [
    "example..com",
    "example..",
    "a..b",
    "..example.com",
    "a.example..com",
  ] {
    let ctx = host_test_context(host_test_headers(Some(host)))
    app.handle(ctx)
    assert_eq(ctx.response.status, 400, msg=host)
    assert_eq(ctx.response.body, "400 Bad Request")
  }
  for host in ["example.com.", "a.example.com.", "[::1]"] {
    let ctx = host_test_context(host_test_headers(Some(host)))
    app.handle(ctx)
    assert_eq(ctx.response.status, 200, msg=host)
  }
  assert_eq(calls.val, 3)
}
