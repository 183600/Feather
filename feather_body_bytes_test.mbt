///|
test "body_bytes returns the utf8 encoding of a text body" {
  let ctx = @feather.Context::new({
    method: "POST",
    path: "/",
    headers: Map([]),
    body: "héllo 世界",
  })
  assert_eq(ctx.body_bytes(), @utf8.encode("héllo 世界"))
}

///|
test "body_bytes is empty when the request has no body" {
  let ctx = @feather.Context::new({
    method: "GET",
    path: "/",
    headers: Map([]),
    body: "",
  })
  assert_eq(ctx.body_bytes(), b"")
}

///|
test "body_bytes replaces lone surrogates instead of aborting" {
  let lone_high = String::from_array([Char::from_int(0xD800)])
  let lone_low = String::from_array([Char::from_int(0xDC00)])
  let pair = String::from_array([
    Char::from_int(0xD83D), Char::from_int(0xDE00),
  ])
  let ctx = @feather.Context::new({
    method: "POST",
    path: "/",
    headers: Map([]),
    body: "A" + lone_high + "B" + lone_low + "C" + pair,
  })
  assert_eq(ctx.body_bytes(), @utf8.encode("A\u{FFFD}B\u{FFFD}C" + pair))
}

///|
async test "server reads a binary request body byte for byte" {
  let payload : Bytes = b"\x00\xff\xfe\x80\xc3\x28\x10\x7fAB"
  let app = @feather.App::new().post("/upload", fn(ctx) {
    let bytes = ctx.body_bytes()
    // Encoding the lossy text must not panic: `Request::body` only ever
    // holds well-formed text, even for a body of arbitrary bytes.
    let text = @utf8.encode(ctx.request.body)
    ctx.text(200, "\{bytes == payload}:\{text.length() > 0}")
  })
  with_server(app, client => {
    let response = client.post("/upload", payload)
    assert_eq(response.code, 200)
    assert_eq(client.read_all().text(), "true:true")
  })
}

///|
async test "server body_bytes matches the text body of a utf8 request" {
  let app = @feather.App::new().post("/echo", fn(ctx) {
    let bytes_ok = ctx.body_bytes() == @utf8.encode("héllo 世界")
    let text_ok = ctx.request.body == "héllo 世界"
    ctx.text(200, "\{bytes_ok}:\{text_ok}")
  })
  with_server(app, client => {
    let response = client.post("/echo", "héllo 世界")
    assert_eq(response.code, 200)
    assert_eq(client.read_all().text(), "true:true")
  })
}

///|
async test "server body_bytes is empty for a request without a body" {
  let app = @feather.App::new().get("/ping", fn(ctx) {
    ctx.text(200, "len=\{ctx.body_bytes().length()}")
  })
  with_server(app, client => {
    let response = client.get("/ping")
    assert_eq(response.code, 200)
    assert_eq(client.read_all().text(), "len=0")
  })
}

///|
async test "server body_bytes sees through a gzip encoded binary body" {
  let payload : Bytes = b"\xff\xfe\x00binary\xff\x7f"
  let compressed = gzip_encode_for_test(payload)
  let app = @feather.App::new().post("/upload", fn(ctx) {
    ctx.text(200, if ctx.body_bytes() == payload { "equal" } else { "diff" })
  })
  with_server(app, client => {
    let response = client.post(
      "/upload",
      compressed,
      extra_headers=Map([
        (@http.CaseInsensitiveString("Content-Encoding"), "gzip"),
      ]),
    )
    assert_eq(response.code, 200)
    assert_eq(client.read_all().text(), "equal")
  })
}

///|
async test "server body_bytes decodes gzip in a content-encoding list" {
  let payload : Bytes = b"list gzip\xff\x00body"
  let compressed = gzip_encode_for_test(payload)
  let app = @feather.App::new().post("/upload", fn(ctx) {
    ctx.text(200, if ctx.body_bytes() == payload { "equal" } else { "diff" })
  })
  with_server(app, client => {
    let response = client.post(
      "/upload",
      compressed,
      extra_headers=Map([
        (@http.CaseInsensitiveString("Content-Encoding"), "gzip, identity"),
      ]),
    )
    assert_eq(response.code, 200)
    assert_eq(client.read_all().text(), "equal")
  })
}

///|
/// Build a multipart body from a raw byte payload (binary parts included).
fn binary_multipart_body(payload : Bytes) -> Bytes {
  let head = @utf8.encode(
    "--B\r\nContent-Disposition: form-data; name=\"file\"; filename=\"a.bin\"\r\nContent-Type: application/octet-stream\r\n\r\n",
  )
  let tail = @utf8.encode("\r\n--B--\r\n")
  let out = @buffer.Buffer::Buffer(
    size_hint=head.length() + payload.length() + tail.length(),
  )
  out.write_bytes(head)
  out.write_bytes(payload)
  out.write_bytes(tail)
  out.to_bytes()
}

///|
async test "server exposes exact bytes of a binary multipart upload" {
  let payload : Bytes = b"\x00\xff\xfe\x80header\x7f\xffPNG"
  let app = @feather.App::new().post("/upload", fn(ctx) {
    let file = ctx.multipart_file("file").unwrap()
    ctx.text(200, if file.data_bytes == payload { "exact" } else { "lossy" })
  })
  with_server(app, client => {
    let response = client.post(
      "/upload",
      binary_multipart_body(payload),
      extra_headers=Map([
        (
          @http.CaseInsensitiveString("Content-Type"),
          "multipart/form-data; boundary=B",
        ),
      ]),
    )
    assert_eq(response.code, 200)
    assert_eq(client.read_all().text(), "exact")
  })
}

///|
async test "server keeps data_bytes aligned with data for text parts" {
  let payload : Bytes = @utf8.encode("héllo 世界")
  let app = @feather.App::new().post("/upload", fn(ctx) {
    let file = ctx.multipart_file("file").unwrap()
    ctx.text(
      200,
      "\{file.data_bytes == @utf8.encode(file.data)}:\{file.data == "héllo 世界"}",
    )
  })
  with_server(app, client => {
    let response = client.post(
      "/upload",
      binary_multipart_body(payload),
      extra_headers=Map([
        (
          @http.CaseInsensitiveString("Content-Type"),
          "multipart/form-data; boundary=B",
        ),
      ]),
    )
    assert_eq(response.code, 200)
    assert_eq(client.read_all().text(), "true:true")
  })
}
