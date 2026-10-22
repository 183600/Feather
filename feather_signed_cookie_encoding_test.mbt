///|
test "signed cookie tokens encode lone surrogates lossily" {
  let value = "a" + String::from_array([Char::from_int(0xD800)]) + "b"
  let token = @feather.signed_cookie_token("s3cret", "note", value)
  assert_eq(
    @feather.verify_signed_cookie_token("s3cret", "note", token),
    Some("a\u{FFFD}b"),
  )
  let secret = "k" + String::from_array([Char::from_int(0xDC00)])
  let token = @feather.signed_cookie_token(secret, "note", "value")
  assert_eq(
    @feather.verify_signed_cookie_token(secret, "note", token),
    Some("value"),
  )
}
