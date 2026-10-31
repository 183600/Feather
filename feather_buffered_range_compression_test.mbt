///|
async test "compression leaves buffered ranged responses alone" {
  let app = @feather.App::new().compress(min_size=0).get("/data", fn(ctx) {
    ctx.text(200, "0123456789".repeat(64))
  })
  let response = app.respond_async({
    method: "GET",
    path: "/data",
    headers: Map([("Range", "bytes=4-6"), ("Accept-Encoding", "gzip")]),
    body: "",
  })
  assert_eq(response.status, 206)
  assert_eq(response.headers.get("Content-Encoding"), None)
  assert_eq(response.headers.get("Content-Range"), Some("bytes 4-6/640"))
  assert_eq(response.body, "456")
}

///|
async test "server compression leaves buffered ranged responses alone" {
  let app = @feather.App::new().compress(min_size=0).get("/data", fn(ctx) {
    ctx.text(200, "0123456789".repeat(64))
  })
  with_server(app, client => {
    let response = client.get(
      "/data",
      extra_headers=Map([
        (@http.CaseInsensitiveString("Range"), "bytes=4-6"),
        (@http.CaseInsensitiveString("Accept-Encoding"), "gzip"),
      ]),
    )
    assert_eq(response.code, 206)
    assert_eq(
      response.headers.get(@http.CaseInsensitiveString("Content-Encoding")),
      None,
    )
    assert_eq(
      response.headers.get(@http.CaseInsensitiveString("Content-Range")),
      Some("bytes 4-6/640"),
    )
    assert_eq(client.read_all().text(), "456")
  })
}
