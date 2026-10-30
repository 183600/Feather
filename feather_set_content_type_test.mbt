///|
fn content_type_response_ctx() -> @feather.Context {
  @feather.Context::new({
    method: "GET",
    path: "/",
    headers: Map([]),
    body: "",
  })
}

///|
test "set content type writes ordered parameters and quotes when needed" {
  let ctx = content_type_response_ctx()
  ctx.set_content_type("Application/Problem+JSON", parameters=[
    ("charset", "utf-8"),
    ("profile", "https://example.com/a b"),
    ("empty", ""),
  ])
  assert_eq(
    ctx.response_header("Content-Type"),
    "Application/Problem+JSON; charset=utf-8; profile=\"https://example.com/a b\"; empty=\"\"",
  )
}

///|
test "set content type escapes quoted parameter values" {
  let ctx = content_type_response_ctx()
  ctx.set_content_type("multipart/form-data", parameters=[
    ("boundary", "a;b\"c\\d"),
  ])
  assert_eq(
    ctx.response_header("Content-Type"),
    "multipart/form-data; boundary=\"a;b\\\"c\\\\d\"",
  )
}

///|
test "set content type skips invalid names and strips controls" {
  let ctx = content_type_response_ctx()
  ctx.set_content_type("text/plain", parameters=[
    ("", "ignored"),
    ("bad name", "ignored"),
    (" charset ", "utf-8"),
    ("note", "a\r\nb"),
  ])
  assert_eq(
    ctx.response_header("Content-Type"),
    "text/plain; charset=utf-8; note=\"ab\"",
  )
}

///|
test "set content type trims separators and ignores an empty media type" {
  let ctx = content_type_response_ctx()
  ctx.set_content_type(" text/plain ; ; ")
  assert_eq(ctx.response_header("Content-Type"), "text/plain")
  ctx.set_content_type("application/json", parameters=[("charset", "utf-8")])
  ctx.set_content_type(" ;; ")
  assert_eq(
    ctx.response_header("Content-Type"),
    "application/json; charset=utf-8",
  )
}

///|
test "set content type appends to an existing parameterized media type" {
  let ctx = content_type_response_ctx()
  ctx.set_content_type("text/plain; charset=utf-8", parameters=[
    ("format", "flowed"),
  ])
  assert_eq(
    ctx.response_header("Content-Type"),
    "text/plain; charset=utf-8; format=flowed",
  )
}

///|
test "set content type replaces the header case insensitively" {
  let app = @feather.App::new().get("/report", fn(ctx) {
    ctx.bytes(200, b"{}", content_type="application/json")
    ctx.set_content_type("application/problem+json", parameters=[
      ("charset", "utf-8"),
    ])
  })
  let response = app.respond({
    method: "GET",
    path: "/report",
    headers: Map([]),
    body: "",
  })
  assert_eq(
    response.headers.get("Content-Type"),
    Some("application/problem+json; charset=utf-8"),
  )
}
