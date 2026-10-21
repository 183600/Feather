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
