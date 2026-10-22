///|
fn cors_request(method : String, headers : Map[String, String]) -> @feather.Context {
  @feather.Context::new({
    method,
    path: "/me",
    headers,
    body: "",
  })
}

///|
test "cors predicate echoes allowed origins and rejects others" {
  let app = @feather.App::new()
    .use(
      @feather.middleware_cors_with(
        allow_origin=fn(origin) { origin == "https://good.example" },
        allow_credentials=true,
        max_age=600,
      ),
    )
    .get("/me", fn(ctx) { ctx.text(200, "ok") })

  let allowed = cors_request("GET", Map([("Origin", "https://good.example")]))
  app.handle(allowed)
  assert_eq(
    allowed.response.headers.get("Access-Control-Allow-Origin"),
    Some("https://good.example"),
  )
  assert_eq(
    allowed.response.headers.get("Access-Control-Allow-Credentials"),
    Some("true"),
  )
  assert_eq(allowed.response.headers.get("Vary"), Some("Origin"))
  assert_eq(allowed.response.body, "ok")

  let rejected = cors_request("GET", Map([("Origin", "https://evil.example")]))
  app.handle(rejected)
  assert_eq(rejected.response.headers.get("Access-Control-Allow-Origin"), None)
  assert_eq(rejected.response.headers.get("Access-Control-Allow-Credentials"), Some("true"))
  assert_eq(rejected.response.headers.get("Vary"), None)
  assert_eq(rejected.response.body, "ok")

  let anonymous = cors_request("GET", Map([]))
  app.handle(anonymous)
  assert_eq(anonymous.response.headers.get("Access-Control-Allow-Origin"), None)
  assert_eq(anonymous.response.headers.get("Vary"), None)
}

///|
test "cors predicate answers preflight only for allowed origins" {
  let app = @feather.App::new()
    .use(
      @feather.middleware_cors_with(
        allow_origin=fn(origin) { origin == "https://good.example" },
        allow_methods="GET, POST",
        allow_headers="X-Token",
        max_age=600,
      ),
    )
    .get("/me", fn(ctx) { ctx.text(200, "handler") })

  let allowed = cors_request(
    "OPTIONS",
    Map([
      ("Origin", "https://good.example"),
      ("Access-Control-Request-Method", "POST"),
    ]),
  )
  app.handle(allowed)
  assert_eq(allowed.response.status, 204)
  assert_eq(allowed.response.body, "")
  assert_eq(
    allowed.response.headers.get("Access-Control-Allow-Origin"),
    Some("https://good.example"),
  )
  assert_eq(
    allowed.response.headers.get("Access-Control-Allow-Methods"),
    Some("GET, POST"),
  )
  assert_eq(
    allowed.response.headers.get("Access-Control-Allow-Headers"),
    Some("X-Token"),
  )
  assert_eq(allowed.response.headers.get("Access-Control-Max-Age"), Some("600"))

  let rejected = cors_request(
    "OPTIONS",
    Map([
      ("Origin", "https://evil.example"),
      ("Access-Control-Request-Method", "POST"),
    ]),
  )
  app.handle(rejected)
  assert_eq(rejected.response.status, 204)
  assert_eq(rejected.response.body, "")
  assert_eq(rejected.response.headers.get("Access-Control-Allow-Origin"), None)
  assert_eq(rejected.response.headers.get("Access-Control-Allow-Methods"), None)
  assert_eq(rejected.response.headers.get("Access-Control-Allow-Headers"), None)
  assert_eq(rejected.response.headers.get("Access-Control-Max-Age"), None)
}

///|
test "cors credentialed preflight omits every CORS header when rejected" {
  let app = @feather.App::new()
    .use(
      @feather.middleware_cors_with(
        allow_origin=fn(origin) { origin == "https://good.example" },
        allow_credentials=true,
      ),
    )
    .get("/me", fn(ctx) { ctx.text(200, "handler") })
  let allowed = cors_request(
    "OPTIONS",
    Map([
      ("Origin", "https://good.example"),
      ("Access-Control-Request-Method", "POST"),
    ]),
  )
  app.handle(allowed)
  assert_eq(allowed.response.status, 204)
  assert_eq(
    allowed.response.headers.get("Access-Control-Allow-Credentials"),
    Some("true"),
  )
  let rejected = cors_request(
    "OPTIONS",
    Map([
      ("Origin", "https://evil.example"),
      ("Access-Control-Request-Method", "POST"),
    ]),
  )
  app.handle(rejected)
  assert_eq(rejected.response.status, 204)
  assert_eq(rejected.response.headers.get("Access-Control-Allow-Origin"), None)
  assert_eq(
    rejected.response.headers.get("Access-Control-Allow-Credentials"),
    None,
  )
}

///|
test "cors allowlist matches origins exactly" {
  let app = @feather.App::new()
    .use(
      @feather.middleware_cors_allowlist(
        ["https://one.example", "https://two.example"],
        allow_credentials=true,
        expose_headers="X-Trace",
      ),
    )
    .get("/me", fn(ctx) { ctx.text(200, "ok") })

  let second = cors_request("GET", Map([("Origin", "https://two.example")]))
  app.handle(second)
  assert_eq(
    second.response.headers.get("Access-Control-Allow-Origin"),
    Some("https://two.example"),
  )
  assert_eq(
    second.response.headers.get("Access-Control-Expose-Headers"),
    Some("X-Trace"),
  )
  assert_eq(second.response.headers.get("Vary"), Some("Origin"))

  let lookalike = cors_request("GET", Map([("Origin", "https://two.example.evil")]))
  app.handle(lookalike)
  assert_eq(lookalike.response.headers.get("Access-Control-Allow-Origin"), None)
  assert_eq(lookalike.response.headers.get("Access-Control-Expose-Headers"), None)

  let empty = @feather.App::new()
    .use(@feather.middleware_cors_allowlist([]))
    .get("/me", fn(ctx) { ctx.text(200, "ok") })
  let denied = cors_request("GET", Map([("Origin", "https://one.example")]))
  empty.handle(denied)
  assert_eq(denied.response.headers.get("Access-Control-Allow-Origin"), None)
}

///|
test "cors credentials echo requested preflight headers" {
  let app = @feather.App::new()
    .use(@feather.middleware_cors(allow_credentials=true))
    .get("/me", fn(ctx) { ctx.text(200, "ok") })

  let reflected = cors_request(
    "OPTIONS",
    Map([
      ("Origin", "https://example.com"),
      ("Access-Control-Request-Method", "GET"),
      ("Access-Control-Request-Headers", "X-Token, X-Trace"),
    ]),
  )
  app.handle(reflected)
  assert_eq(reflected.response.status, 204)
  assert_eq(
    reflected.response.headers.get("Access-Control-Allow-Headers"),
    Some("X-Token, X-Trace"),
  )

  let absent = cors_request(
    "OPTIONS",
    Map([
      ("Origin", "https://example.com"),
      ("Access-Control-Request-Method", "GET"),
    ]),
  )
  app.handle(absent)
  assert_eq(
    absent.response.headers.get("Access-Control-Allow-Headers"),
    Some("*"),
  )

  let anonymous = @feather.App::new()
    .use(@feather.middleware_cors())
    .get("/me", fn(ctx) { ctx.text(200, "ok") })
  let wildcard = cors_request(
    "OPTIONS",
    Map([
      ("Origin", "https://example.com"),
      ("Access-Control-Request-Method", "GET"),
      ("Access-Control-Request-Headers", "X-Token"),
    ]),
  )
  anonymous.handle(wildcard)
  assert_eq(
    wildcard.response.headers.get("Access-Control-Allow-Headers"),
    Some("*"),
  )
}
