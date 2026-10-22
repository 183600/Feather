///|
test "http date only uses full weekday names in rfc850 dates" {
  // IMF-fixdate and asctime spell the day-name with exactly three letters.
  assert_eq(
    @feather.parse_http_date("Sunday, 06 Nov 2024 08:49:37 GMT"),
    None,
  )
  assert_eq(
    @feather.parse_http_date("Sunday Nov  6 08:49:37 2024"),
    None,
  )
  // rfc850-date uses the full weekday name, so it keeps accepting it.
  assert_eq(
    @feather.parse_http_date("Sunday, 06-Nov-24 08:49:37 GMT"),
    Some(1730882977L),
  )
  assert_eq(
    @feather.parse_http_date("Sun Nov  6 08:49:37 2024"),
    Some(1730882977L),
  )
}
