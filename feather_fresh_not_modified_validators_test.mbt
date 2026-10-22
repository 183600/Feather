///|
fn conditional_request(path : String, headers : Map[String, String]) -> @feather.Request {
  { method: "GET", path, headers, body: "", }
}

///|
test "fresh remembers the etag for a bare not_modified" {
  let app = @feather.App::new().get("/items/7", fn(ctx) {
    let etag = "\"v1\""
    if ctx.fresh(etag) {
      ctx.not_modified()
    } else {
      ctx.set_header("ETag", etag)
      ctx.text(200, "item")
    }
  })
  let cached = app.respond(
    conditional_request("/items/7", Map([("If-None-Match", "\"v1\"")])),
  )
  assert_eq(cached.status, 304)
  assert_eq(cached.body, "")
  assert_eq(cached.headers.get("ETag"), Some("\"v1\""))
}

///|
test "fresh remembers the last-modified date for a bare not_modified" {
  let app = @feather.App::new().get("/page", fn(ctx) {
    let stamp = "Thu, 01 Jan 1970 00:00:00 GMT"
    if ctx.fresh("", last_modified=stamp) {
      ctx.not_modified()
    } else {
      ctx.set_header("Last-Modified", stamp)
      ctx.text(200, "page")
    }
  })
  let cached = app.respond(
    conditional_request(
      "/page",
      Map([("If-Modified-Since", "Thu, 01 Jan 1970 00:00:00 GMT")]),
    ),
  )
  assert_eq(cached.status, 304)
  assert_eq(
    cached.headers.get("Last-Modified"),
    Some("Thu, 01 Jan 1970 00:00:00 GMT"),
  )
}

///|
test "fresh does not leave a stale remembered validator" {
  let ctx = @feather.Context::new(
    conditional_request("/items/7", Map([("If-None-Match", "\"other\"")])),
  )
  assert_false(ctx.fresh("\"v1\""))
  ctx.not_modified()
  assert_eq(ctx.response.status, 304)
  assert_eq(ctx.response.headers.get("ETag"), None)
}
