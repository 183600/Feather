///|
async test "agent async middleware error after calling through must not start sse" {
  let app = @feather.App::new()
    .use(fn(next) {
      fn(ctx) raise {
        next(ctx)
        raise @feather.HttpError(500, "boom")
      }
    })
    .sse("/events", async fn(_ctx, sse) { sse.send("handler-ran") })
  with_sse_server(app, client => {
    let response = client.get("/events")
    assert_eq(response.code, 500)
    assert_eq(client.read_all().text(), "{\"status\":500,\"error\":\"boom\"}")
  })
}

///|
async test "agent static middleware error after calling through must not serve file" {
  let dir = @fs.tmpdir(prefix="feather-static-middleware-error")
  @fs.write_file(dir + "/asset.txt", "asset")
  let app = @feather.App::new()
    .use(fn(next) {
      fn(ctx) raise {
        next(ctx)
        raise @feather.HttpError(503, "unavailable")
      }
    })
    .static_files("/assets", dir)
  with_server(app, client => {
    let response = client.get("/assets/asset.txt")
    assert_eq(response.code, 503)
    assert_eq(
      client.read_all().text(),
      "{\"status\":503,\"error\":\"unavailable\"}",
    )
  })
  @fs.rmdir(dir, recursive=true)
}

///|
async test "agent static 304 must drop middleware content length" {
  let dir = @fs.tmpdir(prefix="feather-static-304-cl")
  @fs.write_file(dir + "/asset.txt", "asset")
  let app = @feather.App::new()
    .use(fn(next) {
      fn(ctx) {
        ctx.set_header("Content-Length", "999")
        next(ctx)
      }
    })
    .static_files("/assets", dir)
  with_server(app, client => {
    let first = client.get("/assets/asset.txt")
    let etag = first.headers.get(@http.CaseInsensitiveString("ETag")).unwrap()
    ignore(client.read_all())
    let second = client.get(
      "/assets/asset.txt",
      extra_headers=Map([(@http.CaseInsensitiveString("If-None-Match"), etag)]),
    )
    assert_eq(second.code, 304)
    assert_eq(
      second.headers.get(@http.CaseInsensitiveString("Content-Length")),
      None,
    )
  })
  @fs.rmdir(dir, recursive=true)
}

///|
async test "agent gzip-only static 404 still varies on accept-encoding" {
  let dir = @fs.tmpdir(prefix="feather-gz-only-vary")
  let encoded = gzip_encode_for_test(@utf8.encode("only gzip\n"))
  @fs.write_file(dir + "/app.js.gz", encoded)
  let app = @feather.App::new().static_files("/assets", dir, precompressed=true)
  with_server(app, client => {
    let gz = client.get(
      "/assets/app.js",
      extra_headers=Map([(ext_accept_encoding, "gzip")]),
    )
    assert_eq(gz.code, 200)
    assert_true(
      gz.headers.get(ext_vary).unwrap_or("").contains("Accept-Encoding"),
    )
    ignore(client.read_all())
    let identity = client.get(
      "/assets/app.js",
      extra_headers=Map([(ext_accept_encoding, "identity")]),
    )
    assert_eq(identity.code, 404)
    assert_true(
      identity.headers.get(ext_vary).unwrap_or("").contains("Accept-Encoding"),
    )
    ignore(client.read_all())
  })
  @fs.rmdir(dir, recursive=true)
}

///|
async test "agent static 416 must drop middleware content length" {
  let dir = @fs.tmpdir(prefix="feather-static-416-cl")
  @fs.write_file(dir + "/asset.txt", "asset")
  let app = @feather.App::new()
    .use(fn(next) {
      fn(ctx) {
        ctx.set_header("Content-Length", "999")
        next(ctx)
      }
    })
    .static_files("/assets", dir)
  with_server(app, client => {
    let response = client.get(
      "/assets/asset.txt",
      extra_headers=Map([(@http.CaseInsensitiveString("Range"), "bytes=99-")]),
    )
    assert_eq(response.code, 416)
    // The middleware's 999 must not leak; the runtime frames the empty body.
    assert_eq(
      response.headers.get(@http.CaseInsensitiveString("Content-Length")),
      Some("0"),
    )
    ignore(client.read_all())
  })
  @fs.rmdir(dir, recursive=true)
}

///|
async test "agent dynamic error must drop middleware content length" {
  let app = @feather.App::new()
    .use(fn(next) {
      fn(ctx) {
        ctx.set_header("Content-Length", "999")
        next(ctx)
      }
    })
    .get("/boom", fn(_ctx) { raise @feather.HttpError(503, "down") })
  with_raw_server(app, conn => {
    conn.write(
      @utf8.encode(
        "GET /boom HTTP/1.1\r\nHost: test\r\nConnection: close\r\n\r\n",
      ),
    )
    let head = read_http_head(conn)
    assert_true(head.has_prefix("HTTP/1.1 503"))
    assert_false(head.contains("Content-Length: 999"))
  })
}
