///|
test "header index sees names added after a miss with unchanged size" {
  let headers : Map[String, String] = Map([("A", "1")])
  assert_eq(get_header_ignore_case(headers, "X-Token"), None)
  ignore(headers.remove("A"))
  headers.set("x-token", "secret")
  assert_eq(get_header_ignore_case(headers, "X-Token"), Some("secret"))
}

///|
test "header index recovers when a cached spelling is replaced" {
  let headers : Map[String, String] = Map([("X-Token", "secret")])
  assert_eq(get_header_ignore_case(headers, "x-token"), Some("secret"))
  ignore(headers.remove("X-Token"))
  headers.set("X-TOKEN", "rotated")
  assert_eq(get_header_ignore_case(headers, "x-token"), Some("rotated"))
  assert_eq(get_header_ignore_case(headers, "X-Token"), Some("rotated"))
}

///|
test "header index does not remember absent names" {
  let headers : Map[String, String] = Map([("Content-Type", "text/plain")])
  assert_eq(get_header_ignore_case(headers, "X-Missing"), None)
  assert_eq(get_header_ignore_case(headers, "X-Missing"), None)
  headers.set("X-Missing", "now-here")
  assert_eq(get_header_ignore_case(headers, "x-missing"), Some("now-here"))
}

///|
test "Context header lookup sees headers added after a miss" {
  let request : Request = {
    method: "GET",
    path: "/",
    headers: Map([("A", "1")]),
    body: "",
  }
  let ctx = Context::new(request)
  assert_eq(ctx.header("X-Token"), "")
  ignore(ctx.request.headers.remove("A"))
  ctx.request.headers.set("x-token", "secret")
  assert_eq(ctx.header("X-Token"), "secret")
}
