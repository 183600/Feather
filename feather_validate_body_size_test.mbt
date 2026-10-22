///|
fn size_limited_feather(max_body_size : Int32) -> @feather.Feather {
  @feather.create_feather({ host: "127.0.0.1", port: 0, timeout: 0, })
  .max_body_size(max_body_size)
}

///|
test "validate_body_size counts utf-8 and lossy surrogate bytes" {
  let lone_high = String::from_array([Char::from_int(0xD800)])
  let lone_low = String::from_array([Char::from_int(0xDC00)])
  let pair = String::from_array([Char::from_int(0xD83D), Char::from_int(0xDE00)])
  // A lone surrogate is replaced by U+FFFD, just like `Context::body_bytes`.
  assert_true(size_limited_feather(3).validate_body_size(lone_high))
  assert_false(size_limited_feather(2).validate_body_size(lone_high))
  assert_true(size_limited_feather(3).validate_body_size(lone_low))
  assert_false(size_limited_feather(2).validate_body_size(lone_low))
  // A well-formed supplementary pair keeps its four-byte encoding.
  assert_true(size_limited_feather(4).validate_body_size(pair))
  assert_false(size_limited_feather(3).validate_body_size(pair))
}
