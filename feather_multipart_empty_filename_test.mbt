///|
fn empty_filename_multipart_ctx() -> @feather.Context {
  let body = "--B\r\n" +
    "Content-Disposition: form-data; name=\"empty\"; filename=\"\"\r\n" +
    "Content-Type: application/octet-stream\r\n\r\n" +
    "\r\n--B\r\n" +
    "Content-Disposition: form-data; name=\"star\"; filename*=UTF-8''\r\n\r\n" +
    "\r\n--B\r\n" +
    "Content-Disposition: form-data; name=\"field\"\r\n\r\n" +
    "value\r\n--B--\r\n"
  @feather.Context::new({
    method: "POST",
    path: "/",
    headers: Map([("Content-Type", "multipart/form-data; boundary=B")]),
    body,
  })
}

///|
test "an empty filename parameter still marks a file part" {
  let ctx = empty_filename_multipart_ctx()
  let file = ctx.multipart_file("empty").unwrap()
  assert_eq(file.name, "empty")
  assert_eq(file.filename, "")
  assert_eq(file.data, "")
  assert_eq(ctx.multipart_value("empty"), "")
  assert_eq(ctx.multipart_values("empty").length(), 0)
  assert_eq(ctx.multipart_files("empty").length(), 1)
  let star = ctx.multipart_file("star").unwrap()
  assert_eq(star.filename, "")
  assert_eq(ctx.multipart_value("star"), "")
  assert_eq(ctx.multipart_files("star").length(), 1)
}

///|
test "a part without a filename parameter remains a text field" {
  let ctx = empty_filename_multipart_ctx()
  assert_eq(ctx.multipart_value("field"), "value")
  assert_eq(ctx.multipart_values("field").join(","), "value")
  assert_eq(ctx.multipart_file("field"), None)
  assert_eq(ctx.multipart_files("field").length(), 0)
}
