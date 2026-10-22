///|
test "http date rejects years that are not four digits" {
  // A malformed year must not be read as a far-future validator: conditional
  // requests would otherwise treat it as a valid, very late date.
  assert_eq(
    @feather.parse_http_date("Sun, 06 Nov 20250 08:49:37 GMT"),
    None,
  )
  assert_eq(
    @feather.parse_http_date("Sun, 06 Nov 02024 08:49:37 GMT"),
    None,
  )
  assert_eq(@feather.parse_http_date("Sun Nov  6 08:49:37 20250"), None)
  assert_eq(@feather.parse_http_date("Sun Nov  6 08:49:37 02024"), None)
}

///|
test "http date still accepts four-digit rfc1123 and asctime years" {
  assert_eq(
    @feather.parse_http_date("Sun, 06 Nov 2024 08:49:37 GMT"),
    Some(1730882977L),
  )
  assert_eq(
    @feather.parse_http_date("Sun Nov  6 08:49:37 2024"),
    Some(1730882977L),
  )
}

///|
test "http date round trips pre-epoch timestamps" {
  for seconds in [-1L, -86400L, -2208988800L] {
    let text = @feather.format_http_date(seconds)
    assert_eq(@feather.parse_http_date(text), Some(seconds), msg=text)
  }
}
