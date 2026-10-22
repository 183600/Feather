///|
fn compression_override_headers() -> Map[@http.CaseInsensitiveString, String] {
  Map([(@http.CaseInsensitiveString("Accept-Encoding"), "gzip")])
}

///|
async test "context compress opts a response in when app compression is off" {
  let body = "feather ".repeat(200)
  let app = @feather.App::new().get("/big", fn(ctx) {
    ctx.compress()
    ctx.text(200, body)
  })
  let response = app.respond_async({
    method: "GET",
    path: "/big",
    headers: Map([("Accept-Encoding", "gzip")]),
    body: "",
  })
  assert_eq(response.headers.get("Content-Encoding"), Some("gzip"))
  assert_eq(response.headers.get("Vary"), Some("Accept-Encoding"))
  assert_eq(decode_gzip(response.data.unwrap()), @utf8.encode(body))
}

///|
async test "context no_compress opts a response out of app compression" {
  let body = "feather ".repeat(200)
  let app = @feather.App::new()
    .compress(min_size=0)
    .get("/plain", fn(ctx) {
      ctx.no_compress()
      ctx.text(200, body)
    })
  let response = app.respond_async({
    method: "GET",
    path: "/plain",
    headers: Map([("Accept-Encoding", "gzip")]),
    body: "",
  })
  assert_eq(response.headers.get("Content-Encoding"), None)
  assert_eq(response.headers.get("Vary"), None)
  assert_eq(response.body, body)
}

///|
async test "context compress applies its own minimum size" {
  let app = @feather.App::new().get("/small", fn(ctx) {
    ctx.compress(min_size=4096)
    ctx.text(200, "tiny body")
  })
  let response = app.respond_async({
    method: "GET",
    path: "/small",
    headers: Map([("Accept-Encoding", "gzip")]),
    body: "",
  })
  assert_eq(response.headers.get("Content-Encoding"), None)
  assert_eq(response.headers.get("Vary"), Some("Accept-Encoding"))
  assert_eq(response.body, "tiny body")
}

///|
async test "context compress accepts the full Int32 threshold range" {
  let body = "feather ".repeat(200)
  let app = @feather.App::new().get("/large-threshold", fn(ctx) {
    ctx.compress(min_size=200_000_000)
    ctx.text(200, body)
  })
  let response = app.respond_async({
    method: "GET",
    path: "/large-threshold",
    headers: Map([("Accept-Encoding", "gzip")]),
    body: "",
  })
  assert_eq(response.headers.get("Content-Encoding"), None)
  assert_eq(response.headers.get("Vary"), Some("Accept-Encoding"))
  assert_eq(response.body, body)
}

///|
async test "context compress still negotiates the accepted encoding" {
  let body = "feather ".repeat(200)
  let app = @feather.App::new().get("/big", fn(ctx) {
    ctx.compress()
    ctx.text(200, body)
  })
  let response = app.respond_async({
    method: "GET",
    path: "/big",
    headers: Map([("Accept-Encoding", "identity")]),
    body: "",
  })
  assert_eq(response.headers.get("Content-Encoding"), None)
  assert_eq(response.headers.get("Vary"), Some("Accept-Encoding"))
  assert_eq(response.body, body)
}

///|
async test "server honors per-response compression overrides" {
  let body = "feather ".repeat(200)
  let opt_in = @feather.App::new().get("/in", fn(ctx) {
    ctx.compress()
    ctx.text(200, body)
  })
  with_server(opt_in, client => {
    let response = client.get(
      "/in",
      extra_headers=compression_override_headers(),
    )
    assert_eq(response.code, 200)
    assert_eq(
      response.headers.get(@http.CaseInsensitiveString("Content-Encoding")),
      Some("gzip"),
    )
    assert_eq(decode_gzip(client.read_all().binary()), @utf8.encode(body))
  })
  let opt_out = @feather.App::new()
    .compress(min_size=0)
    .get("/out", fn(ctx) {
      ctx.no_compress()
      ctx.text(200, body)
    })
  with_server(opt_out, client => {
    let response = client.get(
      "/out",
      extra_headers=compression_override_headers(),
    )
    assert_eq(response.code, 200)
    assert_eq(
      response.headers.get(@http.CaseInsensitiveString("Content-Encoding")),
      None,
    )
    assert_eq(response.headers.get(@http.CaseInsensitiveString("Vary")), None)
    assert_eq(client.read_all().text(), body)
  })
}
