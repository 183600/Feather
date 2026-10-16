///|
fn accept_ctx(accept : String) -> @feather.Context {
  @feather.Context::new({
    method: "GET",
    path: "/",
    headers: if accept == "" {
      Map([])
    } else {
      Map([("Accept", accept)])
    },
    body: "",
  })
}

///|
test "accepts treats a missing accept header as accepting everything" {
  assert_true(accept_ctx("").accepts("application/json"))
  assert_true(accept_ctx("").accepts("text/html"))
}

///|
test "accepts matches exact media types case insensitively" {
  assert_true(accept_ctx("application/json").accepts("application/json"))
  assert_true(accept_ctx("Application/JSON").accepts("application/json"))
  assert_false(accept_ctx("application/json").accepts("text/html"))
}

///|
test "accepts understands wildcard media ranges" {
  assert_true(accept_ctx("*/*").accepts("application/json"))
  assert_true(accept_ctx("text/*").accepts("text/html"))
  assert_false(accept_ctx("text/*").accepts("application/json"))
  assert_true(accept_ctx("text/html, */*;q=0.1").accepts("application/xml"))
}

///|
test "accepts honors quality values" {
  assert_false(accept_ctx("application/json;q=0").accepts("application/json"))
  assert_true(accept_ctx("application/json;q=0.001").accepts("application/json"))
  assert_false(accept_ctx("*/*;q=0").accepts("text/html"))
}

///|
test "accepts prefers the most specific matching range" {
  let header = "application/json;q=0, */*;q=0.9"
  assert_false(accept_ctx(header).accepts("application/json"))
  assert_true(accept_ctx(header).accepts("text/html"))
  let wildcard_off = "text/html, */*;q=0"
  assert_true(accept_ctx(wildcard_off).accepts("text/html"))
  assert_false(accept_ctx(wildcard_off).accepts("application/json"))
}

///|
test "accepts ignores media type parameters on the offer" {
  assert_true(
    accept_ctx("text/html").accepts("text/html; charset=utf-8"),
  )
  assert_true(accept_ctx("application/json").accepts("application/json"))
}

///|
test "accepts tolerates malformed headers" {
  assert_true(accept_ctx("garbage").accepts("text/html"))
  assert_true(accept_ctx(",,,").accepts("text/html"))
}

///|
test "preferred_type picks the best matching offer" {
  let ctx = accept_ctx("text/html;q=0.9, application/json;q=0.8")
  assert_eq(ctx.preferred_type(["application/json", "text/html"]), Some("text/html"))
  assert_eq(
    ctx.preferred_type(["text/plain", "application/xml"]),
    None,
  )
}

///|
test "preferred_type keeps server order on quality ties" {
  let ctx = accept_ctx("*/*")
  assert_eq(
    ctx.preferred_type(["application/json", "text/html"]),
    Some("application/json"),
  )
  let specific = accept_ctx("text/html, application/json")
  assert_eq(
    specific.preferred_type(["application/json", "text/html"]),
    Some("application/json"),
  )
}

///|
test "preferred_type skips rejected offers" {
  let ctx = accept_ctx("application/json;q=0, text/*")
  assert_eq(
    ctx.preferred_type(["application/json", "text/html"]),
    Some("text/html"),
  )
  assert_eq(
    ctx.preferred_type(["application/json", "image/png"]),
    None,
  )
  assert_eq(
    accept_ctx("").preferred_type([]),
    None,
  )
}
