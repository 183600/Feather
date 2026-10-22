///|
test "signed cookie deadlines reject values outside the signed 64-bit range" {
  assert_eq(parse_decimal_int64("0".view()), Some(0L))
  assert_eq(
    parse_decimal_int64("9223372036854775807".view()),
    Some(9223372036854775807L),
  )
  assert_eq(parse_decimal_int64("9223372036854775808".view()), None)
  assert_eq(parse_decimal_int64("9999999999999999999".view()), None)
  assert_eq(parse_decimal_int64("0001".view()), Some(1L))
}
