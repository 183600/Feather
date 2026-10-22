///|
fn url_decode_first_unit(text : String) -> Int {
  text.view().unsafe_get(0).to_int()
}

///|
test "url_decode replaces lone surrogates without percent or plus escapes" {
  let lone_high = String::from_array([Char::from_int(0xD800)])
  let lone_low = String::from_array([Char::from_int(0xDC00)])
  let decoded_high = @feather.url_decode(lone_high)
  assert_eq(decoded_high.view().length(), 1)
  assert_eq(url_decode_first_unit(decoded_high), 0xFFFD)
  let decoded_low = @feather.url_decode(lone_low)
  assert_eq(decoded_low.view().length(), 1)
  assert_eq(url_decode_first_unit(decoded_low), 0xFFFD)
  let decoded_after = @feather.url_decode("é" + lone_high)
  assert_eq(decoded_after.view().length(), 2)
  assert_eq(decoded_after.view().unsafe_get(0).to_int(), 0xE9)
  assert_eq(decoded_after.view().unsafe_get(1).to_int(), 0xFFFD)
  let decoded_before = @feather.url_decode(lone_low + "é")
  assert_eq(decoded_before.view().length(), 2)
  assert_eq(decoded_before.view().unsafe_get(0).to_int(), 0xFFFD)
  assert_eq(decoded_before.view().unsafe_get(1).to_int(), 0xE9)
  let pair = String::from_array([Char::from_int(0xD83D), Char::from_int(0xDE00)])
  assert_eq(@feather.url_decode(pair), pair)
}
