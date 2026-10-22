///|
fn forwarded_authority_ctx(
  headers : Map[String, String],
  path~ : String = "/x",
) -> @feather.Context {
  @feather.Context::new({ method: "GET", path, headers, body: "" })
}

///|
test "forwarded authority ignores malformed forwarded host values" {
  for headers in [
    Map([("Forwarded", "host=\"evil.example/path\""), ("Host", "good.example:8080")]),
    Map([("Forwarded", "host=\"user@evil.example\""), ("Host", "good.example:8080")]),
    Map([("Forwarded", "host=\"[::1]junk\""), ("Host", "good.example:8080")]),
    Map([("Forwarded", "host=\"evil.example\r\nX-Injected: yes\""), ("Host", "good.example:8080")]),
    Map([("X-Forwarded-Host", "evil.example/path"), ("Host", "good.example:8080")]),
    Map([("X-Forwarded-Host", "user@evil.example"), ("Host", "good.example:8080")]),
    Map([("X-Forwarded-Host", "[::1]junk"), ("Host", "good.example:8080")]),
  ] {
    let ctx = forwarded_authority_ctx(headers)
    assert_eq(ctx.forwarded_authority(), "good.example:8080")
    assert_eq(ctx.full_url(), "http://good.example:8080/x")
  }
  let valid = forwarded_authority_ctx(
    Map([
      ("Forwarded", "host=\"public.example:8443\";proto=https"),
      ("Host", "internal:8080"),
    ]),
  )
  assert_eq(valid.forwarded_authority(), "public.example:8443")
  assert_eq(valid.full_url(), "https://public.example:8443/x")
}

///|
test "full_url rejects a malformed host authority" {
  let ctx = forwarded_authority_ctx(Map([("Host", "bad host")]))
  assert_eq(ctx.forwarded_authority(), "")
  assert_eq(ctx.full_url(), "/x")
}

///|
test "forwarded protocol ignores malformed scheme values" {
  let ctx = forwarded_authority_ctx(
    Map([
      ("Forwarded", "proto=\"https://evil.example\""),
      ("X-Forwarded-Proto", "https"),
      ("Host", "good.example"),
    ]),
  )
  assert_eq(ctx.protocol(), "https")
  assert_eq(ctx.full_url(), "https://good.example/x")
  let injected = forwarded_authority_ctx(
    Map([
      ("X-Forwarded-Proto", "https\r\nX-Injected: yes"),
      ("Host", "good.example"),
    ]),
  )
  assert_eq(injected.protocol(), "http")
  let malformed = forwarded_authority_ctx(Map([("Host", "good.example")]))
  assert_eq(malformed.protocol(), "http")
}

///|
test "full_url makes a relative path absolute and leaves asterisk-form alone" {
  let ctx = forwarded_authority_ctx(
    Map([("Host", "example.com")]),
    path="items?tab=1",
  )
  assert_eq(ctx.full_url(), "http://example.com/items?tab=1")
  let star = forwarded_authority_ctx(
    Map([("Host", "example.com")]),
    path="*",
  )
  assert_eq(star.full_url(), "*")
}
