///|
fn roundtrip_bytes(seed : Int32, length : Int32) -> Bytes {
  let out = FixedArray::make(length, b'\x00')
  let mut state = seed
  for i = 0; i < length; i = i + 1 {
    state = state * 1664525 + 1013904223
    out[i] = ((state >> 16) & 255).to_byte()
  }
  out.unsafe_reinterpret_as_bytes()
}

///|
fn bytes_equal(left : Bytes, right : Bytes) -> Bool {
  if left.length() != right.length() {
    return false
  }
  for i = 0; i < left.length(); i = i + 1 {
    if left[i] != right[i] {
      return false
    }
  }
  true
}

///|
test "base64 round-trips arbitrary bytes" {
  for length = 0; length <= 130; length = length + 1 {
    let data = roundtrip_bytes(length * 17 + 3, length)
    let encoded = @feather.base64_encode(data)
    let decoded = @feather.base64_decode(encoded).unwrap()
    assert_true(
      bytes_equal(data, decoded),
      msg="base64 round-trip failed at length \{length}",
    )
  }
}

///|
test "url encoding round-trips text" {
  let samples = [
    "", "plain", "with space", "a/b?c=d&e#f", "caf\u{e9}", "\u{4f60}\u{597d}",
    "100%", "+plus+", "quote\"and'apostrophe", "line\nbreak", "tab\there",
    "\u{1f600}\u{1f680}",
  ]
  for sample in samples {
    let encoded = @feather.url_encode(sample)
    assert_eq(@feather.url_decode(encoded), sample)
  }
}

///|
test "urlencoded round-trips repeated keys and escapes" {
  let encoded = "a=1&a=2&b=hello+world&c=%E4%BD%A0%E5%A5%BD&empty=&bare"
  let parsed = @feather.parse_urlencoded(encoded)
  assert_eq(parsed.get("a"), Some("2"))
  assert_eq(parsed.get("b"), Some("hello world"))
  assert_eq(parsed.get("c"), Some("\u{4f60}\u{597d}"))
  assert_eq(parsed.get("empty"), Some(""))
  assert_eq(parsed.get("bare"), Some(""))
}

///|
test "http dates round-trip across the supported range" {
  let samples : Array[Int64] = [
    0L, 1L, 59L, 951782400L, 1_600_000_000L, 2_147_483_647L, 4_102_444_800L,
  ]
  for seconds in samples {
    let formatted = @feather.format_http_date(seconds)
    assert_eq(
      @feather.parse_http_date(formatted),
      Some(seconds),
      msg="HTTP date did not round-trip: \{formatted}",
    )
  }
}

///|
test "byte ranges round-trip their selected bounds" {
  let total = 1000L
  match @feather.parse_byte_range("bytes=0-0", total) {
    ByteRangeSpec(start, end) => {
      assert_eq(start, 0L)
      assert_eq(end, 0L)
    }
    _ => fail("expected a satisfiable single range")
  }
  match @feather.parse_byte_range("bytes=999-", total) {
    ByteRangeSpec(start, end) => {
      assert_eq(start, 999L)
      assert_eq(end, 999L)
    }
    _ => fail("expected a suffix range")
  }
  match @feather.parse_byte_range("bytes=-1", total) {
    ByteRangeSpec(start, end) => {
      assert_eq(start, 999L)
      assert_eq(end, 999L)
    }
    _ => fail("expected a suffix range")
  }
}

///|
test "multipart boundary parsing handles quoted parameters" {
  assert_eq(
    @feather.multipart_boundary("multipart/form-data; boundary=\"abc-123\""),
    Some("abc-123"),
  )
  assert_eq(
    @feather.multipart_boundary(
      "multipart/form-data; charset=utf-8; boundary=abc-123",
    ),
    Some("abc-123"),
  )
  assert_eq(@feather.multipart_boundary("application/json"), None)
}

///|
test "multipart parser round-trips several ASCII parts" {
  let boundary = "feather-boundary"
  let body = "--feather-boundary\r\n" +
    "Content-Disposition: form-data; name=\"first\"\r\n\r\n" +
    "one\r\n" +
    "--feather-boundary\r\n" +
    "Content-Disposition: form-data; name=\"second\"\r\n\r\n" +
    "two\r\n" +
    "--feather-boundary--\r\n"
  let parts = @feather.parse_multipart(
    body,
    "multipart/form-data; boundary=" + boundary,
  ).unwrap()
  assert_eq(parts.length(), 2)
  assert_eq(parts[0].name, "first")
  assert_eq(parts[0].data, "one")
  assert_eq(parts[1].name, "second")
  assert_eq(parts[1].data, "two")
}

///|
test "multipart parser preserves empty and repeated parts" {
  let boundary = "b"
  let body = "--b\r\n" +
    "Content-Disposition: form-data; name=\"empty\"\r\n\r\n" +
    "\r\n" +
    "--b\r\n" +
    "Content-Disposition: form-data; name=\"empty\"\r\n\r\n" +
    "again\r\n" +
    "--b--"
  let parts = @feather.parse_multipart(
    body,
    "multipart/form-data; boundary=" + boundary,
  ).unwrap()
  assert_eq(parts.length(), 2)
  assert_eq(parts[0].data, "")
  assert_eq(parts[1].data, "again")
}

///|
test "urlencoded parser round-trips encoded keys and values" {
  let pairs = [
    ("simple", "value"), ("a b", "c d"), ("a&b", "c=d"), ("pct%", "%25"),
    ("plus+", "+plus+"), ("slash/key", "/value"), ("unicode", "\u{4f60}\u{597d}"),
  ]
  let builder = StringBuilder()
  let mut first = true
  for pair in pairs {
    if !first {
      builder.write_char('&')
    }
    first = false
    builder.write_string(@feather.url_encode(pair.0))
    builder.write_char('=')
    builder.write_string(@feather.url_encode(pair.1))
  }
  let parsed = @feather.parse_urlencoded(builder.to_string())
  for pair in pairs {
    assert_eq(parsed.get(pair.0), Some(pair.1))
  }
}
