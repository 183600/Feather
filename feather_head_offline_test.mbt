///|
test "offline respond strips HEAD bodies but keeps their byte length" {
  let app = @feather.App::new()
    .get("/hello", fn(ctx) { ctx.text(200, "héllo") })
    .get("/bytes", fn(ctx) { ctx.bytes(200, b"\x01\x02\x03") })

  let get = app.respond({
    method: "GET",
    path: "/hello",
    headers: Map([]),
    body: "",
  })
  assert_eq(get.body, "héllo")
  assert_eq(get.headers.get("Content-Length"), None)

  let head = app.respond({
    method: "HEAD",
    path: "/hello",
    headers: Map([]),
    body: "",
  })
  assert_eq(head.status, 200)
  assert_eq(head.body, "")
  assert_eq(head.data, None)
  assert_eq(head.headers.get("Content-Length"), Some("6"))

  let head_bytes = app.respond({
    method: "HEAD",
    path: "/bytes",
    headers: Map([]),
    body: "",
  })
  assert_eq(head_bytes.body, "")
  assert_eq(head_bytes.data, None)
  assert_eq(head_bytes.headers.get("Content-Length"), Some("3"))
}

///|
test "offline respond drops seeded lengths on HEAD statuses without bodies" {
  let app = @feather.App::new().get("/gone", fn(ctx) {
    ctx.no_content()
    ctx.set_header("Content-Length", "9")
  })
  let head = app.respond({
    method: "HEAD",
    path: "/gone",
    headers: Map([]),
    body: "",
  })
  assert_eq(head.status, 204)
  assert_eq(head.body, "")
  assert_eq(head.data, None)
  assert_eq(head.headers.get("Content-Length"), None)
}

///|
test "offline HEAD falls back to the GET route" {
  let app = @feather.App::new()
    .get("/only-get", fn(ctx) { ctx.text(201, "created") })
  let head = app.respond({
    method: "HEAD",
    path: "/only-get",
    headers: Map([]),
    body: "",
  })
  assert_eq(head.status, 201)
  assert_eq(head.body, "")
  assert_eq(head.headers.get("Content-Length"), Some("7"))
}

///|
test "offline respond strips lowercase head bodies" {
  let app = @feather.App::new().get("/hello", fn(ctx) {
    ctx.text(200, "hello")
  })
  let head = app.respond({
    method: "head",
    path: "/hello",
    headers: Map([]),
    body: "",
  })
  assert_eq(head.status, 200)
  assert_eq(head.body, "")
  assert_eq(head.data, None)
  assert_eq(head.headers.get("Content-Length"), Some("5"))
}

///|
async test "offline respond_async strips mixed-case head bodies" {
  let payload = "feather ".repeat(200)
  let app = @feather.App::new()
    .compress(min_size=0)
    .get("/big", fn(ctx) { ctx.text(200, payload) })
  let get = app.respond_async({
    method: "GET",
    path: "/big",
    headers: Map([("Accept-Encoding", "gzip")]),
    body: "",
  })
  assert_eq(get.headers.get("Content-Encoding"), Some("gzip"))
  let compressed_length = get.data.unwrap().length()
  let head = app.respond_async({
    method: "Head",
    path: "/big",
    headers: Map([("Accept-Encoding", "gzip")]),
    body: "",
  })
  assert_eq(head.status, 200)
  assert_eq(head.body, "")
  assert_eq(head.data, None)
  assert_eq(head.headers.get("Content-Encoding"), Some("gzip"))
  assert_eq(
    head.headers.get("Content-Length"),
    Some(compressed_length.to_string()),
  )
}

///|
async test "offline respond_async strips compressed HEAD bodies" {
  let payload = "feather ".repeat(200)
  let app = @feather.App::new()
    .compress(min_size=0)
    .get("/big", fn(ctx) { ctx.text(200, payload) })
  let get = app.respond_async({
    method: "GET",
    path: "/big",
    headers: Map([("Accept-Encoding", "gzip")]),
    body: "",
  })
  assert_eq(get.headers.get("Content-Encoding"), Some("gzip"))
  let compressed_length = get.data.unwrap().length()
  let head = app.respond_async({
    method: "HEAD",
    path: "/big",
    headers: Map([("Accept-Encoding", "gzip")]),
    body: "",
  })
  assert_eq(head.status, 200)
  assert_eq(head.body, "")
  assert_eq(head.data, None)
  assert_eq(head.headers.get("Content-Encoding"), Some("gzip"))
  assert_eq(
    head.headers.get("Content-Length"),
    Some(compressed_length.to_string()),
  )
}
