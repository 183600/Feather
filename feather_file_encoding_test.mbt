///|
async fn preencoded_gzip_file(dir : String, payload : String) -> String {
  let path = dir + "/data.txt"
  @fs.write_file(path, gzip_encode_for_test(@utf8.encode(payload)))
  path
}

///|
async test "queued files with an existing gzip coding honor the coding" {
  let dir = @fs.tmpdir(prefix="feather-file-existing-gzip")
  let payload = "pre-encoded file payload ".repeat(64)
  let path = preencoded_gzip_file(dir, payload)
  let app = @feather.App::new().get("/download", fn(ctx) {
    ctx.file(200, path)
    ctx.set_header("Content-Encoding", "gzip")
  })
  with_server(app, client => {
    let response = client.get(
      "/download",
      extra_headers=Map([
        (@http.CaseInsensitiveString("Accept-Encoding"), "gzip, identity;q=0"),
      ]),
    )
    assert_eq(response.code, 200)
    assert_eq(
      response.headers.get(@http.CaseInsensitiveString("Content-Encoding")),
      Some("gzip"),
    )
    assert_eq(
      @utf8.decode_lossy(gunzip_for_test(client.read_all().binary())),
      payload,
    )
  })
  @fs.rmdir(dir, recursive=true)
}

///|
async test "queued files with an existing gzip coding reject a client that refuses it" {
  let dir = @fs.tmpdir(prefix="feather-file-existing-gzip-refused")
  let payload = "pre-encoded file payload ".repeat(64)
  let path = preencoded_gzip_file(dir, payload)
  let app = @feather.App::new().get("/download", fn(ctx) {
    ctx.file(200, path)
    ctx.set_header("Content-Encoding", "gzip")
  })
  with_server(app, client => {
    let response = client.get(
      "/download",
      extra_headers=Map([
        (@http.CaseInsensitiveString("Accept-Encoding"), "identity"),
      ]),
    )
    assert_eq(response.code, 406)
    assert_eq(
      response.headers.get(@http.CaseInsensitiveString("Content-Encoding")),
      None,
    )
    assert_eq(client.read_all().text(), "406 Not Acceptable")
  })
  @fs.rmdir(dir, recursive=true)
}

///|
async test "ranges on an existing gzip coding use the encoded representation" {
  let dir = @fs.tmpdir(prefix="feather-file-existing-gzip-range")
  let payload = "pre-encoded range payload ".repeat(64)
  let path = preencoded_gzip_file(dir, payload)
  let encoded_size = @fs.read_file(path).binary().length()
  let app = @feather.App::new().get("/download", fn(ctx) {
    ctx.file(200, path)
    ctx.set_header("Content-Encoding", "gzip")
  })
  with_server(app, client => {
    let response = client.get(
      "/download",
      extra_headers=Map([
        (@http.CaseInsensitiveString("Accept-Encoding"), "gzip"),
        (@http.CaseInsensitiveString("Range"), "bytes=0-9"),
      ]),
    )
    assert_eq(response.code, 206)
    assert_eq(
      response.headers.get(@http.CaseInsensitiveString("Content-Encoding")),
      Some("gzip"),
    )
    assert_eq(
      response.headers.get(@http.CaseInsensitiveString("Content-Range")),
      Some("bytes 0-9/" + encoded_size.to_string()),
    )
    assert_eq(client.read_all().binary().length(), 10)
  })
  @fs.rmdir(dir, recursive=true)
}
