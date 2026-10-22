///|
let static_gzip_accept : @http.CaseInsensitiveString = @http.CaseInsensitiveString(
  "Accept-Encoding",
)

///|
let static_content_encoding : @http.CaseInsensitiveString = @http.CaseInsensitiveString(
  "Content-Encoding",
)

///|
let static_content_length : @http.CaseInsensitiveString = @http.CaseInsensitiveString(
  "Content-Length",
)

///|
let static_content_range : @http.CaseInsensitiveString = @http.CaseInsensitiveString(
  "Content-Range",
)

///|
let static_etag : @http.CaseInsensitiveString = @http.CaseInsensitiveString(
  "ETag",
)

///|
async test "application compression gzips static files" {
  let dir = @fs.tmpdir(prefix="feather-static-compress")
  let payload = "console.log(\"compressible static asset\");\n".repeat(64)
  @fs.write_file(dir + "/app.js", payload)
  let app = @feather.App::new()
    .compress(min_size=0)
    .static_files("/assets", dir)
  with_server(app, client => {
    let encoded = client.get(
      "/assets/app.js",
      extra_headers=Map([(static_gzip_accept, "gzip")]),
    )
    assert_eq(encoded.code, 200)
    assert_eq(encoded.headers.get(static_content_encoding), Some("gzip"))
    assert_true(
      encoded.headers
      .get(@http.CaseInsensitiveString("Vary"))
      .unwrap_or("")
      .contains("Accept-Encoding"),
    )
    let compressed = client.read_all().binary()
    assert_eq(@utf8.decode_lossy(gunzip_for_test(compressed)), payload)

    let identity = client.get(
      "/assets/app.js",
      extra_headers=Map([(static_gzip_accept, "identity")]),
    )
    assert_eq(identity.code, 200)
    assert_eq(identity.headers.get(static_content_encoding), None)
    assert_true(
      identity.headers
      .get(@http.CaseInsensitiveString("Vary"))
      .unwrap_or("")
      .contains("Accept-Encoding"),
    )
    assert_eq(client.read_all().text(), payload)
  })
  @fs.rmdir(dir, recursive=true)
}

///|
async test "head advertises the compressed static length" {
  let dir = @fs.tmpdir(prefix="feather-static-compress-head")
  let payload = "static head compression ".repeat(80)
  @fs.write_file(dir + "/head.txt", payload)
  let app = @feather.App::new()
    .compress(min_size=0)
    .static_files("/assets", dir)
  with_server(app, client => {
    ignore(
      client.get(
        "/assets/head.txt",
        extra_headers=Map([(static_gzip_accept, "gzip")]),
      ),
    )
    let compressed_length = client.read_all().binary().length()
    client.request(
      @http.RequestMethod::Head,
      "/assets/head.txt",
      extra_headers=Map([(static_gzip_accept, "gzip")]),
    )
    let head = client.end_request()
    assert_eq(head.code, 200)
    assert_eq(head.headers.get(static_content_encoding), Some("gzip"))
    assert_eq(
      head.headers.get(static_content_length),
      Some(compressed_length.to_string()),
    )
    assert_eq(client.read_all().text(), "")
  })
  @fs.rmdir(dir, recursive=true)
}

///|
async test "compressed static revalidation uses a weak validator" {
  let dir = @fs.tmpdir(prefix="feather-static-compress-etag")
  @fs.write_file(dir + "/data.txt", "revalidate compressed static ".repeat(32))
  let app = @feather.App::new()
    .compress(min_size=0)
    .static_files("/assets", dir)
  with_server(app, client => {
    let first = client.get(
      "/assets/data.txt",
      extra_headers=Map([(static_gzip_accept, "gzip")]),
    )
    let etag = first.headers.get(static_etag).unwrap()
    assert_true(etag.has_prefix("W/"), msg=etag)
    ignore(client.read_all())
    let revalidated = client.get(
      "/assets/data.txt",
      extra_headers=Map([
        (static_gzip_accept, "gzip"),
        (@http.CaseInsensitiveString("If-None-Match"), etag),
      ]),
    )
    assert_eq(revalidated.code, 304)
    assert_eq(revalidated.headers.get(static_content_encoding), Some("gzip"))
    assert_eq(client.read_all().text(), "")
  })
  @fs.rmdir(dir, recursive=true)
}

///|
async test "compressed static range covers the selected representation" {
  let dir = @fs.tmpdir(prefix="feather-static-compress-range")
  @fs.write_file(dir + "/range.txt", "range over compressed bytes ".repeat(64))
  let app = @feather.App::new()
    .compress(min_size=0)
    .static_files("/assets", dir)
  with_server(app, client => {
    ignore(
      client.get(
        "/assets/range.txt",
        extra_headers=Map([(static_gzip_accept, "gzip")]),
      ),
    )
    let total = client.read_all().binary().length()
    let response = client.get(
      "/assets/range.txt",
      extra_headers=Map([
        (static_gzip_accept, "gzip"),
        (@http.CaseInsensitiveString("Range"), "bytes=0-9"),
      ]),
    )
    assert_eq(response.code, 206)
    assert_eq(response.headers.get(static_content_length), Some("10"))
    assert_eq(
      response.headers.get(static_content_range),
      Some("bytes 0-9/" + total.to_string()),
    )
    assert_eq(client.read_all().binary().length(), 10)
  })
  @fs.rmdir(dir, recursive=true)
}

///|
async test "static middleware can opt a file out of compression" {
  let dir = @fs.tmpdir(prefix="feather-static-compress-off")
  let payload = "no compression for this file ".repeat(64)
  @fs.write_file(dir + "/plain.txt", payload)
  let app = @feather.App::new()
    .compress(min_size=0)
    .use(fn(next) {
      fn(ctx) raise {
        ctx.no_compress()
        next(ctx)
      }
    })
    .static_files("/assets", dir)
  with_server(app, client => {
    let response = client.get(
      "/assets/plain.txt",
      extra_headers=Map([(static_gzip_accept, "gzip")]),
    )
    assert_eq(response.code, 200)
    assert_eq(response.headers.get(static_content_encoding), None)
    assert_eq(client.read_all().text(), payload)
  })
  @fs.rmdir(dir, recursive=true)
}

///|
async test "compressed static files honor an identity refusal" {
  let dir = @fs.tmpdir(prefix="feather-static-compress-identity")
  let payload = "identity is not acceptable ".repeat(64)
  @fs.write_file(dir + "/only.txt", payload)
  let app = @feather.App::new()
    .compress(min_size=0)
    .static_files("/assets", dir)
  with_server(app, client => {
    let response = client.get(
      "/assets/only.txt",
      extra_headers=Map([(static_gzip_accept, "gzip, identity;q=0")]),
    )
    assert_eq(response.code, 200)
    assert_eq(response.headers.get(static_content_encoding), Some("gzip"))
    let compressed = client.read_all().binary()
    assert_eq(@utf8.decode_lossy(gunzip_for_test(compressed)), payload)
  })
  @fs.rmdir(dir, recursive=true)
}

///|
async test "no-transform static mounts are never compressed" {
  let dir = @fs.tmpdir(prefix="feather-static-compress-notransform")
  let payload = "do not transform this file ".repeat(64)
  @fs.write_file(dir + "/fixed.txt", payload)
  let app = @feather.App::new()
    .compress(min_size=0)
    .static_files(
      "/assets",
      dir,
      cache_control="no-transform, max-age=60",
    )
  with_server(app, client => {
    let response = client.get(
      "/assets/fixed.txt",
      extra_headers=Map([(static_gzip_accept, "gzip")]),
    )
    assert_eq(response.code, 200)
    assert_eq(response.headers.get(static_content_encoding), None)
    assert_eq(client.read_all().text(), payload)
  })
  @fs.rmdir(dir, recursive=true)
}
