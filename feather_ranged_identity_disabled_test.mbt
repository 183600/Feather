///|
fn ranged_identity_request() -> @feather.Request {
  {
    method: "GET",
    path: "/part",
    headers: Map([("Accept-Encoding", "gzip, identity;q=0")]),
    body: "",
  }
}

///|
async test "ranged responses reject identity without app compression" {
  let app = @feather.App::new().get("/part", fn(ctx) {
    ctx.text(206, "0123")
    ctx.set_header("Content-Range", "bytes 0-3/10")
  })
  let response = app.respond_async(ranged_identity_request())
  assert_eq(response.status, 406)
  assert_eq(response.body, "406 Not Acceptable")
  assert_eq(response.headers.get("Content-Range"), None)
  assert_eq(response.headers.get("Content-Encoding"), None)
  assert_eq(response.headers.get("Vary"), Some("Accept-Encoding"))
}

///|
test "offline ranged responses reject identity without app compression" {
  let app = @feather.App::new().get("/part", fn(ctx) {
    ctx.text(206, "0123")
    ctx.set_header("Content-Range", "bytes 0-3/10")
  })
  let response = app.respond(ranged_identity_request())
  assert_eq(response.status, 406)
  assert_eq(response.body, "406 Not Acceptable")
  assert_eq(response.headers.get("Content-Range"), None)
  assert_eq(response.headers.get("Vary"), Some("Accept-Encoding"))
}
