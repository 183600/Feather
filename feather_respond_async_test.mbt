///|
async fn decode_gzip(data : Bytes) -> Bytes {
  let reader = @io.MemoryReader(async fn(writer) { writer.write(data) })
  defer reader.close()
  let decoder = @gzip.Decoder::Decoder(reader)
  decoder.read_all().binary()
}

///|
fn text_app() -> @feather.App {
  @feather.App::new()
    .compress(min_size=0)
    .get("/big", fn(ctx) { ctx.text(200, "hello ".repeat(100)) })
}

///|
test "the offline facade leaves the response uncompressed" {
  let response = text_app().respond({
    method: "GET",
    path: "/big",
    headers: Map([("Accept-Encoding", "gzip")]),
    body: "",
  })
  assert_eq(response.headers.get("Content-Encoding"), None)
  assert_eq(response.body, "hello ".repeat(100))
}

///|
async test "the async offline facade compresses the response" {
  let response = text_app().respond_async({
    method: "GET",
    path: "/big",
    headers: Map([("Accept-Encoding", "gzip")]),
    body: "",
  })
  assert_eq(response.headers.get("Content-Encoding"), Some("gzip"))
  assert_eq(
    decode_gzip(response.data.unwrap()),
    @utf8.encode("hello ".repeat(100)),
  )
}

///|
async test "the async offline facade keeps the body when gzip is not accepted" {
  let response = text_app().respond_async({
    method: "GET",
    path: "/big",
    headers: Map([("Accept-Encoding", "identity")]),
    body: "",
  })
  assert_eq(response.headers.get("Content-Encoding"), None)
  assert_eq(response.body, "hello ".repeat(100))
}

///|
async test "the async offline facade keeps a body below the compression threshold" {
  let app = @feather.App::new()
    .compress(min_size=4096)
    .get("/small", fn(ctx) { ctx.text(200, "tiny body") })
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
async test "the async offline facade keeps a body when gzip would not help" {
  let app = @feather.App::new()
    .compress(min_size=0)
    .get("/tiny", fn(ctx) { ctx.text(200, "hi") })
  let response = app.respond_async({
    method: "GET",
    path: "/tiny",
    headers: Map([("Accept-Encoding", "gzip")]),
    body: "",
  })
  assert_eq(response.headers.get("Content-Encoding"), None)
  assert_eq(response.headers.get("Vary"), Some("Accept-Encoding"))
  assert_eq(response.body, "hi")
}

///|
async test "the async offline facade advertises encoding negotiation" {
  let response = text_app().respond_async({
    method: "GET",
    path: "/big",
    headers: Map([]),
    body: "",
  })
  assert_eq(response.headers.get("Content-Encoding"), None)
  assert_eq(response.headers.get("Vary"), Some("Accept-Encoding"))
  assert_eq(response.body, "hello ".repeat(100))
}

///|
async test "the async offline facade tags the compressed representation" {
  let app = @feather.App::new()
    .compress(min_size=0)
    .etag()
    .get("/big", fn(ctx) { ctx.text(200, "hello ".repeat(100)) })
  let response = app.respond_async({
    method: "GET",
    path: "/big",
    headers: Map([("Accept-Encoding", "gzip")]),
    body: "",
  })
  let etag = response.headers.get("ETag").unwrap()
  // The tag describes the bytes that are sent, so it is a strong tag of the
  // compressed representation.
  assert_false(etag.has_prefix("W/"))
  let plain = app.respond({
    method: "GET",
    path: "/big",
    headers: Map([("Accept-Encoding", "gzip")]),
    body: "",
  })
  assert_true(plain.headers.get("ETag").unwrap() != etag)
}

///|
async test "the async offline facade answers conditional requests" {
  let app = @feather.App::new()
    .etag()
    .get("/hello", fn(ctx) { ctx.text(200, "hello") })
  let first = app.respond_async({
    method: "GET",
    path: "/hello",
    headers: Map([]),
    body: "",
  })
  let etag = first.headers.get("ETag").unwrap()
  let second = app.respond_async({
    method: "GET",
    path: "/hello",
    headers: Map([("If-None-Match", etag)]),
    body: "",
  })
  assert_eq(second.status, 304)
  assert_eq(second.body, "")
}

///|
test "the offline facade drops hop-by-hop framing headers" {
  let app = @feather.App::new().get("/framed", fn(ctx) {
    ctx.set_header("Transfer-Encoding", "chunked")
    ctx.set_header("Connection", "keep-alive")
    ctx.set_header("Keep-Alive", "timeout=5")
    ctx.text(200, "hi")
  })
  let request : @feather.Request = {
    method: "GET",
    path: "/framed",
    headers: Map([]),
    body: "",
  }
  let response = app.respond(request)
  assert_eq(response.body, "hi")
  assert_eq(response.headers.get("Transfer-Encoding"), None)
  assert_eq(response.headers.get("Connection"), None)
  // `Keep-Alive` is not part of the framework's wire filter, so it survives
  // exactly like it would on a server response.
  assert_eq(response.headers.get("Keep-Alive"), Some("timeout=5"))
}

///|
async test "the async offline facade drops hop-by-hop framing headers" {
  let app = @feather.App::new()
    .compress(min_size=0)
    .get("/framed", fn(ctx) {
      ctx.set_header("Transfer-Encoding", "chunked")
      ctx.set_header("Connection", "close")
      ctx.text(200, "hello ".repeat(100))
    })
  let response = app.respond_async({
    method: "GET",
    path: "/framed",
    headers: Map([("Accept-Encoding", "gzip")]),
    body: "",
  })
  assert_eq(response.headers.get("Content-Encoding"), Some("gzip"))
  assert_eq(response.headers.get("Transfer-Encoding"), None)
  assert_eq(response.headers.get("Connection"), None)
}

///|
async test "the feather facade runs the async pipeline" {
  let config : @feather.Config = {
    host: "localhost",
    port: 3000,
    timeout: 5000,
  }
  let feather = @feather.create_feather(config)
    .compress(min_size=0)
    .get("/big", fn(ctx) { ctx.text(200, "hello ".repeat(100)) })
  let response = feather.handle_async({
    method: "GET",
    path: "/big",
    headers: Map([("Accept-Encoding", "gzip")]),
    body: "",
  })
  assert_eq(response.headers.get("Content-Encoding"), Some("gzip"))
  assert_eq(
    decode_gzip(response.data.unwrap()),
    @utf8.encode("hello ".repeat(100)),
  )
}
