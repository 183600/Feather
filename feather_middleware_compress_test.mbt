///|
fn middleware_compress_request(path : String, encoding : String) -> @feather.Request {
  {
    method: "GET",
    path,
    headers: Map([("Accept-Encoding", encoding)]),
    body: "",
  }
}

///|
async test "compress middleware makes only its scope compressible" {
  let body = "feather ".repeat(200)
  let app = @feather.App::new()
    .use_prefix("/api", @feather.middleware_compress(min_size=0))
    .get("/api/big", fn(ctx) { ctx.text(200, body) })
    .get("/plain/big", fn(ctx) { ctx.text(200, body) })
  let compressed = app.respond_async(
    middleware_compress_request("/api/big", "gzip"),
  )
  assert_eq(compressed.headers.get("Content-Encoding"), Some("gzip"))
  assert_eq(compressed.headers.get("Vary"), Some("Accept-Encoding"))
  assert_eq(decode_gzip(compressed.data.unwrap()), @utf8.encode(body))
  let plain = app.respond_async(
    middleware_compress_request("/plain/big", "gzip"),
  )
  assert_eq(plain.headers.get("Content-Encoding"), None)
  assert_eq(plain.headers.get("Vary"), None)
  assert_eq(plain.body, body)
}

///|
async test "compress middleware threshold and negotiation are honored" {
  let body = "feather ".repeat(200)
  let app = @feather.App::new()
    .use(
      @feather.middleware_compress(min_size=4096),
    )
    .get("/small-threshold", fn(ctx) { ctx.text(200, body) })
  let below = app.respond_async(
    middleware_compress_request("/small-threshold", "gzip"),
  )
  assert_eq(below.headers.get("Content-Encoding"), None)
  assert_eq(below.headers.get("Vary"), Some("Accept-Encoding"))
  assert_eq(below.body, body)
  let identity = app.respond_async(
    middleware_compress_request("/small-threshold", "identity"),
  )
  assert_eq(identity.headers.get("Content-Encoding"), None)
  assert_eq(identity.body, body)
}

///|
async test "compress middleware leaves a handler opt out intact" {
  let body = "feather ".repeat(200)
  let app = @feather.App::new()
    .use(@feather.middleware_compress(min_size=0))
    .get("/opted-out", fn(ctx) {
      ctx.no_compress()
      ctx.text(200, body)
    })
  let response = app.respond_async(
    middleware_compress_request("/opted-out", "gzip"),
  )
  assert_eq(response.headers.get("Content-Encoding"), None)
  assert_eq(response.headers.get("Vary"), None)
  assert_eq(response.body, body)
}

///|
async test "compress middleware works on a single route" {
  let body = "feather ".repeat(200)
  let app = @feather.App::new()
    .route_with(
      "GET",
      "/cached",
      [@feather.middleware_compress(min_size=0)],
      fn(ctx) { ctx.text(200, body) },
    )
    .get("/plain", fn(ctx) { ctx.text(200, body) })
  let compressed = app.respond_async(
    middleware_compress_request("/cached", "gzip"),
  )
  assert_eq(compressed.headers.get("Content-Encoding"), Some("gzip"))
  let plain = app.respond_async(middleware_compress_request("/plain", "gzip"))
  assert_eq(plain.headers.get("Content-Encoding"), None)
}
