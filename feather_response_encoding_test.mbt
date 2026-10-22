///|
fn responsive_lone_surrogate() -> String {
  "ok" + String::from_array([Char::from_int(0xD800)])
}

///|
test "offline facade drops bodies for statuses that forbid them" {
  let app = @feather.App::new()
    .get("/no-content", fn(ctx) { ctx.text(204, "ignored") })
    .get("/reset", fn(ctx) { ctx.text(205, "ignored") })
    .get("/not-modified", fn(ctx) { ctx.text(304, "ignored") })
  for pair in [
    ("/no-content", 204),
    ("/reset", 205),
    ("/not-modified", 304),
  ] {
    let (path, status) = pair
    let response = app.respond({
      method: "GET",
      path,
      headers: Map([]),
      body: "",
    })
    assert_eq(response.status, status)
    assert_eq(response.body, "")
    assert_eq(response.data, None)
    assert_eq(response.headers.get("Content-Length"), None)
  }
}

///|
async test "server writes lone surrogate response text lossily" {
  let expected = "ok\u{FFFD}"
  let app = @feather.App::new().get("/text", fn(ctx) {
    ctx.text(200, responsive_lone_surrogate())
  })
  with_server(app, client => {
    let response = client.get("/text")
    assert_eq(response.code, 200)
    assert_eq(
      response.headers.get(@http.CaseInsensitiveString("Content-Length")),
      Some("5"),
    )
    assert_eq(client.read_all().text(), expected)
  })
}

///|
test "offline HEAD framing counts lone surrogates lossily" {
  let app = @feather.App::new().get("/text", fn(ctx) {
    ctx.text(200, responsive_lone_surrogate())
  })
  let response = app.respond({
    method: "HEAD",
    path: "/text",
    headers: Map([]),
    body: "",
  })
  assert_eq(response.status, 200)
  assert_eq(response.body, "")
  assert_eq(response.data, None)
  assert_eq(response.headers.get("Content-Length"), Some("5"))
}

///|
async test "compressed offline responses accept lone surrogates" {
  let app = @feather.App::new()
    .compress(min_size=0)
    .get("/text", fn(ctx) {
      ctx.text(200, "x".repeat(1000) + responsive_lone_surrogate())
    })
  let response = app.respond_async({
    method: "GET",
    path: "/text",
    headers: Map([("Accept-Encoding", "gzip")]),
    body: "",
  })
  assert_eq(response.headers.get("Content-Encoding"), Some("gzip"))
  assert_true(response.data is Some(_))
}

///|
test "generated ETags accept lone surrogates" {
  let app = @feather.App::new()
    .etag()
    .get("/text", fn(ctx) { ctx.text(200, responsive_lone_surrogate()) })
  let response = app.respond({
    method: "GET",
    path: "/text",
    headers: Map([]),
    body: "",
  })
  assert_eq(response.status, 200)
  assert_true(response.headers.get("ETag") is Some(_))
}

///|
async test "handler supplied encodings honor accept-encoding" {
  let payload = "pre-encoded dynamic payload ".repeat(64)
  let encoded = gzip_encode_for_test(@utf8.encode(payload))
  let app = @feather.App::new().get("/encoded", fn(ctx) {
    ctx.bytes(200, encoded, content_type="text/plain; charset=utf-8")
    ctx.set_header("Content-Encoding", "gzip")
  })
  let accepted = app.respond_async({
    method: "GET",
    path: "/encoded",
    headers: Map([("Accept-Encoding", "gzip")]),
    body: "",
  })
  assert_eq(accepted.status, 200)
  assert_eq(accepted.headers.get("Content-Encoding"), Some("gzip"))
  assert_eq(accepted.headers.get("Vary"), Some("Accept-Encoding"))
  assert_eq(
    @utf8.decode_lossy(gunzip_for_test(accepted.data.unwrap())),
    payload,
  )

  let refused = app.respond_async({
    method: "GET",
    path: "/encoded",
    headers: Map([("Accept-Encoding", "identity")]),
    body: "",
  })
  assert_eq(refused.status, 406)
  assert_eq(refused.headers.get("Content-Encoding"), None)
  assert_eq(refused.headers.get("Vary"), Some("Accept-Encoding"))
  assert_eq(refused.body, "406 Not Acceptable")
}

///|
async test "an explicit identity coding is replaced when gzip is needed" {
  let payload = "identity coded payload ".repeat(64)
  let app = @feather.App::new().compress(min_size=0).get("/identity", fn(ctx) {
    ctx.text(200, payload)
    ctx.set_header("Content-Encoding", "identity")
  })
  let response = app.respond_async({
    method: "GET",
    path: "/identity",
    headers: Map([("Accept-Encoding", "gzip, identity;q=0")]),
    body: "",
  })
  assert_eq(response.status, 200)
  assert_eq(response.headers.get("Content-Encoding"), Some("gzip"))
  assert_eq(response.headers.get("Vary"), Some("Accept-Encoding"))
  assert_eq(
    @utf8.decode_lossy(gunzip_for_test(response.data.unwrap())),
    payload,
  )
}
