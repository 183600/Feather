///|
fn fragment_ctx(path : String) -> @feather.Context {
  @feather.Context::new({
    method: "GET",
    path,
    headers: Map([("Host", "example.com")]),
    body: "",
  })
}

///|
test "query helpers ignore a URL fragment" {
  let ctx = fragment_ctx("/search?q=hello+world&tag=a&tag=b#results")
  assert_eq(ctx.query("q"), "hello world")
  assert_eq(ctx.query("tag"), "b")
  assert_eq(ctx.query_values("tag").join(","), "a,b")
  assert_eq(ctx.queries().get("q"), Some("hello world"))
  assert_eq(ctx.query_default("missing", "fallback"), "fallback")
  assert_eq(ctx.query("results"), "")
}

///|
test "a fragment before the question mark hides the query" {
  let ctx = fragment_ctx("/search#results?q=hello")
  assert_eq(ctx.query("q"), "")
  assert_eq(ctx.queries().length(), 0)
  assert_eq(ctx.query_values("q").length(), 0)
}

///|
test "routing ignores a URL fragment" {
  let app = @feather.App::new()
    .get("/docs", fn(ctx) { ctx.text(200, "docs") })
    .get("/named", fn(ctx) { ctx.text(200, "named") })
  let response = app.respond({
    method: "GET",
    path: "/docs#installation",
    headers: Map([]),
    body: "",
  })
  assert_eq(response.status, 200)
  assert_eq(response.body, "docs")

  let before_query = app.respond({
    method: "GET",
    path: "/docs#installation?q=1",
    headers: Map([]),
    body: "",
  })
  assert_eq(before_query.status, 200)
  assert_eq(before_query.body, "docs")

  let registration = @feather.App::new()
    .get("/named#section", fn(ctx) { ctx.text(200, "named") })
  let registered = registration.respond({
    method: "GET",
    path: "/named",
    headers: Map([]),
    body: "",
  })
  assert_eq(registered.status, 200)
  assert_eq(registered.body, "named")
}

///|
test "full_url drops a fragment but keeps the query" {
  let ctx = fragment_ctx("/items?page=2#top")
  assert_eq(ctx.full_url(), "http://example.com/items?page=2")
}

///|
test "static lookup ignores a URL fragment" {
  let app = @feather.App::new().static_files("/assets", "/tmp/feather-fragment")
  assert_eq(
    app.static_file_for("/assets/app.css#theme"),
    Some("/tmp/feather-fragment/app.css"),
  )
}
