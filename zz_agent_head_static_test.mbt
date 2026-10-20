///|
async test "agent HEAD falls back to GET route before static mount" {
  let dir = @fs.tmpdir(prefix="feather-head-static")
  @fs.write_file(dir + "/foo", "static")
  let app = @feather.App::new()
    .get("/assets/foo", fn(ctx) { ctx.text(200, "dynamic!") })
    .static_files("/assets", dir)
  with_raw_server(app, conn => {
    conn.write(
      @utf8.encode(
        "HEAD /assets/foo HTTP/1.1\r\nHost: test\r\nConnection: close\r\n\r\n",
      ),
    )
    let head = read_http_head(conn)
    assert_true(head.has_prefix("HTTP/1.1 200"))
    assert_true(head.contains("Content-Type: text/plain; charset=utf-8"))
    assert_true(head.contains("Content-Length: 8"))
  })
  @fs.rmdir(dir, recursive=true)
}

///|
async test "agent newly added gzip sibling is served after a negative probe" {
  let dir = @fs.tmpdir(prefix="feather-gzip-probe")
  let plain = "console.log(\"new gzip sibling\");\n"
  @fs.write_file(dir + "/app.js", plain)
  let app = @feather.App::new().static_files("/assets", dir, precompressed=true)
  with_server(app, client => {
    let first = client.get(
      "/assets/app.js",
      extra_headers=Map([(ext_accept_encoding, "gzip")]),
    )
    assert_eq(first.code, 200)
    assert_eq(first.headers.get(ext_content_encoding), None)
    assert_eq(client.read_all().text(), plain)
    @fs.write_file(dir + "/app.js.gz", gzip_encode_for_test(@utf8.encode(plain)))
    let second = client.get(
      "/assets/app.js",
      extra_headers=Map([(ext_accept_encoding, "gzip")]),
    )
    assert_eq(second.code, 200)
    assert_eq(second.headers.get(ext_content_encoding), Some("gzip"))
    let decoded = gunzip_for_test(client.read_all().binary())
    assert_eq(@utf8.decode_lossy(decoded), plain)
  })
  @fs.rmdir(dir, recursive=true)
}
