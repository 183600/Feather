///|
async fn decode_gzip_body(data : Bytes) -> Bytes {
  let reader = @io.MemoryReader(async fn(writer) {
    writer.write(data)
  })
  defer reader.close()
  let decoder = @gzip.Decoder::Decoder(reader)
  decoder.read_all().binary()
}

///|
let accept_encoding_key : @http.CaseInsensitiveString = @http.CaseInsensitiveString(
  "Accept-Encoding",
)

///|
let content_encoding_key : @http.CaseInsensitiveString = @http.CaseInsensitiveString(
  "Content-Encoding",
)

///|
let vary_key : @http.CaseInsensitiveString = @http.CaseInsensitiveString("Vary")

///|
test "base64 encodes rfc 4648 vectors" {
  assert_eq(@feather.base64_encode(b""), "")
  assert_eq(@feather.base64_encode(b"f"), "Zg==")
  assert_eq(@feather.base64_encode(b"fo"), "Zm8=")
  assert_eq(@feather.base64_encode(b"foo"), "Zm9v")
  assert_eq(@feather.base64_encode(b"foob"), "Zm9vYg==")
  assert_eq(@feather.base64_encode(b"fooba"), "Zm9vYmE=")
  assert_eq(@feather.base64_encode(b"foobar"), "Zm9vYmFy")
}

///|
test "base64 decodes rfc 4648 vectors" {
  assert_eq(@feather.base64_decode(""), Some(b""))
  assert_eq(@feather.base64_decode("Zg=="), Some(b"f"))
  assert_eq(@feather.base64_decode("Zm8="), Some(b"fo"))
  assert_eq(@feather.base64_decode("Zm9v"), Some(b"foo"))
  assert_eq(@feather.base64_decode("Zm9vYg=="), Some(b"foob"))
  assert_eq(@feather.base64_decode("Zm9vYmE="), Some(b"fooba"))
  assert_eq(@feather.base64_decode("Zm9vYmFy"), Some(b"foobar"))
}

///|
test "base64 accepts unpadded tails" {
  assert_eq(@feather.base64_decode("Zg"), Some(b"f"))
  assert_eq(@feather.base64_decode("Zm8"), Some(b"fo"))
}

///|
test "base64 rejects malformed input" {
  assert_eq(@feather.base64_decode("A"), None)
  assert_eq(@feather.base64_decode("AA=A"), None)
  assert_eq(@feather.base64_decode("AA="), None)
  assert_eq(@feather.base64_decode("A==="), None)
  assert_eq(@feather.base64_decode("AB==C"), None)
  assert_eq(@feather.base64_decode("!!!!"), None)
  assert_eq(@feather.base64_decode("AAA=AAA="), None)
}

///|
test "base64 round trips every byte value" {
  let data : Array[Byte] = []
  for i = 0; i < 256; i = i + 1 {
    data.push(i.to_byte())
  }
  let bytes = Bytes::from_array(data)
  assert_eq(@feather.base64_decode(@feather.base64_encode(bytes)), Some(bytes))
}

///|
async test "server compresses responses for gzip clients" {
  let payload = "feather compression payload ".repeat(128)
  let app = @feather.App::new().compress(min_size=16).get("/big", fn(ctx) {
    ctx.text(200, payload)
  })
  with_server(app, client => {
    let response = client.get(
      "/big",
      extra_headers=Map([(accept_encoding_key, "gzip")]),
    )
    assert_eq(response.code, 200)
    assert_eq(response.headers.get(content_encoding_key), Some("gzip"))
    assert_eq(response.headers.get(vary_key), Some("Accept-Encoding"))
    let compressed_length = client.read_all().binary().length()
    assert_true(compressed_length > 0)
    assert_true(compressed_length < @utf8.encode(payload).length())
  })
  with_server(app, client => {
    let response = client.get(
      "/big",
      extra_headers=Map([(accept_encoding_key, "gzip")]),
    )
    assert_eq(response.code, 200)
    let decoded = decode_gzip_body(client.read_all().binary())
    assert_eq(@utf8.decode_lossy(decoded), payload)
  })
}

///|
async test "server compresses json responses" {
  let app = @feather.App::new().compress(min_size=16).get("/json", fn(ctx) {
    ctx.json_value(200, Json::object({ "data": Json::string("v".repeat(512)) }))
  })
  with_server(app, client => {
    let response = client.get(
      "/json",
      extra_headers=Map([(accept_encoding_key, "gzip")]),
    )
    assert_eq(response.code, 200)
    assert_eq(response.headers.get(content_encoding_key), Some("gzip"))
    let decoded = decode_gzip_body(client.read_all().binary())
    assert_eq(
      @utf8.decode_lossy(decoded),
      "{\"data\":\"" + "v".repeat(512) + "\"}",
    )
  })
}

///|
async test "server leaves bodies plain for identity clients" {
  let payload = "plain body ".repeat(128)
  let app = @feather.App::new().compress(min_size=16).get("/big", fn(ctx) {
    ctx.text(200, payload)
  })
  with_server(app, client => {
    let response = client.get(
      "/big",
      extra_headers=Map([(accept_encoding_key, "identity")]),
    )
    assert_eq(response.code, 200)
    assert_eq(response.headers.get(content_encoding_key), None)
    assert_eq(response.headers.get(vary_key), Some("Accept-Encoding"))
    assert_eq(client.read_all().text(), payload)
  })
}

///|
async test "server honors gzip rejection quality value" {
  let app = @feather.App::new().compress(min_size=16).get("/big", fn(ctx) {
    ctx.text(200, "body ".repeat(128))
  })
  with_server(app, client => {
    let response = client.get(
      "/big",
      extra_headers=Map([(accept_encoding_key, "gzip;q=0")]),
    )
    assert_eq(response.code, 200)
    assert_eq(response.headers.get(content_encoding_key), None)
    assert_eq(client.read_all().text(), "body ".repeat(128))
  })
}

///|
async test "server skips compression below the configured size" {
  let app = @feather.App::new().compress(min_size=4096).get("/small", fn(ctx) {
    ctx.text(200, "tiny body")
  })
  with_server(app, client => {
    let response = client.get(
      "/small",
      extra_headers=Map([(accept_encoding_key, "gzip")]),
    )
    assert_eq(response.code, 200)
    assert_eq(response.headers.get(content_encoding_key), None)
    assert_eq(response.headers.get(vary_key), Some("Accept-Encoding"))
    assert_eq(client.read_all().text(), "tiny body")
  })
}

///|
async test "server skips compression for binary content types" {
  let binary = Bytes::from_fixedarray(
    FixedArray::make(768, b'\x07'),
    len=768,
  )
  let app = @feather.App::new().compress(min_size=1).get("/bin", fn(ctx) {
    ctx.bytes(200, binary)
  })
  with_server(app, client => {
    let response = client.get(
      "/bin",
      extra_headers=Map([(accept_encoding_key, "gzip")]),
    )
    assert_eq(response.code, 200)
    assert_eq(response.headers.get(content_encoding_key), None)
    assert_eq(response.headers.get(vary_key), None)
    assert_eq(client.read_all().binary().length(), 768)
  })
}

///|
async test "server does not compress when disabled" {
  let payload = "uncompressed ".repeat(128)
  let app = @feather.App::new().get("/plain", fn(ctx) {
    ctx.text(200, payload)
  })
  with_server(app, client => {
    let response = client.get(
      "/plain",
      extra_headers=Map([(accept_encoding_key, "gzip")]),
    )
    assert_eq(response.code, 200)
    assert_eq(response.headers.get(content_encoding_key), None)
    assert_eq(response.headers.get(vary_key), None)
    assert_eq(client.read_all().text(), payload)
  })
}

///|
async test "feather facade can enable compression" {
  let payload = "facade compression ".repeat(128)
  let feather = @feather.create_feather({
    host: "127.0.0.1",
    port: 0,
    timeout: 0,
  }).compress(min_size=16).get("/big", fn(ctx) { ctx.text(200, payload) })
  with_server(feather.app, client => {
    let response = client.get(
      "/big",
      extra_headers=Map([(accept_encoding_key, "gzip")]),
    )
    assert_eq(response.code, 200)
    assert_eq(response.headers.get(content_encoding_key), Some("gzip"))
    let decoded = decode_gzip_body(client.read_all().binary())
    assert_eq(@utf8.decode_lossy(decoded), payload)
  })
}
