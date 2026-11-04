///|
test "Context::port reads the port from the Host header" {
  let ctx = @feather.Context::new({
    method: "GET",
    path: "/",
    headers: Map([("Host", "example.com:8080")]),
    body: "",
  })
  assert_eq(ctx.port(), Some(8080))
  assert_eq(ctx.host(), "example.com")
}

///|
test "Context::port reports None when the Host has no port" {
  let ctx = @feather.Context::new({
    method: "GET",
    path: "/",
    headers: Map([("Host", "example.com")]),
    body: "",
  })
  assert_eq(ctx.port(), None)
}

///|
test "Context::port reports None when the Host header is absent" {
  let ctx = @feather.Context::new({
    method: "GET",
    path: "/",
    headers: Map([]),
    body: "",
  })
  assert_eq(ctx.port(), None)
}

///|
test "Context::port parses an IPv6 literal with a port" {
  let ctx = @feather.Context::new({
    method: "GET",
    path: "/",
    headers: Map([("Host", "[::1]:3000")]),
    body: "",
  })
  assert_eq(ctx.port(), Some(3000))
  assert_eq(ctx.host(), "[::1]")
}

///|
test "Context::port reports None for an IPv6 literal without a port" {
  let ctx = @feather.Context::new({
    method: "GET",
    path: "/",
    headers: Map([("Host", "[::1]")]),
    body: "",
  })
  assert_eq(ctx.port(), None)
}

///|
test "Context::port rejects malformed and out-of-range ports" {
  let cases = [
    ("example.com:bad", None),
    ("example.com:", None),
    (":8080", None),
    ("example.com:0", Some(0)),
    ("example.com:65535", Some(65535)),
    ("example.com:65536", None),
    ("example.com:8080:9090", None),
    ("[::1]:bad", None),
    ("[::1]", None),
    ("[::1]:", None),
  ]
  for (authority, expected) in cases {
    let ctx = @feather.Context::new({
      method: "GET",
      path: "/",
      headers: Map([("Host", authority)]),
      body: "",
    })
    assert_eq(ctx.port(), expected, msg=authority)
  }
}

///|
test "Context::port ignores surrounding whitespace in the Host header" {
  let ctx = @feather.Context::new({
    method: "GET",
    path: "/",
    headers: Map([("Host", "  example.com:9090  ")]),
    body: "",
  })
  assert_eq(ctx.port(), Some(9090))
}

///|
test "Context::host and port are consistent" {
  let ctx = @feather.Context::new({
    method: "GET",
    path: "/",
    headers: Map([("Host", "example.com:443")]),
    body: "",
  })
  assert_eq((ctx.host(), ctx.port()), ("example.com", Some(443)))
}
