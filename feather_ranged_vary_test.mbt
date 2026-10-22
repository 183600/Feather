///|
async test "ranged identity responses vary even when compression is off" {
  let app = @feather.App::new().get("/part", fn(ctx) {
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
  assert_eq(response.headers.get("Vary"), Some("Accept-Encoding"))
}

///|
async test "ranged identity responses vary when compression is enabled" {
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
  assert_eq(response.headers.get("Vary"), Some("Accept-Encoding"))
}
