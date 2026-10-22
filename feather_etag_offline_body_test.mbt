///|
fn etag_offline_request(headers : Map[String, String]) -> @feather.Request {
  { method: "GET", path: "/text", headers, body: "", }
}

///|
test "offline etag generation keeps a text body in Response.body" {
  let app = @feather.App::new().etag().get("/text", fn(ctx) {
    ctx.text(200, "hello")
  })
  let first = app.respond(etag_offline_request(Map([])))
  assert_eq(first.status, 200)
  assert_eq(first.body, "hello")
  assert_eq(first.data, None)
  let etag = match first.headers.get("ETag") {
    Some(etag) => etag
    None => fail("missing generated ETag")
  }
  let second = app.respond(
    etag_offline_request(Map([("If-None-Match", etag)])),
  )
  assert_eq(second.status, 304)
  assert_eq(second.body, "")
  assert_eq(second.data, None)
  assert_eq(second.headers.get("ETag"), Some(etag))
}

///|
async test "async offline etag generation keeps an identity text body" {
  let app = @feather.App::new().etag().get("/text", fn(ctx) {
    ctx.text(200, "hello")
  })
  let response = app.respond_async(etag_offline_request(Map([])))
  assert_eq(response.status, 200)
  assert_eq(response.body, "hello")
  assert_eq(response.data, None)
  assert_true(response.headers.get("ETag") is Some(_))
}
