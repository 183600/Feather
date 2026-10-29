///|
fn context_with_content_type(value : String) -> @feather.Context {
  @feather.Context::new({
    method: "POST",
    path: "/",
    headers: Map([("Content-Type", value)]),
    body: "x",
  })
}

///|
test "content type parameters are parsed case-insensitively" {
  let ctx = context_with_content_type(
    "Application/JSON; Charset = \"UTF-8\"; profile=example",
  )
  assert_eq(ctx.content_type_parameter("charset"), Some("UTF-8"))
  assert_eq(ctx.content_type_parameter("CHARSET"), Some("UTF-8"))
  assert_eq(ctx.content_type_parameter("profile"), Some("example"))
  assert_eq(ctx.content_type_parameter("missing"), None)
}

///|
test "content type parameters unescape quoted values" {
  let ctx = context_with_content_type(
    "multipart/form-data; boundary=\"a;b\\\"c\\\\d\"",
  )
  assert_eq(ctx.content_type_parameter("boundary"), Some("a;b\"c\\d"))
}

///|
test "content type parameters ignore lookalikes and quoted names" {
  let ctx = context_with_content_type(
    "multipart/form-data; note=\"charset=fake\"; xcharset=wrong; charset=utf-8",
  )
  assert_eq(ctx.content_type_parameter("charset"), Some("utf-8"))
  assert_eq(ctx.content_type_parameter("xcharset"), Some("wrong"))
}

///|
test "content type parameters require an equals sign" {
  let ctx = context_with_content_type(
    "multipart/form-data; charset ; boundary=abc",
  )
  assert_eq(ctx.content_type_parameter("charset"), None)
  assert_eq(ctx.content_type_parameter("boundary"), Some("abc"))
}

///|
test "content type parameter duplicates keep the first value" {
  let ctx = context_with_content_type("text/plain; charset=utf-8; charset=latin1")
  assert_eq(ctx.content_type_parameter("charset"), Some("utf-8"))
}

///|
test "content type parameter is absent without a header" {
  let ctx = @feather.Context::new({
    method: "POST",
    path: "/",
    headers: Map([]),
    body: "x",
  })
  assert_eq(ctx.content_type_parameter("charset"), None)
}
