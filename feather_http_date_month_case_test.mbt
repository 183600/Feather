///|
test "HTTP dates accept case-insensitive month names" {
  let expected = Some(784111777L)
  for value in [
    "Sun, 06 Nov 1994 08:49:37 GMT",
    "Sun, 06 nov 1994 08:49:37 GMT",
    "SUN, 06 NOV 1994 08:49:37 GMT",
    "Sun, 06 nOv 1994 08:49:37 GMT",
    "Sunday, 06-nov-94 08:49:37 GMT",
    "Sunday, 06-NOV-1994 08:49:37 GMT",
    "Sun nov  6 08:49:37 1994",
    "SUN NOV  6 08:49:37 1994",
  ] {
    assert_eq(@feather.parse_http_date(value), expected, msg=value)
  }
  assert_eq(@feather.parse_http_date("Sun, 06 Nox 1994 08:49:37 GMT"), None)
}
