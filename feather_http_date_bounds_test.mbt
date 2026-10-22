///|
test "format_http_date clamps to the four-digit year range" {
  assert_eq(
    @feather.format_http_date(253402300800L),
    "Fri, 31 Dec 9999 23:59:59 GMT",
  )
  assert_eq(
    @feather.parse_http_date(@feather.format_http_date(253402300800L)),
    Some(253402300799L),
  )
  let before_epoch = -719528L * 86400L
  assert_eq(
    @feather.format_http_date(before_epoch - 1L),
    "Sat, 01 Jan 0000 00:00:00 GMT",
  )
  assert_eq(
    @feather.parse_http_date(@feather.format_http_date(before_epoch - 1L)),
    Some(before_epoch),
  )
}
