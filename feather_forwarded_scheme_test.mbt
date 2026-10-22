///|
test "forwarded protocol headers cannot inject a non-http scheme" {
  for headers in [
    Map([("Host", "example.com"), ("X-Forwarded-Proto", "javascript")]),
    Map([("Host", "example.com"), ("Forwarded", "proto=file")]),
    Map([("Host", "example.com"), ("Forwarded", "proto=\"ftp\"")]),
  ] {
    let ctx = @feather.Context::new({
      method: "GET",
      path: "/x",
      headers,
      body: "",
    })
    assert_eq(ctx.protocol(), "http")
    assert_eq(ctx.full_url(), "http://example.com/x")
  }
  let secure = @feather.Context::new({
    method: "GET",
    path: "/x",
    headers: Map([("Host", "example.com"), ("X-Forwarded-Proto", "HTTPS")]),
    body: "",
  })
  assert_true(secure.is_secure())
  assert_eq(secure.full_url(), "HTTPS://example.com/x")
}
