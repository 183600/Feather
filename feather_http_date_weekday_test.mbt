///|
test "http date rejects unknown weekday names" {
  assert_eq(
    @feather.parse_http_date("Sunx, 06 Nov 2024 08:49:37 GMT"),
    None,
  )
  assert_eq(
    @feather.parse_http_date("Sundayx, 06-Nov-24 08:49:37 GMT"),
    None,
  )
  assert_eq(
    @feather.parse_http_date("Thurs Nov  6 08:49:37 2024"),
    None,
  )
}

///|
test "http date still accepts abbreviated and full weekday names" {
  assert_eq(
    @feather.parse_http_date("Sun, 06 Nov 2024 08:49:37 GMT"),
    Some(1730882977L),
  )
  assert_eq(
    @feather.parse_http_date("Sunday, 06-Nov-24 08:49:37 GMT"),
    Some(1730882977L),
  )
  assert_eq(
    @feather.parse_http_date("Sun Nov  6 08:49:37 2024"),
    Some(1730882977L),
  )
}
