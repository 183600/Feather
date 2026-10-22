///|
async test "application compression gzips queued text files" {
  let dir = @fs.tmpdir(prefix="feather-file-compress")
  let payload = "queued file compression payload ".repeat(64)
  @fs.write_file(dir + "/report.txt", payload)
  let app = @feather.App::new()
    .compress(min_size=0)
    .get("/download", fn(ctx) { ctx.file(200, dir + "/report.txt") })
  with_server(app, client => {
    let response = client.get(
      "/download",
      extra_headers=Map([(accept_encoding_key, "gzip")]),
    )
    assert_eq(response.code, 200)
    assert_eq(response.headers.get(content_encoding_key), Some("gzip"))
    assert_true(
      response.headers.get(vary_key).unwrap_or("").contains("Accept-Encoding"),
    )
    let etag = response.headers.get(
      @http.CaseInsensitiveString("ETag"),
    ).unwrap_or("")
    assert_true(etag.has_prefix("W/"))
    let body = client.read_all().binary()
    assert_eq(decode_gzip_body(body), @utf8.encode(payload))
  })
  @fs.rmdir(dir, recursive=true)
}

///|
async test "queued files stay identity for clients that prefer it" {
  let dir = @fs.tmpdir(prefix="feather-file-identity")
  let payload = "identity file compression payload ".repeat(64)
  @fs.write_file(dir + "/report.txt", payload)
  let app = @feather.App::new()
    .compress(min_size=0)
    .get("/download", fn(ctx) { ctx.file(200, dir + "/report.txt") })
  with_server(app, client => {
    let response = client.get(
      "/download",
      extra_headers=Map([(accept_encoding_key, "identity")]),
    )
    assert_eq(response.code, 200)
    assert_eq(response.headers.get(content_encoding_key), None)
    assert_true(
      response.headers.get(vary_key).unwrap_or("").contains("Accept-Encoding"),
    )
    let etag = response.headers.get(
      @http.CaseInsensitiveString("ETag"),
    ).unwrap_or("")
    assert_false(etag.has_prefix("W/"))
    assert_eq(client.read_all().text(), payload)
  })
  @fs.rmdir(dir, recursive=true)
}

///|
async test "queued file compression honors per-response overrides" {
  let dir = @fs.tmpdir(prefix="feather-file-compress-override")
  let payload = "per response compression override ".repeat(64)
  @fs.write_file(dir + "/report.txt", payload)
  let app = @feather.App::new()
    .compress(min_size=0)
    .get("/opt-out", fn(ctx) {
      ctx.no_compress()
      ctx.file(200, dir + "/report.txt")
    })
    .get("/opt-in", fn(ctx) {
      ctx.compress(min_size=0)
      ctx.file(200, dir + "/report.txt")
    })
  with_server(app, client => {
    let opted_out = client.get(
      "/opt-out",
      extra_headers=Map([(accept_encoding_key, "gzip")]),
    )
    assert_eq(opted_out.code, 200)
    assert_eq(opted_out.headers.get(content_encoding_key), None)
    // The same URL answers 406 when identity is refused, so the identity 200
    // must still vary even though this response opted out of compression.
    assert_eq(opted_out.headers.get(vary_key), Some("Accept-Encoding"))
    assert_eq(client.read_all().text(), payload)
    let refused = client.get(
      "/opt-out",
      extra_headers=Map([(accept_encoding_key, "identity;q=0")]),
    )
    assert_eq(refused.code, 406)
    assert_eq(client.read_all().text(), "406 Not Acceptable")
  })
  let plain = @feather.App::new().get("/opt-in", fn(ctx) {
    ctx.compress(min_size=0)
    ctx.file(200, dir + "/report.txt")
  })
  with_server(plain, client => {
    let opted_in = client.get(
      "/opt-in",
      extra_headers=Map([(accept_encoding_key, "gzip")]),
    )
    assert_eq(opted_in.code, 200)
    assert_eq(opted_in.headers.get(content_encoding_key), Some("gzip"))
    assert_eq(decode_gzip_body(client.read_all().binary()), @utf8.encode(payload))
  })
  @fs.rmdir(dir, recursive=true)
}

///|
async test "queued binary files are not compressed" {
  let dir = @fs.tmpdir(prefix="feather-file-compress-binary")
  let data : Array[Byte] = []
  for i = 0; i < 256; i = i + 1 {
    data.push(i.to_byte())
  }
  let bytes = Bytes::from_array(data)
  @fs.write_file(dir + "/asset.bin", bytes)
  let app = @feather.App::new()
    .compress(min_size=0)
    .get("/asset", fn(ctx) { ctx.file(200, dir + "/asset.bin") })
  with_server(app, client => {
    let response = client.get(
      "/asset",
      extra_headers=Map([(accept_encoding_key, "gzip")]),
    )
    assert_eq(response.code, 200)
    assert_eq(response.headers.get(content_encoding_key), None)
    // Identity refusal still yields 406 for a non-compressible file, so the
    // identity 200 varies on Accept-Encoding.
    assert_eq(response.headers.get(vary_key), Some("Accept-Encoding"))
    assert_eq(client.read_all().binary(), bytes)
  })
  @fs.rmdir(dir, recursive=true)
}

///|
async test "queued file ranges apply to the compressed representation" {
  let dir = @fs.tmpdir(prefix="feather-file-compress-range")
  let payload = "range over compressed file bytes ".repeat(64)
  @fs.write_file(dir + "/report.txt", payload)
  let app = @feather.App::new()
    .compress(min_size=0)
    .get("/download", fn(ctx) { ctx.file(200, dir + "/report.txt") })
  with_server(app, client => {
    let full = client.get(
      "/download",
      extra_headers=Map([(accept_encoding_key, "gzip")]),
    )
    assert_eq(full.code, 200)
    let total = client.read_all().binary().length()
    client.request(
      @http.RequestMethod::Get,
      "/download",
      extra_headers=Map([
        (accept_encoding_key, "gzip"),
        (@http.CaseInsensitiveString("Range"), "bytes=0-9"),
      ]),
    )
    let ranged = client.end_request()
    assert_eq(ranged.code, 206)
    assert_eq(
      ranged.headers.get(@http.CaseInsensitiveString("Content-Range")),
      Some("bytes 0-9/" + total.to_string()),
    )
    assert_eq(client.read_all().binary().length(), 10)
  })
  @fs.rmdir(dir, recursive=true)
}

///|
async test "HEAD describes the compressed queued file representation" {
  let dir = @fs.tmpdir(prefix="feather-file-compress-head")
  let payload = "head over compressed file bytes ".repeat(64)
  @fs.write_file(dir + "/report.txt", payload)
  let app = @feather.App::new()
    .compress(min_size=0)
    .get("/download", fn(ctx) { ctx.file(200, dir + "/report.txt") })
  with_server(app, client => {
    let full = client.get(
      "/download",
      extra_headers=Map([(accept_encoding_key, "gzip")]),
    )
    assert_eq(full.code, 200)
    let compressed_length = client.read_all().binary().length()
    client.request(
      @http.RequestMethod::Head,
      "/download",
      extra_headers=Map([(accept_encoding_key, "gzip")]),
    )
    let head = client.end_request()
    assert_eq(head.code, 200)
    assert_eq(head.headers.get(content_encoding_key), Some("gzip"))
    assert_eq(
      head.headers.get(@http.CaseInsensitiveString("Content-Length")),
      Some(compressed_length.to_string()),
    )
    assert_eq(client.read_all().binary().length(), 0)
  })
  @fs.rmdir(dir, recursive=true)
}

///|
async test "queued file precondition failures vary on accept-encoding" {
  let dir = @fs.tmpdir(prefix="feather-file-compress-412-vary")
  @fs.write_file(dir + "/data.txt", "queued precondition ".repeat(64))
  let app = @feather.App::new()
    .compress(min_size=0)
    .use(fn(next) {
      fn(ctx) {
        ctx.set_header("ETag", "\"custom\"")
        next(ctx)
      }
    })
    .get("/download", fn(ctx) { ctx.file(200, dir + "/data.txt") })
  with_server(app, client => {
    let response = client.get(
      "/download",
      extra_headers=Map([
        (accept_encoding_key, "gzip"),
        (@http.CaseInsensitiveString("If-Match"), "\"stale\""),
      ]),
    )
    assert_eq(response.code, 412)
    assert_true(
      response.headers
      .get(@http.CaseInsensitiveString("Vary"))
      .unwrap_or("")
      .contains("Accept-Encoding"),
    )
    ignore(client.read_all())
  })
  @fs.rmdir(dir, recursive=true)
}
