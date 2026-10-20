///|
test "forwarded helpers tolerate a quoted value with a dangling escape" {
  let dangling = @feather.Context::new({
    method: "GET",
    path: "/x",
    headers: Map([("Forwarded", "host=\"exam\\")]),
    body: "",
  })
  // The escape consumes no following byte, so the unterminated value stays
  // malformed but parsing must not read past the header.
  assert_true(dangling.forwarded_authority().has_prefix("exam"))
  let no_param = @feather.Context::new({
    method: "GET",
    path: "/x",
    headers: Map([("Forwarded", "\"x\\"), ("Host", "fallback.example")]),
    body: "",
  })
  assert_eq(no_param.forwarded_authority(), "fallback.example")
  assert_eq(no_param.protocol(), "http")
  let escaped = @feather.Context::new({
    method: "GET",
    path: "/x",
    headers: Map([("Forwarded", "host=\"a\\\"b.example\"")]),
    body: "",
  })
  assert_eq(escaped.forwarded_authority(), "a\"b.example")
}
