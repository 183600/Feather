///|
async test "identity refusal compresses below the minimum size" {
  let app = @feather.App::new()
    .compress(min_size=4096)
    .get("/small", fn(ctx) { ctx.text(200, "tiny body") })
  let response = app.respond_async({
    method: "GET",
    path: "/small",
    headers: Map([("Accept-Encoding", "gzip, identity;q=0")]),
    body: "",
  })
  assert_eq(response.status, 200)
  assert_eq(response.headers.get("Content-Encoding"), Some("gzip"))
  assert_true(response.data is Some(_))
}

///|
async test "identity refusal rejects a non-compressible response" {
  let app = @feather.App::new()
    .compress()
    .get("/image", fn(ctx) {
      ctx.bytes(200, b"\x89PNG\r\n\x1a\n", content_type="image/png")
    })
  let response = app.respond_async({
    method: "GET",
    path: "/image",
    headers: Map([("Accept-Encoding", "gzip, identity;q=0")]),
    body: "",
  })
  assert_eq(response.status, 406)
  assert_eq(response.body, "406 Not Acceptable")
  assert_eq(response.headers.get("Content-Encoding"), None)
}
