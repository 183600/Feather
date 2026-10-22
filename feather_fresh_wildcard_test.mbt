///|
fn fresh_wildcard_context(headers : Map[String, String]) -> @feather.Context {
  @feather.Context::new({
    method: "GET",
    path: "/document",
    headers,
    body: "",
  })
}

///|
test "fresh treats a wildcard if-none-match as matching without an etag" {
  let wildcard = fresh_wildcard_context(Map([("If-None-Match", "*")]))
  assert_true(wildcard.fresh(""))
  let listed = fresh_wildcard_context(
    Map([("If-None-Match", "\"other\", *")]),
  )
  assert_true(listed.fresh(""))
}

///|
test "fresh still rejects concrete tags without an etag" {
  let concrete = fresh_wildcard_context(
    Map([("If-None-Match", "\"other\"")]),
  )
  assert_false(concrete.fresh(""))
}

///|
test "fresh wildcard wins over an if-modified-since date without an etag" {
  let last_modified = @feather.format_http_date(1_600_000_000L)
  let ctx = fresh_wildcard_context(
    Map([
      ("If-None-Match", "*"),
      ("If-Modified-Since", @feather.format_http_date(1_500_000_000L)),
    ]),
  )
  assert_true(ctx.fresh("", last_modified=last_modified))
}
