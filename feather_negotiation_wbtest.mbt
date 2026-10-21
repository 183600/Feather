///|
test "weak etag comparison is symmetric" {
  assert_true(etag_header_matches("W/\"abc\"".view(), "\"abc\""))
  assert_true(etag_header_matches("\"abc\"".view(), "W/\"abc\""))
}

///|
test "accept negotiation" {
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
  assert_eq(
    accept_encoding_quality("gzip;q=0.5, *;q=0.8".view(), "gzip".view()),
    500,
  )
  assert_eq(accept_encoding_quality("br, *;q=0.5".view(), "gzip".view()), 500)
  assert_eq(accept_encoding_quality("br".view(), "gzip".view()), 0)
}

///|
test "accept negotiation keeps quoted parameters intact" {
  assert_eq(
    accept_quality_for("text/html;note=\"a,b\";q=0.2", "text/html".view()),
    200,
  )
  assert_eq(
    accept_quality_for("text/html;note=\"a;b;q=0\"", "text/html".view()),
    1000,
  )
  assert_eq(
    accept_encoding_quality("gzip;ext=\"a,b\";q=0.5".view(), "gzip".view()),
    500,
  )
}

///|
test "accept negotiation honors tab ows before the q value" {
  assert_eq(accept_quality_for("text/html;q\t=0.5", "text/html".view()), 500)
  assert_eq(accept_quality_for("text/html;q\t=0", "text/html".view()), 0)
  assert_eq(accept_encoding_quality("gzip;q\t=0.5".view(), "gzip".view()), 500)
}

///|
test "accept negotiation keeps the best quality among equally specific ranges" {
  assert_eq(
    accept_quality_for("text/html;q=0.2, text/html;q=0.9", "text/html".view()),
    900,
  )
  assert_eq(
    accept_quality_for("text/html;q=0.9, text/html;q=0", "text/html".view()),
    900,
  )
  assert_eq(
    accept_quality_for("text/*;q=0.2, text/*;q=0.7", "text/plain".view()),
    700,
  )
}
