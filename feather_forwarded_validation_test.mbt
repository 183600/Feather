///|
fn forwarded_validation_ctx(
  headers : Map[String, String],
) -> @feather.Context {
  @feather.Context::new({
    method: "GET",
    path: "/",
    headers,
    body: "",
  })
}

///|
test "forwarded_ip rejects malformed bracketed node identifiers" {
  for value in [
    "[::1]junk",
    "[::1]:bad",
    "[::1]:65536",
    "[::1]:",
    "[not-an-ip]",
  ] {
    let ctx = forwarded_validation_ctx(
      Map([
        ("Forwarded", "for=\"" + value + "\""),
        ("X-Forwarded-For", "203.0.113.9"),
      ]),
    )
    assert_eq(ctx.forwarded_ip(), "203.0.113.9", msg=value)
  }
}

///|
test "forwarded_ip still normalizes valid bracketed node identifiers" {
  let ctx = forwarded_validation_ctx(
    Map([("Forwarded", "for=\"[2001:db8::1]:4711\"")]),
  )
  assert_eq(ctx.forwarded_ip(), "[2001:db8::1]")
  let literal = forwarded_validation_ctx(
    Map([("Forwarded", "for=\"[v1.foo]\"")]),
  )
  assert_eq(literal.forwarded_ip(), "[v1.foo]")
}

///|
test "trusted proxy treats a malformed forwarded node as addressless" {
  let app = @feather.App::new()
    .trust_proxy(1)
    .use(fn(next) {
      fn(ctx) {
        ctx.state.set("remote_addr", "10.0.0.9")
        next(ctx)
      }
    })
    .get("/ip", fn(ctx) { ctx.text(200, ctx.ip()) })
  let response = app.respond({
    method: "GET",
    path: "/ip",
    headers: Map([
      ("Forwarded", "for=\"[::1]junk\""),
      ("X-Forwarded-For", "203.0.113.9"),
    ]),
    body: "",
  })
  assert_eq(response.body, "10.0.0.9")
}

///|
test "forwarded_ip rejects an invalid port on a single-colon node" {
  let ctx = forwarded_validation_ctx(
    Map([
      ("Forwarded", "for=192.0.2.60:not-a-port"),
      ("X-Forwarded-For", "203.0.113.9"),
    ]),
  )
  assert_eq(ctx.forwarded_ip(), "203.0.113.9")
  let valid = forwarded_validation_ctx(
    Map([("Forwarded", "for=192.0.2.60:8080")]),
  )
  assert_eq(valid.forwarded_ip(), "192.0.2.60")
}

///|
test "forwarded_ip rejects malformed bare IPv6 node identifiers" {
  for value in ["::::", "1:2:3", "1::2::3", "::ffff:192.0.2.999"] {
    let ctx = forwarded_validation_ctx(
      Map([
        ("Forwarded", "for=" + value),
        ("X-Forwarded-For", "203.0.113.9"),
      ]),
    )
    assert_eq(ctx.forwarded_ip(), "203.0.113.9", msg=value)
  }
  for value in ["::1", "2001:db8::1", "::ffff:192.0.2.1"] {
    let ctx = forwarded_validation_ctx(Map([("Forwarded", "for=" + value)]))
    assert_eq(ctx.forwarded_ip(), value, msg=value)
  }
}
