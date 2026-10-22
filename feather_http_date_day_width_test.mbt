///|
test "http date requires fixed-width days outside asctime" {
  // IMF-fixdate and rfc850-date spell the day with exactly two digits.
  assert_eq(@feather.parse_http_date("Sun, 6 Nov 2024 08:49:37 GMT"), None)
  assert_eq(
    @feather.parse_http_date("Sunday, 6-Nov-24 08:49:37 GMT"),
    None,
  )
  assert_eq(@feather.parse_http_date("Sun, 006 Nov 2024 08:49:37 GMT"), None)
  assert_eq(
    @feather.parse_http_date("Sunday, 006-Nov-24 08:49:37 GMT"),
    None,
  )
  // The asctime grammar keeps its space-padded single-digit day.
  assert_eq(
    @feather.parse_http_date("Sun Nov  6 08:49:37 2024"),
    Some(1730882977L),
  )
  assert_eq(
    @feather.parse_http_date("Sun Nov 06 08:49:37 2024"),
    Some(1730882977L),
  )
  assert_eq(@feather.parse_http_date("Sun Nov 006 08:49:37 2024"), None)
}
