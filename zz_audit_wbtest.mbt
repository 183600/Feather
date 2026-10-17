///|
test "audit weak etag comparison is symmetric" {
  assert_true(etag_header_matches("W/\"abc\"".view(), "\"abc\""))
  assert_true(etag_header_matches("\"abc\"".view(), "W/\"abc\""))
}

///|
test "audit accept negotiation" {
  assert_eq(accept_quality_for("text/html;q=0", "text/html".view()), 0)
  assert_eq(accept_quality_for("*/*;q=0.5", "text/html".view()), 500)
  assert_eq(
    accept_quality_for("text/*;q=0.5, text/html;q=0", "text/html".view()),
    0,
  )
  assert_eq(
    accept_quality_for("text/*;q=0.5, text/html;q=0", "text/plain".view()),
    500,
  )
  assert_eq(accept_quality_for("", "text/html".view()), 1000)
  assert_eq(accept_encoding_quality("gzip;q=0.5, *;q=0.8".view(), "gzip".view()), 500)
  assert_eq(accept_encoding_quality("br, *;q=0.5".view(), "gzip".view()), 500)
  assert_eq(accept_encoding_quality("br".view(), "gzip".view()), 0)
}
