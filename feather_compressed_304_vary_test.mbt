///|
async test "handler-generated 304 varies on accept-encoding when compression is enabled" {
  let etag = "\"v1\""
  let app = @feather.App::new().compress(min_size=0).get("/cached", fn(ctx) {
    if ctx.fresh(etag) {
      ctx.not_modified(etag=etag)
    } else {
      ctx.set_header("ETag", etag)
      ctx.text(200, "cacheable ".repeat(64))
    }
  })
  let response = app.respond_async({
    method: "GET",
    path: "/cached",
    headers: Map([
      ("Accept-Encoding", "gzip"),
      ("If-None-Match", etag),
    ]),
    body: "",
  })
  assert_eq(response.status, 304)
  assert_eq(response.body, "")
  assert_eq(response.headers.get("Vary"), Some("Accept-Encoding"))
}

///|
test "sync facade 304 varies on accept-encoding when compression is enabled" {
  let etag = "\"v1\""
  let app = @feather.App::new().compress(min_size=0).get("/cached", fn(ctx) {
    if ctx.fresh(etag) {
      ctx.not_modified(etag=etag)
    } else {
      ctx.set_header("ETag", etag)
      ctx.text(200, "cacheable ".repeat(64))
    }
  })
  let response = app.respond({
    method: "GET",
    path: "/cached",
    headers: Map([
      ("Accept-Encoding", "gzip"),
      ("If-None-Match", etag),
    ]),
    body: "",
  })
  assert_eq(response.status, 304)
  assert_eq(response.body, "")
  assert_eq(response.headers.get("Vary"), Some("Accept-Encoding"))
}
