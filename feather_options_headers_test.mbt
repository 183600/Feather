///|
test "automatic OPTIONS drops a stale content type" {
  let app = @feather.App::new()
    .use(fn(next) {
      fn(ctx) raise {
        ctx.set_header("Content-Type", "text/html; charset=utf-8")
        next(ctx)
      }
    })
    .get("/resource", fn(ctx) { ctx.text(200, "ok") })
  let response = app.respond({
    method: "OPTIONS",
    path: "/resource",
    headers: Map([]),
    body: "",
  })
  assert_eq(response.status, 204)
  assert_eq(response.body, "")
  assert_eq(response.headers.get("Content-Type"), None)
  assert_eq(response.headers.get("Allow"), Some("GET, HEAD"))
}

///|
test "respond_options drops a stale content type" {
  let ctx = @feather.Context::new({
    method: "OPTIONS",
    path: "/resource",
    headers: Map([]),
    body: "",
  })
  ctx.set_header("Content-Type", "application/json")
  @feather.respond_options(ctx, ["GET", "POST"])
  assert_eq(ctx.response.status, 204)
  assert_eq(ctx.response.headers.get("Content-Type"), None)
  assert_eq(ctx.response.headers.get("Allow"), Some("GET, HEAD, POST"))
}
