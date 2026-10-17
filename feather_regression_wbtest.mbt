///|
test "parse_quality rejects values above one" {
  assert_eq(parse_quality("1.5".view()), 0)
  assert_eq(parse_quality("01.5".view()), 0)
  assert_eq(parse_quality("1.999".view()), 0)
  assert_eq(parse_quality("1.000".view()), 1000)
  assert_eq(parse_quality("1".view()), 1000)
  assert_eq(parse_quality("0.999".view()), 999)
}

///|
test "accept quality ignores fractional values above one" {
  assert_eq(accept_quality_for("text/html;q=1.5".view(), "text/html".view()), 0)
  assert_eq(
    accept_quality_for(
      "text/html;q=1.5, application/json;q=0.9".view(),
      "text/html".view(),
    ),
    0,
  )
  assert_eq(
    accept_quality_for(
      "text/html;q=1.5, application/json;q=0.9".view(),
      "application/json".view(),
    ),
    900,
  )
}

///|
test "accept encoding quality rejects fractional values above one" {
  assert_eq(
    accept_encoding_quality("gzip;q=1.5".view(), "gzip".view()),
    0,
  )
  assert_true(accept_encoding_allows_gzip("gzip;q=1.0".view()))
  assert_false(accept_encoding_allows_gzip("gzip;q=1.5".view()))
}

///|
test "parse_multipart finds the earliest header terminator for lf parts" {
  let body = "--X\nContent-Disposition: form-data; name=\"a\"\n\nfoo\r\n\r\nbar\n--X--\n"
  let parts = parse_multipart(body, "multipart/form-data; boundary=X").unwrap()
  assert_eq(parts.length(), 1)
  assert_eq(parts[0].name, "a")
  assert_eq(parts[0].data, "foo\r\n\r\nbar")
}

///|
test "parse_multipart still prefers crlf headers when crlf comes first" {
  let body = "--X\r\nContent-Disposition: form-data; name=\"a\"\r\n\r\none\n\ntwo\r\n--X--\r\n"
  let parts = parse_multipart(body, "multipart/form-data; boundary=X").unwrap()
  assert_eq(parts.length(), 1)
  assert_eq(parts[0].data, "one\n\ntwo")
}
