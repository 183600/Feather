///|
test "decode_utf8_lossless keeps valid utf8 intact" {
  assert_eq(
    decode_utf8_lossless(@utf8.encode("héllo 世界")),
    "héllo 世界",
  )
}

///|
test "decode_utf8_lossless escapes invalid bytes as code units" {
  let decoded = decode_utf8_lossless(b"\x41\xff\x80\x42")
  assert_eq(decoded.length(), 4)
  assert_eq(decoded.unsafe_get(0).to_int(), 0x41)
  assert_eq(decoded.unsafe_get(1).to_int(), 0xDC00 + 0xFF)
  assert_eq(decoded.unsafe_get(2).to_int(), 0xDC00 + 0x80)
  assert_eq(decoded.unsafe_get(3).to_int(), 0x42)
}

///|
test "lossless codec round trips arbitrary bytes" {
  for
    bytes in [
      b"", b"\x00\x01\x02\x7f", b"\x80\xbf\xc0\xc1\xf5\xff", b"\xe4\xb8\x96\xe7\x95\x8c",
      b"\xf0\x9f\x98\x80", b"\xff\xfe\x00binary\x80", b"\xe0\x80\x80", b"\xed\xa0\x80\xed\xb0\x80",
      b"\xf0\x80\x80\x80", b"\xf4\x90\x80\x80", b"\xe0\xa0\x80\xf0\x90\x80\x80",
    ] {
    assert_eq(encode_utf8_lossless(decode_utf8_lossless(bytes)), bytes)
  }
}

///|
test "lossless codec round trips a supplementary character" {
  let smile = "😀"
  let bytes = @utf8.encode(smile)
  assert_eq(bytes.length(), 4)
  assert_eq(encode_utf8_lossless(decode_utf8_lossless(bytes)), bytes)
}

///|
test "resolve_part_bytes recovers bytes from lossless text" {
  let builder = StringBuilder()
  builder.write_char((0xDC00).unsafe_to_char())
  builder.write_char((0xDCFF).unsafe_to_char())
  builder.write_char('A')
  builder.write_char('B')
  let (bytes, text) = resolve_part_bytes("x", Some(builder.to_string()))
  assert_eq(bytes, b"\x00\xffAB")
  assert_eq(text, "\u{0}\u{FFFD}AB")
}

///|
test "resolve_part_bytes falls back to encoding text" {
  let (bytes, text) = resolve_part_bytes("héllo", None)
  assert_eq(bytes, @utf8.encode("héllo"))
  assert_eq(text, "héllo")
}
