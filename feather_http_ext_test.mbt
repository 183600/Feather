///|
fn language_ctx(accept : String) -> @feather.Context {
  @feather.Context::new({
    method: "GET",
    path: "/",
    headers: if accept == "" {
      Map([])
    } else {
      Map([("Accept-Language", accept)])
    },
    body: "",
  })
}

///|
test "accepts_language treats a missing header as accepting everything" {
  assert_true(language_ctx("").accepts_language("en"))
  assert_true(language_ctx("").accepts_language("zh-Hans"))
}

///|
test "accepts_language matches exact tags and prefixes" {
  assert_true(language_ctx("en-US").accepts_language("en-US"))
  assert_true(language_ctx("EN-us").accepts_language("en-US"))
  assert_true(language_ctx("en").accepts_language("en-US"))
  assert_false(language_ctx("en-US").accepts_language("en"))
  assert_false(language_ctx("zh").accepts_language("en-US"))
  assert_true(language_ctx("zh-Hans").accepts_language("zh-Hans-CN"))
}

///|
test "accepts_language honors quality values and wildcards" {
  assert_false(language_ctx("en;q=0").accepts_language("en"))
  assert_true(language_ctx("en;q=0.001").accepts_language("en"))
  assert_true(language_ctx("*").accepts_language("fr"))
  assert_false(language_ctx("*;q=0").accepts_language("fr"))
  assert_false(language_ctx("en-US").accepts_language("fr"))
}

///|
test "accepts_language lets the most specific range win" {
  let header = "en;q=0, en-US"
  assert_true(language_ctx(header).accepts_language("en-US"))
  assert_false(language_ctx(header).accepts_language("en-GB"))
}

///|
test "preferred_language picks the best offer" {
  let ctx = language_ctx("fr;q=0.8, en;q=0.9")
  assert_eq(ctx.preferred_language(["fr", "en"]), Some("en"))
  assert_eq(ctx.preferred_language(["en-US"]), Some("en-US"))
  assert_eq(ctx.preferred_language(["de"]), None)
  assert_eq(language_ctx("").preferred_language(["de", "en"]), Some("de"))
}

///|
test "preferred_language keeps server order on quality ties" {
  let ctx = language_ctx("*")
  assert_eq(ctx.preferred_language(["de", "en"]), Some("de"))
  let specific = language_ctx("en, fr")
  assert_eq(specific.preferred_language(["fr", "en"]), Some("fr"))
  assert_eq(specific.preferred_language([]), None)
}

///|
test "multipart prefers the RFC 8187 filename* parameter" {
  let body = "--B\r\n" +
    "Content-Disposition: form-data; name=\"file\"; " +
    "filename=\"fallback.txt\"; filename*=UTF-8''%E6%8A%A5%E5%91%8A.txt\r\n" +
    "Content-Type: text/plain\r\n\r\n" +
    "hi\r\n--B--\r\n"
  let parts = @feather.parse_multipart(body, "multipart/form-data; boundary=B")
  match parts {
    Some(parts) => {
      assert_eq(parts.length(), 1)
      assert_eq(parts[0].filename, "报告.txt")
      assert_eq(parts[0].name, "file")
      assert_eq(parts[0].data, "hi")
    }
    None => fail("expected multipart parts")
  }
}

///|
test "multipart accepts filename* without a plain filename" {
  let body = "--B\r\n" +
    "Content-Disposition: form-data; name=\"file\"; " +
    "filename*=UTF-8''caf%C3%A9.txt\r\n\r\n" +
    "x\r\n--B--\r\n"
  let parts = @feather.parse_multipart(body, "multipart/form-data; boundary=B")
  match parts {
    Some(parts) => assert_eq(parts[0].filename, "café.txt")
    None => fail("expected multipart parts")
  }
}

///|
test "multipart ignores filename* with an unsupported charset" {
  let body = "--B\r\n" +
    "Content-Disposition: form-data; name=\"file\"; " +
    "filename=\"plain.txt\"; filename*=ISO-8859-1''caf%E9.txt\r\n\r\n" +
    "x\r\n--B--\r\n"
  let parts = @feather.parse_multipart(body, "multipart/form-data; boundary=B")
  match parts {
    Some(parts) => assert_eq(parts[0].filename, "plain.txt")
    None => fail("expected multipart parts")
  }
  let only_ext = "--B\r\n" +
    "Content-Disposition: form-data; name=\"file\"; " +
    "filename*=ISO-8859-1''caf%E9.txt\r\n\r\n" +
    "x\r\n--B--\r\n"
  let parts = @feather.parse_multipart(
    only_ext, "multipart/form-data; boundary=B",
  )
  match parts {
    Some(parts) => assert_eq(parts[0].filename, "")
    None => fail("expected multipart parts")
  }
}

///|
test "OPTIONS is answered with the allowed methods" {
  let app = @feather.App::new()
    .get("/res", fn(ctx) { ctx.text(200, "g") })
    .post("/res", fn(ctx) { ctx.text(200, "p") })
  let response = app.respond({
    method: "OPTIONS",
    path: "/res",
    headers: Map([]),
    body: "",
  })
  assert_eq(response.status, 204)
  assert_eq(response.body, "")
  let allow = response.headers.get("Allow").unwrap_or("")
  assert_true(allow.contains("GET"))
  assert_true(allow.contains("HEAD"))
  assert_true(allow.contains("POST"))
}

///|
test "405 responses list HEAD next to GET" {
  let app = @feather.App::new().get("/only", fn(ctx) { ctx.text(200, "g") })
  let response = app.respond({
    method: "DELETE",
    path: "/only",
    headers: Map([]),
    body: "",
  })
  assert_eq(response.status, 405)
  let allow = response.headers.get("Allow").unwrap_or("")
  assert_true(allow.contains("GET"))
  assert_true(allow.contains("HEAD"))
}

///|
test "Allow header lists HEAD between GET and later methods" {
  let app = @feather.App::new()
    .get("/r", fn(ctx) { ctx.text(200, "g") })
    .post("/r", fn(ctx) { ctx.text(200, "p") })
  let response = app.respond({
    method: "DELETE",
    path: "/r",
    headers: Map([]),
    body: "",
  })
  assert_eq(response.status, 405)
  assert_eq(response.headers.get("Allow"), Some("GET, HEAD, POST"))
}

///|
test "Allow header keeps every method separated" {
  let app = @feather.App::new()
    .get("/r", fn(ctx) { ctx.text(200, "g") })
    .put("/r", fn(ctx) { ctx.text(200, "p") })
  let response = app.respond({
    method: "DELETE",
    path: "/r",
    headers: Map([]),
    body: "",
  })
  assert_eq(response.status, 405)
  assert_eq(response.headers.get("Allow"), Some("GET, PUT, HEAD"))
}

///|
test "OPTIONS on an unmatched path stays 404" {
  let app = @feather.App::new().get("/res", fn(ctx) { ctx.text(200, "g") })
  let response = app.respond({
    method: "OPTIONS",
    path: "/missing",
    headers: Map([]),
    body: "",
  })
  assert_eq(response.status, 404)
}

///|
test "OPTIONS still runs an explicitly registered handler" {
  let app = @feather.App::new().options("/res", fn(ctx) {
    ctx.text(200, "custom")
  })
  let response = app.respond({
    method: "OPTIONS",
    path: "/res",
    headers: Map([]),
    body: "",
  })
  assert_eq(response.status, 200)
  assert_eq(response.body, "custom")
}

///|
async fn gzip_encode_for_test(data : Bytes) -> Bytes {
  let reader = @io.MemoryReader(async fn(writer) {
    let encoder = @gzip.Encoder::Encoder(writer)
    encoder.write(data)
    encoder.end()
  })
  defer reader.close()
  reader.read_all().binary()
}

///|
async fn gunzip_for_test(data : Bytes) -> Bytes {
  let reader = @io.MemoryReader(async fn(writer) { writer.write(data) })
  defer reader.close()
  let decoder = @gzip.Decoder::Decoder(reader)
  decoder.read_all().binary()
}

///|
let ext_accept_encoding : @http.CaseInsensitiveString = @http.CaseInsensitiveString(
  "Accept-Encoding",
)

///|
let ext_content_encoding : @http.CaseInsensitiveString = @http.CaseInsensitiveString(
  "Content-Encoding",
)

///|
let ext_vary : @http.CaseInsensitiveString = @http.CaseInsensitiveString("Vary")

///|
async test "static files serve precompressed gzip siblings" {
  let dir = @fs.tmpdir(prefix="feather-precompressed")
  let plain = "console.log(\"hello precompressed world\");\n".repeat(32)
  @fs.write_file(dir + "/app.js", plain)
  let encoded = gzip_encode_for_test(@utf8.encode(plain))
  @fs.write_file(dir + "/app.js.gz", encoded)
  let app = @feather.App::new().static_files("/assets", dir, precompressed=true)
  with_server(app, client => {
    let response = client.get(
      "/assets/app.js",
      extra_headers=Map([(ext_accept_encoding, "gzip")]),
    )
    assert_eq(response.code, 200)
    assert_eq(response.headers.get(ext_content_encoding), Some("gzip"))
    assert_true(
      response.headers.get(ext_vary).unwrap_or("").contains("Accept-Encoding"),
    )
    assert_eq(
      response.headers.get(@http.CaseInsensitiveString("Content-Type")),
      Some("text/javascript; charset=utf-8"),
    )
    let decoded = gunzip_for_test(client.read_all().binary())
    assert_eq(@utf8.decode_lossy(decoded), plain)
    let identity = client.get(
      "/assets/app.js",
      extra_headers=Map([(ext_accept_encoding, "identity")]),
    )
    assert_eq(identity.code, 200)
    assert_eq(identity.headers.get(ext_content_encoding), None)
    assert_true(
      identity.headers.get(ext_vary).unwrap_or("").contains("Accept-Encoding"),
    )
    assert_eq(client.read_all().text(), plain)
  })
  @fs.rmdir(dir, recursive=true)
}

///|
async test "precompressed serving is opt-in per mount" {
  let dir = @fs.tmpdir(prefix="feather-precompressed")
  let plain = "let x = 1;\n"
  @fs.write_file(dir + "/app.js", plain)
  let encoded = gzip_encode_for_test(@utf8.encode(plain))
  @fs.write_file(dir + "/app.js.gz", encoded)
  let app = @feather.App::new().static_files("/assets", dir)
  assert_eq(app.static_file_for("/assets/app.js"), Some(dir + "/app.js"))
  with_server(app, client => {
    let response = client.get(
      "/assets/app.js",
      extra_headers=Map([(ext_accept_encoding, "gzip")]),
    )
    assert_eq(response.code, 200)
    assert_eq(response.headers.get(ext_content_encoding), None)
    assert_eq(client.read_all().text(), plain)
  })
  @fs.rmdir(dir, recursive=true)
}

///|
async test "precompressed static files keep validators and revalidation" {
  let dir = @fs.tmpdir(prefix="feather-precompressed")
  let plain = "body { color: blue; }\n".repeat(64)
  @fs.write_file(dir + "/app.css", plain)
  let encoded = gzip_encode_for_test(@utf8.encode(plain))
  @fs.write_file(dir + "/app.css.gz", encoded)
  let app = @feather.App::new().static_files(
    "/assets",
    dir,
    max_age=60,
    precompressed=true,
  )
  with_server(app, client => {
    let first = client.get(
      "/assets/app.css",
      extra_headers=Map([(ext_accept_encoding, "gzip")]),
    )
    assert_eq(first.code, 200)
    assert_eq(
      first.headers.get(@http.CaseInsensitiveString("Cache-Control")),
      Some("public, max-age=60"),
    )
    let etag = match first.headers.get(@http.CaseInsensitiveString("ETag")) {
      Some(etag) => etag
      None => fail("missing ETag")
    }
    ignore(client.read_all())
    let second = client.get(
      "/assets/app.css",
      extra_headers=Map([
        (ext_accept_encoding, "gzip"),
        (@http.CaseInsensitiveString("If-None-Match"), etag),
      ]),
    )
    assert_eq(second.code, 304)
    assert_eq(second.headers.get(ext_content_encoding), Some("gzip"))
    assert_true(
      second.headers.get(ext_vary).unwrap_or("").contains("Accept-Encoding"),
    )
    ignore(client.read_all())
  })
  @fs.rmdir(dir, recursive=true)
}
