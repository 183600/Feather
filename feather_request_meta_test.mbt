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

///|
test "context protocol honors forwarded params" {
  assert_eq(
    request_with_headers(
      Map([("Forwarded", "for=192.0.2.60;proto=https;by=203.0.113.43")]),
    ).protocol(),
    "https",
  )
  assert_eq(
    request_with_headers(
      Map([("Forwarded", "FOR=192.0.2.60;Proto=\"https\"")]),
    ).protocol(),
    "https",
  )
  assert_eq(
    request_with_headers(
      Map([
        ("Forwarded", "for=192.0.2.60;proto=https"),
        ("X-Forwarded-Proto", "http"),
      ]),
    ).protocol(),
    "https",
  )
  assert_eq(
    request_with_headers(
      Map([("Forwarded", "for=192.0.2.60, for=198.51.100.17;proto=https")]),
    ).protocol(),
    "http",
  )
  assert_eq(
    request_with_headers(
      Map([("Forwarded", "for=192.0.2.60;proto=https, proto=http")]),
    ).protocol(),
    "https",
  )
  assert_eq(
    request_with_headers(
      Map([("Forwarded", "for=192.0.2.60;proto=")]),
    ).protocol(),
    "http",
  )
}

///|
test "context is_secure honors forwarded params" {
  assert_true(
    request_with_headers(
      Map([("Forwarded", "for=192.0.2.60;proto=https")]),
    ).is_secure(),
  )
  assert_true(
    request_with_headers(Map([("Forwarded", "proto=HTTPS")])).is_secure(),
  )
  assert_false(
    request_with_headers(
      Map([("Forwarded", "for=192.0.2.60;proto=http")]),
    ).is_secure(),
  )
}

///|
test "context forwarded_authority honors proxy host headers" {
  assert_eq(
    request_with_headers(
      Map([
        ("Forwarded", "for=192.0.2.60;host=\"example.com:8443\";proto=https"),
        ("Host", "internal:8080"),
      ]),
    ).forwarded_authority(),
    "example.com:8443",
  )
  assert_eq(
    request_with_headers(
      Map([
        ("X-Forwarded-Host", "public.example:9443, internal"),
        ("Host", "internal:8080"),
      ]),
    ).forwarded_authority(),
    "public.example:9443",
  )
  assert_eq(
    request_with_headers(
      Map([("Host", "example.com:8080")]),
    ).forwarded_authority(),
    "example.com:8080",
  )
  assert_eq(
    request_with_headers(Map([])).forwarded_authority(),
    "",
  )
}

///|
test "context full_url honors forwarded host" {
  assert_eq(
    request_with_headers(
      Map([
        ("Forwarded", "for=192.0.2.60;host=\"example.com:8443\";proto=https"),
        ("Host", "internal:8080"),
      ]),
    ).full_url(),
    "https://example.com:8443/users/42?tab=posts",
  )
  assert_eq(
    request_with_headers(
      Map([
        ("X-Forwarded-Host", "public.example"),
        ("X-Forwarded-Proto", "https"),
      ]),
    ).full_url(),
    "https://public.example/users/42?tab=posts",
  )
}

///|
test "context forwarded_ip parses the Forwarded header" {
  assert_eq(
    request_with_headers(
      Map([("Forwarded", "for=192.0.2.60:8080;proto=http")]),
    ).forwarded_ip(),
    "192.0.2.60",
  )
  assert_eq(
    request_with_headers(
      Map([("Forwarded", "for=\"[2001:db8::1]:4711\"")]),
    ).forwarded_ip(),
    "[2001:db8::1]",
  )
  assert_eq(
    request_with_headers(
      Map([("Forwarded", "for=\"192\\.0\\.2\\.60\"")]),
    ).forwarded_ip(),
    "192.0.2.60",
  )
  assert_eq(
    request_with_headers(
      Map([
        ("Forwarded", "for=192.0.2.60, for=198.51.100.17"),
        ("X-Forwarded-For", "203.0.113.9"),
      ]),
    ).forwarded_ip(),
    "192.0.2.60",
  )
  assert_eq(
    request_with_headers(
      Map([
        ("Forwarded", "for=unknown"),
        ("X-Forwarded-For", "203.0.113.9, 10.0.0.1"),
      ]),
    ).forwarded_ip(),
    "203.0.113.9",
  )
  assert_eq(
    request_with_headers(Map([("Forwarded", "for=_hidden")])).forwarded_ip(),
    "127.0.0.1",
  )
}
