///|
async test "a client refusing identity is rejected for ranged responses" {
  let app = @feather.App::new().compress(min_size=0).get("/part", fn(ctx) {
    ctx.text(206, "0123")
    ctx.set_header("Content-Range", "bytes 0-3/10")
  })
  let response = app.respond_async({
    method: "GET",
    path: "/part",
    headers: Map([("Accept-Encoding", "gzip, identity;q=0")]),
    body: "",
  })
  assert_eq(response.status, 406)
  assert_eq(response.body, "406 Not Acceptable")
  assert_eq(response.headers.get("Content-Range"), None)
  assert_eq(response.headers.get("Vary"), Some("Accept-Encoding"))
}

///|
async test "ranged responses keep identity for clients that accept it" {
  let app = @feather.App::new().compress(min_size=0).get("/part", fn(ctx) {
    ctx.text(206, "0123")
    ctx.set_header("Content-Range", "bytes 0-3/10")
  })
  let response = app.respond_async({
    method: "GET",
    path: "/part",
    headers: Map([("Accept-Encoding", "gzip")]),
    body: "",
  })
  assert_eq(response.status, 206)
  assert_eq(response.body, "0123")
  assert_eq(response.headers.get("Content-Range"), Some("bytes 0-3/10"))
}
