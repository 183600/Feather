///|
test "redirects drop a stale content type" {
  let ctx = @feather.create_context()
  ctx.set_header("Content-Type", "application/json")
  ctx.redirect(302, "/next")
  assert_eq(ctx.response.headers.get("Content-Type"), None)
  assert_eq(ctx.response.headers.get("Location"), Some("/next"))
  assert_eq(ctx.response.body, "")
}

///|
test "https redirects drop a stale content type" {
  let app = @feather.App::new()
    .use(fn(next) {
      fn(ctx) raise {
        ctx.set_header("Content-Type", "application/json")
        next(ctx)
      }
    })
    .use(@feather.middleware_https_redirect())
    .get("/", fn(ctx) { ctx.text(200, "ok") })
  let response = app.respond({
    method: "GET",
    path: "/",
    headers: Map([("Host", "example.test")]),
    body: "",
  })
  assert_eq(response.status, 308)
  assert_eq(response.headers.get("Content-Type"), None)
  assert_eq(response.headers.get("Location"), Some("https://example.test/"))
  assert_eq(response.body, "")
}
