///|
fn request_with_headers(headers : Map[String, String]) -> @feather.Context {
  @feather.Context::new({
    method: "GET",
    path: "/users/42?tab=posts",
    headers,
    body: "",
  })
}

///|
test "context host strips the port" {
  assert_eq(
    request_with_headers(Map([("Host", "example.com:8080")])).host(),
    "example.com",
  )
  assert_eq(
    request_with_headers(Map([("Host", "example.com")])).host(),
    "example.com",
  )
  assert_eq(
    request_with_headers(Map([("Host", "[2001:db8::1]:8443")])).host(),
    "[2001:db8::1]",
  )
  assert_eq(
    request_with_headers(Map([("Host", "[2001:db8::1]")])).host(),
    "[2001:db8::1]",
  )
  assert_eq(request_with_headers(Map([])).host(), "")
}

///|
test "context protocol honors forwarded proto" {
  assert_eq(
    request_with_headers(Map([])).protocol(),
    "http",
  )
  assert_eq(
    request_with_headers(Map([("X-Forwarded-Proto", "https")])).protocol(),
    "https",
  )
  assert_eq(
    request_with_headers(
      Map([("X-Forwarded-Proto", "https, http")]),
    ).protocol(),
    "https",
  )
  assert_eq(
    request_with_headers(Map([("X-Forwarded-Proto", "  ")])).protocol(),
    "http",
  )
}

///|
test "context is_secure checks the protocol" {
  assert_true(
    request_with_headers(Map([("X-Forwarded-Proto", "HTTPS")])).is_secure(),
  )
  assert_false(request_with_headers(Map([])).is_secure())
}

///|
test "context full_url rebuilds the absolute url" {
  assert_eq(
    request_with_headers(
      Map([("Host", "example.com"), ("X-Forwarded-Proto", "https")]),
    ).full_url(),
    "https://example.com/users/42?tab=posts",
  )
  assert_eq(
    request_with_headers(Map([("Host", "example.com:8080")])).full_url(),
    "http://example.com:8080/users/42?tab=posts",
  )
  assert_eq(
    request_with_headers(Map([])).full_url(),
    "/users/42?tab=posts",
  )
}
