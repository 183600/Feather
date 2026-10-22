///|
test "rfc850 two-digit years stay inside the rfc 9110 window" {
  let current = http_current_year()
  for digit in [0, 1, 50, 68, 69, 70, 76, 77, 90, 99] {
    let year = expand_two_digit_year(digit)
    assert_eq(year % 100L, digit.to_int64())
    assert_true(year <= current + 50L)
    assert_true(year >= current - 99L)
  }
  let current_suffix = (current % 100L).to_int()
  assert_eq(expand_two_digit_year(current_suffix), current)
}

///|
test "rfc850 year 70 is not treated as a year before the window" {
  let parsed = parse_http_date("Thursday, 01-Jan-70 00:00:00 GMT").unwrap()
  let now = @async.now() / 1000L
  let difference = if parsed >= now { parsed - now } else { now - parsed }
  // 50 years with a generous leap-day allowance; the old fixed 1970 pivot
  // would be roughly 56 years away in the current era.
  assert_true(difference <= 50L * 366L * 86400L)
}
