///|
test "method override recognizes a lower-case post method" {
  let app = @feather.App::new()
    .use(@feather.middleware_method_override())
    .delete("/items/1", fn(ctx) { ctx.text(200, "deleted") })
  let response = app.respond({
    method: "post",
    path: "/items/1",
    headers: Map([("X-HTTP-Method-Override", "DELETE")]),
    body: "",
  })
  assert_eq(response.status, 200)
  assert_eq(response.body, "deleted")
}

///|
test "cors recognizes a lower-case options preflight" {
  let app = @feather.App::new()
    .use(
      @feather.middleware_cors(
        allow_origin="https://example.com",
        allow_methods="GET, POST",
      ),
    )
    .get("/x", fn(ctx) { ctx.text(200, "ok") })
  let ctx = @feather.Context::new({
    method: "options",
    path: "/x",
    headers: Map([
      ("Origin", "https://example.com"),
      ("Access-Control-Request-Method", "GET"),
    ]),
    body: "",
  })
  app.handle(ctx)
  assert_eq(ctx.response.status, 204)
  assert_eq(
    ctx.response.headers.get("Access-Control-Allow-Origin"),
    Some("https://example.com"),
  )
  assert_eq(
    ctx.response.headers.get("Access-Control-Allow-Methods"),
    Some("GET, POST"),
  )
}
