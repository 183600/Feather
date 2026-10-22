///|
async test "dynamic responses reject identity when compression is disabled" {
  let app = @feather.App::new().get("/text", fn(ctx) {
    ctx.text(200, "hello")
  })
  let response = app.respond_async({
    method: "GET",
    path: "/text",
    headers: Map([("Accept-Encoding", "identity;q=0")]),
    body: "",
  })
  assert_eq(response.status, 406)
  assert_eq(response.body, "406 Not Acceptable")
  assert_eq(response.headers.get("Content-Encoding"), None)
  assert_eq(response.headers.get("Vary"), Some("Accept-Encoding"))
}

///|
test "offline dynamic responses reject identity when compression is disabled" {
  let app = @feather.App::new().get("/text", fn(ctx) {
    ctx.text(200, "hello")
  })
  let response = app.respond({
    method: "GET",
    path: "/text",
    headers: Map([("Accept-Encoding", "identity;q=0")]),
    body: "",
  })
  assert_eq(response.status, 406)
  assert_eq(response.body, "406 Not Acceptable")
  assert_eq(response.headers.get("Vary"), Some("Accept-Encoding"))
}

///|
async test "gzip acceptance without compression still serves identity" {
  let app = @feather.App::new().get("/text", fn(ctx) {
    ctx.text(200, "hello")
  })
  let response = app.respond_async({
    method: "GET",
    path: "/text",
    headers: Map([("Accept-Encoding", "gzip")]),
    body: "",
  })
  assert_eq(response.status, 200)
  assert_eq(response.body, "hello")
  assert_eq(response.headers.get("Content-Encoding"), None)
}
