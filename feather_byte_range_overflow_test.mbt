///|
test "byte ranges treat overflowing numeric offsets as unsatisfiable" {
  let total = 100L
  assert_true(
    @feather.parse_byte_range("bytes=999999999999999999999999-", total)
    is @feather.ByteRangeInvalid,
  )
  assert_true(
    @feather.parse_byte_range("bytes=999999999999999999999999-999999999999999999999999", total)
    is @feather.ByteRangeInvalid,
  )
  assert_true(
    @feather.parse_byte_range("bytes=-999999999999999999999999", total)
    is @feather.ByteRangeSpec(0L, 99L),
  )
}

///|
test "byte ranges clamp an overflowing end to the representation end" {
  assert_true(
    @feather.parse_byte_range("bytes=10-999999999999999999999999", 100L)
    is @feather.ByteRangeSpec(10L, 99L),
  )
  assert_true(
    @feather.parse_byte_range("bytes=0-999999999999999999999999", 0L)
    is @feather.ByteRangeInvalid,
  )
}

///|
test "byte ranges still ignore malformed offsets" {
  for value in [
    "bytes=abc-1",
    "bytes=1-abc",
    "bytes=-abc",
    "bytes=+1-2",
    "bytes=1--2",
  ] {
    assert_true(
      @feather.parse_byte_range(value, 100L) is @feather.ByteRangeFull,
      msg=value,
    )
  }
}
