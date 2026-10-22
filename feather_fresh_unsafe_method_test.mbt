///|
fn fresh_method_context(method : String, headers : Map[String, String]) -> @feather.Context {
  @feather.Context::new({
    method,
    path: "/items/1",
    headers,
    body: "",
  })
}

///|
test "fresh only answers conditional retrieval methods" {
  let none_match = Map([("If-None-Match", "\"v1\"")])
  for method in ["GET", "HEAD", "get", "head"] {
    let ctx = fresh_method_context(method, none_match)
    assert_true(ctx.fresh("\"v1\""), msg=method)
  }
  for method in ["POST", "PUT", "PATCH", "DELETE", "CONNECT", "TRACE"] {
    let ctx = fresh_method_context(method, none_match)
    assert_false(ctx.fresh("\"v1\""), msg=method)
    assert_false(ctx.fresh("*"), msg=method)
  }
}

///|
test "fresh ignores date validation on unsafe methods" {
  let stamp = @feather.format_http_date(1_700_000_000L)
  let headers = Map([("If-Modified-Since", stamp)])
  let get = fresh_method_context("GET", headers)
  assert_true(get.fresh("", last_modified=stamp))
  for method in ["POST", "PUT", "PATCH", "DELETE"] {
    let ctx = fresh_method_context(method, headers)
    assert_false(ctx.fresh("", last_modified=stamp), msg=method)
  }
}
