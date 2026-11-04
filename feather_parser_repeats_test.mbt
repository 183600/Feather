///|
fn probe_ctx(path : String) -> @feather.Context {
  @feather.Context::new({
    method: "GET",
    path,
    headers: Map([]),
    body: "",
  })
}

///|
test "query flag without equals is present and empty" {
  let ctx = probe_ctx("/?flag&a=1")
  assert_eq(ctx.query("flag"), "")
  assert_true(ctx.has_query("flag"))
}

///|
test "query plus decodes to space while escapes survive" {
  let ctx = probe_ctx("/?q=hello+world&a=1%2B2")
  assert_eq(ctx.query("q"), "hello world")
  assert_eq(ctx.query("a"), "1+2")
}

///|
test "query keeps invalid percent escapes literally" {
  let ctx = probe_ctx("/?a=%ZZ&b=100%")
  assert_eq(ctx.query("a"), "%ZZ")
  assert_eq(ctx.query("b"), "100%")
}

///|
test "repeated query key resolves to the last value" {
  let ctx = probe_ctx("/?a=1&a=2&a=3")
  assert_eq(ctx.query("a"), "3")
  assert_eq(ctx.queries().get("a"), Some("3"))
  assert_eq(ctx.query_values("a"), ["1", "2", "3"])
}

///|
test "repeated urlencoded key resolves to the last value" {
  let parsed = @feather.parse_urlencoded("a=1&a=2&a=3")
  assert_eq(parsed.get("a"), Some("3"))
}

///|
test "cookie values may be quoted" {
  let quoted = @feather.Context::new({
    method: "GET",
    path: "/",
    headers: Map([("Cookie", "a=\"quoted value\"; b=plain")]),
    body: "",
  })
  assert_eq(quoted.cookie("a"), Some("quoted value"))
  assert_eq(quoted.cookie("b"), Some("plain"))
}

///|
test "empty cookie value is present and distinct from absent" {
  let ctx = @feather.Context::new({
    method: "GET",
    path: "/",
    headers: Map([("Cookie", "a=; b=2")]),
    body: "",
  })
  assert_eq(ctx.cookie("a"), Some(""))
  assert_true(ctx.has_cookie("a"))
  assert_eq(ctx.cookie("b"), Some("2"))
}

///|
test "anonymous wildcard matches an empty remainder" {
  // An anonymous `*` route has no parameter name, so the capture is not
  // addressable: `param("")` and `has_param("")` behave as for any absent
  // parameter. The route still answers, which is the point of the pattern.
  let app = @feather.App::new().get("/files/*", fn(ctx) {
    ctx.json(200, {
      "captured": ctx.param(""),
      "present": ctx.has_param("").to_string(),
    })
  })
  let response = app.respond({
    method: "GET",
    path: "/files/",
    headers: Map([]),
    body: "",
  })
  assert_eq(response.status, 200)
  assert_true(response.body.contains("\"captured\":\"\""))
  assert_true(response.body.contains("\"present\":\"false\""))
  // A non-empty remainder routes the same way.
  let named = app.respond({
    method: "GET",
    path: "/files/a/b.txt",
    headers: Map([]),
    body: "",
  })
  assert_eq(named.status, 200)
}

///|
test "accept ranges with q=0 are rejected" {
  let ctx = @feather.Context::new({
    method: "GET",
    path: "/",
    headers: Map([("Accept", "text/html;q=0, application/json")]),
    body: "",
  })
  assert_eq(ctx.accepted_types(), ["application/json"])
  assert_false(ctx.accepts("text/html"))
}

///|
test "accept-language wildcard matches the first offer" {
  let ctx = @feather.Context::new({
    method: "GET",
    path: "/",
    headers: Map([("Accept-Language", "*")]),
    body: "",
  })
  assert_eq(ctx.preferred_language(["en", "fr"]), Some("en"))
}

///|
test "accept-encoding wildcard matches the first offer" {
  let ctx = @feather.Context::new({
    method: "GET",
    path: "/",
    headers: Map([("Accept-Encoding", "*")]),
    body: "",
  })
  assert_eq(ctx.preferred_encoding(["gzip", "br"]), Some("gzip"))
}

///|
test "duplicate header spellings resolve to the first entry" {
  let ctx = @feather.Context::new({
    method: "GET",
    path: "/",
    headers: Map([("X-Test", "first"), ("x-test", "second")]),
    body: "",
  })
  assert_eq(ctx.header("X-Test"), "first")
}
