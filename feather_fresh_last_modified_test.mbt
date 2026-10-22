///|
fn fresh_context(request_method : String, headers : Map[String, String]) -> @feather.Context {
  @feather.Context::new({
    method: request_method,
    path: "/document",
    headers,
    body: "",
  })
}

///|
test "fresh answers if-modified-since for a matching date" {
  let last_modified = @feather.format_http_date(1_600_000_000L)
  let ctx = fresh_context(
    "GET",
    Map([("If-Modified-Since", last_modified)]),
  )
  assert_true(ctx.fresh("", last_modified=last_modified))
}

///|
test "fresh rejects an older if-modified-since date" {
  let last_modified = @feather.format_http_date(1_600_000_000L)
  let older = @feather.format_http_date(1_599_999_999L)
  let ctx = fresh_context("GET", Map([("If-Modified-Since", older)]))
  assert_false(ctx.fresh("", last_modified=last_modified))
}

///|
test "fresh needs both a request date and a representation date" {
  let last_modified = @feather.format_http_date(1_600_000_000L)
  let ctx = fresh_context("GET", Map([]))
  assert_false(ctx.fresh("", last_modified=last_modified))
  let conditional = fresh_context(
    "GET",
    Map([("If-Modified-Since", last_modified)]),
  )
  assert_false(conditional.fresh(""))
  assert_false(conditional.fresh("", last_modified="not a date"))
}

///|
test "if-none-match takes precedence over if-modified-since" {
  let last_modified = @feather.format_http_date(1_600_000_000L)
  let mismatched = fresh_context(
    "GET",
    Map([
      ("If-None-Match", "\"other\""),
      ("If-Modified-Since", last_modified),
    ]),
  )
  assert_false(mismatched.fresh("\"current\"", last_modified=last_modified))
  let matched = fresh_context(
    "GET",
    Map([
      ("If-None-Match", "\"current\""),
      ("If-Modified-Since", @feather.format_http_date(1_500_000_000L)),
    ]),
  )
  assert_true(matched.fresh("\"current\"", last_modified=last_modified))
}

///|
test "if-modified-since only applies to retrieval methods" {
  let last_modified = @feather.format_http_date(1_600_000_000L)
  let ctx = fresh_context(
    "POST",
    Map([("If-Modified-Since", last_modified)]),
  )
  assert_false(ctx.fresh("", last_modified=last_modified))
}

///|
test "last-modified freshness drives a not-modified response" {
  let last_modified = @feather.format_http_date(1_600_000_000L)
  let app = @feather.App::new().get("/document", fn(ctx) {
    if ctx.fresh("", last_modified=last_modified) {
      ctx.not_modified(last_modified=last_modified)
    } else {
      ctx.set_header("Last-Modified", last_modified)
      ctx.text(200, "document")
    }
  })
  let fresh = app.respond({
    method: "GET",
    path: "/document",
    headers: Map([("If-Modified-Since", last_modified)]),
    body: "",
  })
  assert_eq(fresh.status, 304)
  assert_eq(fresh.body, "")
  assert_eq(fresh.headers.get("Last-Modified"), Some(last_modified))
  let stale = app.respond({
    method: "GET",
    path: "/document",
    headers: Map([
      ("If-Modified-Since", @feather.format_http_date(1_599_999_999L)),
    ]),
    body: "",
  })
  assert_eq(stale.status, 200)
  assert_eq(stale.body, "document")
}
