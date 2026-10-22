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

///|
test "resolve_part_bytes fallback replaces lone surrogates" {
  let lone_high = String::from_array([Char::from_int(0xD800)])
  let lone_low = String::from_array([Char::from_int(0xDC00)])
  let (bytes, text) = resolve_part_bytes(
    "A" + lone_high + "B" + lone_low,
    None,
  )
  assert_eq(bytes, @utf8.encode("A\u{FFFD}B\u{FFFD}"))
  assert_eq(text, "A\u{FFFD}B\u{FFFD}")
}

///|
fn lossless_multipart_body(byte : Int32) -> (String, String) {
  let prefix = "--B\r\nContent-Disposition: form-data; name=\"f\"; filename=\"a.bin\"\r\n\r\n"
  let suffix = "\r\n--B--\r\n"
  let builder = StringBuilder()
  builder.write_string(prefix)
  builder.write_char((0xDC00 + byte).unsafe_to_char())
  builder.write_string(suffix)
  let raw = builder.to_string()
  (prefix + "\u{FFFD}" + suffix, raw)
}

///|
test "multipart cache distinguishes lossy-equal binary bodies" {
  let (body, raw_ff) = lossless_multipart_body(0xFF)
  let (_, raw_80) = lossless_multipart_body(0x80)
  assert_eq(body, body)
  let make = fn(raw : String) {
    let ctx = Context::new({
      method: "POST",
      path: "/",
      headers: Map([("Content-Type", "multipart/form-data; boundary=B")]),
      body,
    })
    ctx.state.set(RAW_BODY_STATE_KEY, base64_encode(encode_utf8_lossless(raw)))
    ctx
  }
  let first = make(raw_ff).multipart_file("f").unwrap()
  let second = make(raw_80).multipart_file("f").unwrap()
  assert_eq(first.data_bytes, b"\xff")
  assert_eq(second.data_bytes, b"\x80")
}
