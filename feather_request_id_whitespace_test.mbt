///|
test "request id generates an id when the incoming value is whitespace only" {
  let app = @feather.App::new()
    .use(@feather.middleware_request_id())
    .get("/id", fn(ctx) { ctx.text(200, ctx.request_id()) })
  let response = app.respond({
    method: "GET",
    path: "/id",
    headers: Map([("X-Request-Id", " \t ")]),
    body: "",
  })
  assert_eq(response.headers.get("X-Request-Id"), Some("feather-1"))
  assert_eq(response.body, "feather-1")
}

///|
test "request id trims surrounding whitespace from a valid incoming id" {
  let app = @feather.App::new()
    .use(@feather.middleware_request_id())
    .get("/id", fn(ctx) { ctx.text(200, ctx.request_id()) })
  let response = app.respond({
    method: "GET",
    path: "/id",
    headers: Map([("X-Request-Id", "  trace-1  ")]),
    body: "",
  })
  assert_eq(response.headers.get("X-Request-Id"), Some("trace-1"))
  assert_eq(response.body, "trace-1")
}
