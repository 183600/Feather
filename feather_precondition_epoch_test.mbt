///|
fn epoch_modified_app() -> @feather.App {
  @feather.App::new().get("/x", fn(ctx) {
    ctx.set_header("Last-Modified", "Thu, 01 Jan 1970 00:00:00 GMT")
    ctx.text(200, "hello")
  })
}

///|
test "an epoch last-modified is a real if-modified-since validator" {
  let app = epoch_modified_app()
  let response = app.respond({
    method: "GET",
    path: "/x",
    headers: Map([("If-Modified-Since", "Fri, 01 Jan 1971 00:00:00 GMT")]),
    body: "",
  })
  assert_eq(response.status, 304)
  assert_eq(response.body, "")
}

///|
test "an epoch last-modified participates in if-unmodified-since" {
  let app = epoch_modified_app()
  let stale = app.respond({
    method: "GET",
    path: "/x",
    headers: Map([("If-Unmodified-Since", "Wed, 31 Dec 1969 00:00:00 GMT")]),
    body: "",
  })
  assert_eq(stale.status, 412)
  assert_eq(stale.body, "412 Precondition Failed")
  let fresh = app.respond({
    method: "GET",
    path: "/x",
    headers: Map([("If-Unmodified-Since", "Thu, 01 Jan 1970 00:00:00 GMT")]),
    body: "",
  })
  assert_eq(fresh.status, 200)
  assert_eq(fresh.body, "hello")
}

///|
test "a missing last-modified still ignores date preconditions" {
  let app = @feather.App::new().get("/x", fn(ctx) { ctx.text(200, "hello") })
  let response = app.respond({
    method: "GET",
    path: "/x",
    headers: Map([("If-Modified-Since", "Fri, 01 Jan 1971 00:00:00 GMT")]),
    body: "",
  })
  assert_eq(response.status, 200)
  assert_eq(response.body, "hello")
}
