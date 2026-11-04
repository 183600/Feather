///|
test "header integer accessors parse signed values and trim whitespace" {
  let ctx = @feather.Context::new({
    method: "GET",
    path: "/",
    headers: Map([
      ("X-Count", " 42 "),
      ("X-Plus", "+7"),
      ("X-Negative", "-8"),
      ("X-Overflow", "2147483648"),
      ("X-Bad", "12x"),
      ("X-Empty", ""),
      ("X-Int64-Max", "9223372036854775807"),
      ("X-Int64-Min", "-9223372036854775808"),
      ("X-Int64-Overflow", "9223372036854775808"),
    ]),
    body: "",
  })
  assert_eq(ctx.header_int("x-count"), Some(42))
  assert_eq(ctx.header_int("X-PLUS"), Some(7))
  assert_eq(ctx.header_int("X-Negative"), Some(-8))
  assert_eq(ctx.header_int("X-Overflow"), None)
  assert_eq(ctx.header_int("X-Bad"), None)
  assert_eq(ctx.header_int("X-Empty"), None)
  assert_eq(ctx.header_int("X-Missing"), None)
  assert_eq(ctx.header_int64("X-Int64-Max"), Some(9223372036854775807L))
  assert_eq(
    ctx.header_int64("X-Int64-Min"),
    Some(-9223372036854775807L - 1L),
  )
  assert_eq(ctx.header_int64("X-Int64-Overflow"), None)
  assert_eq(ctx.header_int64("X-Bad"), None)
}

///|
test "header boolean and float accessors use the shared typed parsers" {
  let ctx = @feather.Context::new({
    method: "GET",
    path: "/",
    headers: Map([
      ("X-True", "true"),
      ("X-False", "0"),
      ("X-One", " 1 "),
      ("X-Bool-Bad", "yes"),
      ("X-Ratio", " 1.25 "),
      ("X-Exponent", "-2e3"),
      ("X-Nan", "nan"),
      ("X-Inf", "inf"),
      ("X-Underscore", "1_000"),
      ("X-Float-Bad", "1.2.3"),
    ]),
    body: "",
  })
  assert_eq(ctx.header_bool("X-True"), Some(true))
  assert_eq(ctx.header_bool("x-false"), Some(false))
  assert_eq(ctx.header_bool("X-One"), Some(true))
  assert_eq(ctx.header_bool("X-Bool-Bad"), None)
  assert_eq(ctx.header_bool("X-Missing"), None)
  assert_eq(ctx.header_float("X-Ratio"), Some(1.25))
  assert_eq(ctx.header_float("X-Exponent"), Some(-2000.0))
  assert_eq(ctx.header_float("X-Nan"), None)
  assert_eq(ctx.header_float("X-Inf"), None)
  assert_eq(ctx.header_float("X-Underscore"), None)
  assert_eq(ctx.header_float("X-Float-Bad"), None)
  assert_eq(ctx.header_float("X-Missing"), None)
}

///|
test "content_length and content_length64 parse the Content-Length header" {
  let ctx = @feather.Context::new({
    method: "POST",
    path: "/",
    headers: Map([
      ("Content-Length", " 123 "),
      ("Content-Length-Dup", "456"),
    ]),
    body: "",
  })
  assert_eq(ctx.content_length(), Some(123))
  assert_eq(ctx.content_length64(), Some(123L))
  let missing = @feather.Context::new({
    method: "GET",
    path: "/",
    headers: Map([]),
    body: "",
  })
  assert_eq(missing.content_length(), None)
  assert_eq(missing.content_length64(), None)
  let bad = @feather.Context::new({
    method: "POST",
    path: "/",
    headers: Map([("Content-Length", "abc")]),
    body: "",
  })
  assert_eq(bad.content_length(), None)
  assert_eq(bad.content_length64(), None)
  let overflow = @feather.Context::new({
    method: "POST",
    path: "/",
    headers: Map([("Content-Length", "2147483648")]),
    body: "",
  })
  assert_eq(overflow.content_length(), None)
  assert_eq(overflow.content_length64(), Some(2147483648L))
  let int64_overflow = @feather.Context::new({
    method: "POST",
    path: "/",
    headers: Map([("Content-Length", "9223372036854775808")]),
    body: "",
  })
  assert_eq(int64_overflow.content_length64(), None)
}

///|
test "Context::request_headers returns all request headers with canonical names" {
  let ctx = @feather.Context::new({
    method: "GET",
    path: "/",
    headers: Map([
      ("Content-Type", "application/json"),
      ("X-Custom-Header", "value1"),
      ("X-Another", "value2"),
    ]),
    body: "",
  })
  let headers = ctx.request_headers()
  assert_eq(headers.get("content-type"), Some("application/json"))
  assert_eq(headers.get("x-custom-header"), Some("value1"))
  assert_eq(headers.get("x-another"), Some("value2"))
  assert_eq(headers.length(), 3)
  // Original map should be unchanged
  assert_eq(ctx.header("Content-Type"), "application/json")
}

///|
test "Context::request_headers returns empty map for no headers" {
  let ctx = @feather.Context::new({
    method: "GET",
    path: "/",
    headers: Map([]),
    body: "",
  })
  let headers = ctx.request_headers()
  assert_eq(headers.length(), 0)
}

///|
test "Context::response_headers returns all response headers with canonical names" {
  let ctx = @feather.Context::new({
    method: "GET",
    path: "/",
    headers: Map([]),
    body: "",
  })
  ctx.set_header("Content-Type", "text/html")
  ctx.set_header("X-Response-Header", "response-value")
  ctx.set_header("Cache-Control", "no-cache")
  let headers = ctx.response_headers()
  assert_eq(headers.get("content-type"), Some("text/html"))
  assert_eq(headers.get("x-response-header"), Some("response-value"))
  assert_eq(headers.get("cache-control"), Some("no-cache"))
  assert_eq(headers.length(), 3)
}

///|
test "Context::response_headers returns empty map when no response headers set" {
  let ctx = @feather.Context::new({
    method: "GET",
    path: "/",
    headers: Map([]),
    body: "",
  })
  let headers = ctx.response_headers()
  assert_eq(headers.length(), 0)
}

///|
test "Context::request_headers and response_headers return copies" {
  let ctx = @feather.Context::new({
    method: "GET",
    path: "/",
    headers: Map([("X-Test", "value")]),
    body: "",
  })
  let req_headers = ctx.request_headers()
  let res_headers = ctx.response_headers()
  // Mutating the copies should not affect the context
  req_headers.set("x-test", "mutated")
  res_headers.set("x-new", "new-value")
  assert_eq(ctx.header("X-Test"), "value")
  assert_eq(ctx.response_header("X-New"), "")
}

///|
test "Context::request_headers handles headers with special characters in values" {
  let ctx = @feather.Context::new({
    method: "GET",
    path: "/",
    headers: Map([
      ("X-Special", "value with spaces and !@#$%^&*()"),
      ("X-Unicode", "café naïve résumé"),
      ("X-Empty", ""),
    ]),
    body: "",
  })
  let headers = ctx.request_headers()
  assert_eq(headers.get("x-special"), Some("value with spaces and !@#$%^&*()"))
  assert_eq(headers.get("x-unicode"), Some("café naïve résumé"))
  assert_eq(headers.get("x-empty"), Some(""))
  assert_eq(headers.length(), 3)
}
