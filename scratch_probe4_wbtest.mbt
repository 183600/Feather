///|
test "probe4 format_http_date vectors" {
  assert_eq(format_http_date(-1L), "Wed, 31 Dec 1969 23:59:59 GMT")
  assert_eq(format_http_date(-86400L), "Wed, 31 Dec 1969 00:00:00 GMT")
  assert_eq(format_http_date(-2208988800L), "Mon, 01 Jan 1900 00:00:00 GMT")
  assert_eq(format_http_date(951782400L), "Tue, 29 Feb 2000 00:00:00 GMT")
  assert_eq(format_http_date(2147483647L), "Tue, 19 Jan 2038 03:14:07 GMT")
  assert_eq(format_http_date(4102444800L), "Fri, 01 Jan 2100 00:00:00 GMT")
  assert_eq(format_http_date(253402300799L), "Fri, 31 Dec 9999 23:59:59 GMT")
  assert_eq(format_http_date(-1000000000L), "Sun, 24 Apr 1938 22:13:20 GMT")
  assert_eq(format_http_date(1000000000L), "Sun, 09 Sep 2001 01:46:40 GMT")
}

///|
test "probe4 parse_http_date legacy year window" {
  assert_eq(
    parse_http_date("Monday, 01-Jan-69 00:00:00 GMT"),
    parse_http_date("Wednesday, 01-Jan-2069 00:00:00 GMT"),
  )
  assert_eq(
    parse_http_date("Thursday, 01-Jan-70 00:00:00 GMT"),
    parse_http_date("Thursday, 01-Jan-1970 00:00:00 GMT"),
  )
}

///|
test "probe4 parse_byte_range edges" {
  assert_eq(parse_byte_range("bytes=0-0", 0L) is ByteRangeInvalid, true)
  assert_eq(parse_byte_range("bytes=-0", 10L) is ByteRangeInvalid, true)
  assert_eq(parse_byte_range("bytes=5-3", 10L) is ByteRangeFull, true)
  assert_eq(parse_byte_range("bytes=99-", 10L) is ByteRangeInvalid, true)
  assert_true(scratch_range_is(parse_byte_range("bytes=9-99", 10L), 9L, 9L))
  assert_true(scratch_range_is(parse_byte_range("bytes=-99", 10L), 0L, 9L))
  assert_eq(parse_byte_range("bytes=0-1,3-4", 10L) is ByteRangeFull, true)
}
