///|
fn forwarded_strip_request(headers : Map[String, String]) -> @feather.Request {
  { method: "GET", path: "/", headers, body: "", }
}

///|
fn forwarded_headers() -> Map[String, String] {
  Map([
    ("Forwarded", "for=203.0.113.7;proto=https;host=public.example"),
    ("X-Forwarded-For", "203.0.113.7"),
    ("X-Forwarded-Host", "public.example"),
    ("X-Forwarded-Proto", "https"),
    ("X-Forwarded-Port", "8443"),
    ("X-Forwarded-Prefix", "/edge"),
    ("X-Real-IP", "203.0.113.7"),
    ("Host", "internal.example"),
    ("X-Trace", "keep-me"),
  ])
}

///|
test "strip forwarded headers falls back to the direct connection" {
  let app = @feather.App::new()
    .use(@feather.middleware_strip_forwarded_headers())
    .get("/", fn(ctx) {
      ctx.text(200, ctx.protocol() + "|" + ctx.full_url() + "|" + ctx.forwarded_ip())
    })
  let response = app.respond(forwarded_strip_request(forwarded_headers()))
  assert_eq(response.status, 200)
  assert_eq(response.body, "http|http://internal.example/|127.0.0.1")
}

///|
test "without the middleware forwarded headers remain visible" {
  let app = @feather.App::new().get("/", fn(ctx) {
    ctx.text(200, ctx.protocol() + "|" + ctx.full_url() + "|" + ctx.forwarded_ip())
  })
  let response = app.respond(forwarded_strip_request(forwarded_headers()))
  assert_eq(
    response.body,
    "https|https://public.example/|203.0.113.7",
  )
}

///|
test "strip forwarded headers ignores header name casing and keeps others" {
  let app = @feather.App::new()
    .use(@feather.middleware_strip_forwarded_headers())
    .get("/", fn(ctx) {
      ctx.text(
        200,
        ctx.header("X-Forwarded-For") +
        "|" +
        ctx.header("x-real-ip") +
        "|" +
        ctx.header("X-Trace"),
      )
    })
  let response = app.respond(
    forwarded_strip_request(
      Map([
        ("x-forwarded-for", "203.0.113.7"),
        ("X-REAL-IP", "203.0.113.7"),
        ("Host", "internal.example"),
        ("X-Trace", "keep-me"),
      ]),
    ),
  )
  assert_eq(response.body, "||keep-me")
}
