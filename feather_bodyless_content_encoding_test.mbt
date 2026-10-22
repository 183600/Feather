///|
async test "bodyless statuses ignore handler supplied content codings" {
  let app = @feather.App::new()
    .compress(min_size=0)
    .get("/none", fn(ctx) {
      ctx.status(204)
      ctx.set_header("Content-Type", "text/plain")
      ctx.set_header("Content-Encoding", "gzip")
    })
  let request : @feather.Request = {
    method: "GET",
    path: "/none",
    headers: Map([("Accept-Encoding", "identity")]),
    body: "",
  }
  let sync = app.respond(request)
  assert_eq(sync.status, 204)
  assert_eq(sync.body, "")
  assert_eq(sync.headers.get("Content-Encoding"), None)
  assert_eq(sync.headers.get("Content-Type"), None)
  let asynchronous = app.respond_async(request)
  assert_eq(asynchronous.status, 204)
  assert_eq(asynchronous.body, "")
  assert_eq(asynchronous.headers.get("Content-Encoding"), None)
  assert_eq(asynchronous.headers.get("Content-Type"), None)
}
