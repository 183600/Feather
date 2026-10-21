///|
fn raw_body_ctx(body : String) -> Context {
  Context::new({
    method: "POST",
    path: "/",
    headers: Map([]),
    body,
  })
}

///|
test "attach_raw_body preserves bytes that are not valid utf8" {
  let ctx = raw_body_ctx("\u{FFFD}A")
  attach_raw_body(ctx, Some(b"\x00\xff\xfe\x41"))
  assert_eq(ctx.body_bytes(), b"\x00\xff\xfe\x41")
}

///|
test "body_bytes re-encodes a well-formed text body" {
  let ctx = raw_body_ctx("héllo 世界")
  assert_eq(ctx.body_bytes(), @utf8.encode("héllo 世界"))
}

///|
test "body_bytes falls back when the preserved body cannot be read" {
  let ctx = raw_body_ctx("hello")
  ctx.state.set(RAW_BODY_STATE_KEY, "not base64!")
  assert_eq(ctx.body_bytes(), b"hello")
}

///|
test "attach_raw_body keeps a body without bytes untouched" {
  let ctx = raw_body_ctx("hello")
  attach_raw_body(ctx, None)
  assert_eq(ctx.state.get(RAW_BODY_STATE_KEY), None)
  assert_eq(ctx.body_bytes(), b"hello")
}
