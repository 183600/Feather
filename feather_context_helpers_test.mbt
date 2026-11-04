///|
fn context_with_headers(headers : Map[String, String]) -> @feather.Context {
  @feather.Context::new({
    method: "GET",
    path: "/",
    headers,
    body: "",
  })
}

///|
test "type_is matches the request media type" {
  let ctx = context_with_headers(
    Map([("Content-Type", "application/json")]),
  )
  assert_true(ctx.type_is("application/json"))
  assert_false(ctx.type_is("text/html"))
}

///|
test "type_is ignores parameters and case" {
  let ctx = context_with_headers(
    Map([("Content-Type", "Application/JSON; charset=UTF-8")]),
  )
  assert_true(ctx.type_is("application/json"))
  assert_true(ctx.type_is("APPLICATION/JSON"))
}

///|
test "type_is matches wildcard patterns" {
  let ctx = context_with_headers(
    Map([("Content-Type", "application/problem+json")]),
  )
  assert_true(ctx.type_is("application/*"))
  assert_true(ctx.type_is("*/*"))
  assert_true(ctx.type_is("application/*+json"))
  assert_false(ctx.type_is("text/*"))
}

///|
test "type_is never matches a request without a content type" {
  let ctx = context_with_headers(Map([]))
  assert_false(ctx.type_is("application/json"))
  assert_false(ctx.type_is("*/*"))
}

///|
test "subdomains reports the labels in front of the root domain" {
  let ctx = context_with_headers(Map([("Host", "a.b.example.com")]))
  assert_eq(ctx.subdomains(), ["a", "b"])
}

///|
test "subdomains is empty for a host without a subdomain" {
  let ctx = context_with_headers(Map([("Host", "example.com")]))
  assert_eq(ctx.subdomains(), [])
}

///|
test "subdomains is empty for a host without a dot" {
  let ctx = context_with_headers(Map([("Host", "localhost")]))
  assert_eq(ctx.subdomains(), [])
}

///|
test "subdomains is empty for an address literal" {
  let ipv4 = context_with_headers(Map([("Host", "192.0.2.1")]))
  assert_eq(ipv4.subdomains(), [])
  let ipv6 = context_with_headers(Map([("Host", "[::1]")]))
  assert_eq(ipv6.subdomains(), [])
}

///|
test "subdomains is empty without a host header" {
  let ctx = context_with_headers(Map([]))
  assert_eq(ctx.subdomains(), [])
}

///|
test "subdomains ignores a trailing root dot" {
  let ctx = context_with_headers(Map([("Host", "a.example.com.")]))
  assert_eq(ctx.subdomains(), ["a"])
}

///|
test "subdomains honours the root domain count" {
  let ctx = context_with_headers(Map([("Host", "a.b.example.com")]))
  assert_eq(ctx.subdomains(root_domains=1), ["a", "b", "example"])
  assert_eq(ctx.subdomains(root_domains=3), ["a"])
  assert_eq(ctx.subdomains(root_domains=4), [])
}

///|
test "subdomains ignores the port of the host" {
  let ctx = context_with_headers(Map([("Host", "a.example.com:8080")]))
  assert_eq(ctx.subdomains(), ["a"])
}

///|
test "accepted types reports every accepted media range" {
  let ctx = context_with_headers(
    Map([("Accept", "text/html,application/json")]),
  )
  assert_eq(ctx.accepted_types(), ["text/html", "application/json"])
}

///|
test "accepted types orders the ranges by quality" {
  let ctx = context_with_headers(
    Map([("Accept", "text/html;q=0.5, application/json;q=0.9")]),
  )
  assert_eq(ctx.accepted_types(), ["application/json", "text/html"])
}

///|
test "accepted types drops the ranges the client rejects" {
  let ctx = context_with_headers(
    Map([("Accept", "text/html;q=0, application/json")]),
  )
  assert_eq(ctx.accepted_types(), ["application/json"])
}

///|
test "accepted types keeps the wildcards of the header" {
  let ctx = context_with_headers(Map([("Accept", "text/*")]))
  assert_eq(ctx.accepted_types(), ["text/*"])
}

///|
test "accepted types lowercases the media types" {
  let ctx = context_with_headers(Map([("Accept", "TEXT/HTML")]))
  assert_eq(ctx.accepted_types(), ["text/html"])
}

///|
test "accepted types reports everything for a request without an accept header" {
  let ctx = context_with_headers(Map([]))
  assert_eq(ctx.accepted_types(), ["*/*"])
}

///|
test "accepted types keeps the header order for equal qualities" {
  let ctx = context_with_headers(
    Map([("Accept", "text/plain, text/html")]),
  )
  assert_eq(ctx.accepted_types(), ["text/plain", "text/html"])
}
