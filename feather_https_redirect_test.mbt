///|
/// Tests for `middleware_https_redirect`: an HTTP request that is not secure is
/// redirected to the same host and path over HTTPS, while a secure request is
/// passed through unchanged.
fn redirect_headers(host : String?) -> Map[String, String] {
  let headers : Map[String, String] = Map([])
  match host {
    Some(value) => headers.set("Host", value)
    None => ()
  }
  headers
}

///|
fn redirect_context(headers : Map[String, String]) -> @feather.Context {
  @feather.Context::new({
    method: "GET",
    path: "/",
    headers,
    body: "",
  })
}

///|
fn redirect_app(
  middlewares : Array[@feather.Middleware],
) -> (@feather.App, Ref[Int32]) {
  let calls = Ref(0)
  let mut app = @feather.App::new()
  for mw in middlewares {
    app = app.use(mw)
  }
  (
    app.get("/", fn(ctx) raise {
      calls.val = calls.val + 1
      ctx.text(200, "ok")
    }),
    calls,
  )
}

///|
test "https redirect sends a permanent 308 to the same host and path" {
  let (app, calls) = redirect_app([
    @feather.middleware_https_redirect(),
  ])
  let ctx = redirect_context(redirect_headers(Some("example.com")))
  app.handle(ctx)
  assert_eq(ctx.response.status, 308)
  assert_eq(
    ctx.response.headers.get("Location"),
    Some("https://example.com/"),
  )
  assert_eq(calls.val, 0)
}

///|
test "https redirect can use a temporary 307 instead" {
  let (app, calls) = redirect_app([
    @feather.middleware_https_redirect(permanent=false),
  ])
  let ctx = redirect_context(redirect_headers(Some("example.com")))
  app.handle(ctx)
  assert_eq(ctx.response.status, 307)
  assert_eq(
    ctx.response.headers.get("Location"),
    Some("https://example.com/"),
  )
  assert_eq(calls.val, 0)
}

///|
test "https redirect honors a fixed host instead of the request Host header" {
  let (app, _) = redirect_app([
    @feather.middleware_https_redirect(host="internal.example.com"),
  ])
  let ctx = redirect_context(redirect_headers(Some("example.com")))
  app.handle(ctx)
  assert_eq(ctx.response.status, 308)
  assert_eq(
    ctx.response.headers.get("Location"),
    Some("https://internal.example.com/"),
  )
}

///|
test "https redirect preserves the request path in the Location URL" {
  let (app, _) = redirect_app([
    @feather.middleware_https_redirect(),
  ])
  let ctx = redirect_context(redirect_headers(Some("example.com")))
  // Hand-built contexts keep the path as given; the middleware prefixes "/"
  // when it is missing.
  let ctx2 = @feather.Context::new({
    method: "GET",
    path: "/users/42",
    headers: redirect_headers(Some("example.com")),
    body: "",
  })
  app.handle(ctx2)
  assert_eq(ctx2.response.status, 308)
  assert_eq(
    ctx2.response.headers.get("Location"),
    Some("https://example.com/users/42"),
  )
}

///|
test "https redirect passes a secure request through to the handler" {
  let (app, calls) = redirect_app([
    @feather.middleware_https_redirect(),
  ])
  let ctx = @feather.Context::new({
    method: "GET",
    path: "/",
    headers: Map([
      ("Host", "example.com"),
      ("X-Forwarded-Proto", "https"),
    ]),
    body: "",
  })
  app.handle(ctx)
  assert_eq(ctx.response.status, 200)
  assert_eq(ctx.response.body, "ok")
  assert_eq(calls.val, 1)
}

///|
test "https redirect passes a request through when the Host header is missing" {
  let (app, calls) = redirect_app([
    @feather.middleware_https_redirect(),
  ])
  let ctx = redirect_context(redirect_headers(None))
  app.handle(ctx)
  assert_eq(ctx.response.status, 200)
  assert_eq(ctx.response.body, "ok")
  assert_eq(calls.val, 1)
}

///|
test "https redirect passes a request through when the host is not valid" {
  let (app, calls) = redirect_app([
    @feather.middleware_https_redirect(),
  ])
  let ctx = redirect_context(redirect_headers(Some("not a host")))
  app.handle(ctx)
  assert_eq(ctx.response.status, 200)
  assert_eq(ctx.response.body, "ok")
  assert_eq(calls.val, 1)
}

///|
test "https redirect passes the asterisk-form target through unchanged" {
  let (app, calls) = redirect_app([
    @feather.middleware_https_redirect(),
  ])
  let ctx = @feather.Context::new({
    method: "OPTIONS",
    path: "*",
    headers: redirect_headers(Some("example.com")),
    body: "",
  })
  app.handle(ctx)
  assert_eq(ctx.response.status, 204)
  assert_eq(calls.val, 0)
}

///|
test "https redirect strips control characters from a forged host and passes through" {
  let (app, calls) = redirect_app([
    @feather.middleware_https_redirect(),
  ])
  let headers = redirect_headers(Some("example.com\r\nInjected: yes"))
  let ctx = redirect_context(headers)
  app.handle(ctx)
  assert_eq(ctx.response.status, 200)
  assert_eq(ctx.response.body, "ok")
  assert_eq(calls.val, 1)
}

///|
test "https redirect with a fixed host ignores a hostile request Host header" {
  let (app, _) = redirect_app([
    @feather.middleware_https_redirect(host="api.example.com"),
  ])
  let headers = redirect_headers(Some("evil.example.com"))
  let ctx = redirect_context(headers)
  app.handle(ctx)
  assert_eq(ctx.response.status, 308)
  assert_eq(
    ctx.response.headers.get("Location"),
    Some("https://api.example.com/"),
  )
}

///|
