///|
fn scratch_bytes(length : Int) -> Bytes {
  let out = FixedArray::make(length, b'\x00')
  for i = 0; i < length; i = i + 1 {
    out[i] = (i * 37 + 11).to_byte()
  }
  out.unsafe_reinterpret_as_bytes()
}

///|
test "scratch base64 round trips every length" {
  for length = 0; length < 40; length = length + 1 {
    let data = scratch_bytes(length)
    let encoded = base64_encode(data)
    assert_eq(base64_decode(encoded), Some(data))
    let encoded_url = base64url_encode(data)
    assert_eq(base64url_decode(encoded_url), Some(data))
  }
}

///|
test "scratch url encode round trips" {
  let samples : Array[String] = [
    "",
    "abc",
    "a b",
    "a+b",
    "a/b?c=d&e",
    "\u{4E2D}\u{6587}",
    "\u{1F600}",
    "~-._",
    "%",
  ]
  for sample in samples {
    let encoded = url_encode(sample)
    assert_eq(url_decode(encoded), sample)
  }
}

///|
test "scratch http date round trips" {
  let samples : Array[Int64] = [
    0L,
    1L,
    59L,
    86399L,
    86400L,
    951782400L,
    1234567890L,
    2147483647L,
    4102444800L,
    253402300799L,
  ]
  for sample in samples {
    let formatted = format_http_date(sample)
    assert_eq(parse_http_date(formatted), Some(sample))
  }
}

///|
fn scratch_range_is(value : ByteRange, start : Int64, end : Int64) -> Bool {
  match value {
    ByteRangeSpec(range_start, range_end) =>
      range_start == start && range_end == end
    _ => false
  }
}

///|
test "scratch parse byte range edges" {
  assert_true(scratch_range_is(parse_byte_range("bytes=0-0", 10L), 0L, 0L))
  assert_true(scratch_range_is(parse_byte_range("bytes=9-9", 10L), 9L, 9L))
  assert_true(scratch_range_is(parse_byte_range("bytes=5-", 10L), 5L, 9L))
  assert_true(scratch_range_is(parse_byte_range("bytes=-5", 10L), 5L, 9L))
  assert_true(scratch_range_is(parse_byte_range("bytes=-100", 10L), 0L, 9L))
  assert_true(parse_byte_range("bytes=10-", 10L) is ByteRangeInvalid)
  assert_true(scratch_range_is(parse_byte_range("bytes=0-100", 10L), 0L, 9L))
  assert_true(parse_byte_range("bytes=5-3", 10L) is ByteRangeFull)
  assert_true(parse_byte_range("bytes=-0", 10L) is ByteRangeInvalid)
  assert_true(parse_byte_range("bytes=0-0", 0L) is ByteRangeInvalid)
}

///|
test "scratch router static beats param" {
  let router = create_router()
  router.add_route("GET", "/a/:x", fn(_ctx) { () })
  router.add_route("GET", "/a/b", fn(_ctx) { () })
  match router.route("GET", "/a/b") {
    RouteFound(route) => assert_eq(route.path, "/a/b")
    _ => fail("expected static match")
  }
  match router.route("GET", "/a/c") {
    RouteFound(route) => assert_eq(route.path, "/a/:x")
    _ => fail("expected param match")
  }
}

///|
test "scratch router wildcard captures" {
  let router = create_router()
  router.add_route("GET", "/files/*path", fn(_ctx) { () })
  match router.route("GET", "/files/a/b/c") {
    RouteFound(route) => {
      assert_eq(route.path, "/files/*path")
      assert_eq(route.params.get("path"), Some("a/b/c"))
      assert_eq(route.wildcard, "a/b/c")
    }
    _ => fail("expected wildcard match")
  }
  match router.route("GET", "/files") {
    RouteFound(route) => assert_eq(route.params.get("path"), Some(""))
    _ => fail("expected empty wildcard match")
  }
}

///|
test "scratch router params before wildcard" {
  let router = create_router()
  router.add_route("GET", "/u/:id/f/*rest", fn(_ctx) { () })
  match router.route("GET", "/u/42/f/x/y") {
    RouteFound(route) => {
      assert_eq(route.params.get("id"), Some("42"))
      assert_eq(route.params.get("rest"), Some("x/y"))
    }
    _ => fail("expected match")
  }
}

///|
test "scratch multipart no trailing crlf" {
  let boundary = "B"
  let body = "--B\r\nContent-Disposition: form-data; name=\"a\"\r\n\r\nvalue\r\n--B--"
  let parts = parse_multipart(body, "multipart/form-data; boundary=B").unwrap()
  assert_eq(parts.length(), 1)
  assert_eq(parts[0].name, "a")
  assert_eq(parts[0].data, "value")
}

///|
test "scratch multipart empty body" {
  let parts = parse_multipart("", "multipart/form-data; boundary=B").unwrap()
  assert_eq(parts.length(), 0)
}
