///|
async test "queued file compression preserves a satisfied strong if-match" {
  let dir = @fs.tmpdir(prefix="feather-file-if-match")
  let payload = "compressed file validator ".repeat(64)
  @fs.write_file(dir + "/data.txt", payload)
  let app = @feather.App::new()
    .compress(min_size=0)
    .get("/download", fn(ctx) {
      ctx.set_header("ETag", "\"v1\"")
      ctx.file(200, dir + "/data.txt")
    })
  with_server(app, client => {
    let response = client.get(
      "/download",
      extra_headers=Map([
        (@http.CaseInsensitiveString("Accept-Encoding"), "gzip"),
        (@http.CaseInsensitiveString("If-Match"), "\"v1\""),
      ]),
    )
    assert_eq(response.code, 200)
    assert_eq(
      response.headers.get(@http.CaseInsensitiveString("Content-Encoding")),
      Some("gzip"),
    )
    assert_eq(
      response.headers.get(@http.CaseInsensitiveString("ETag")),
      Some("W/\"v1\""),
    )
    let decoded = gunzip_for_test(client.read_all().binary())
    assert_eq(@utf8.decode_lossy(decoded), payload)
  })
  @fs.rmdir(dir, recursive=true)
}

///|
async test "precompressed static files preserve a satisfied strong if-match" {
  let dir = @fs.tmpdir(prefix="feather-static-if-match")
  @fs.write_file(dir + "/data.txt", "identity body ".repeat(64))
  @fs.write_file(dir + "/data.txt.gz", b"gzip bytes")
  let app = @feather.App::new().static_files_with(
    "/assets",
    dir,
    [
      fn(next) {
        fn(ctx) {
          ctx.set_header("ETag", "\"v1\"")
          next(ctx)
        }
      },
    ],
    precompressed=true,
  )
  with_server(app, client => {
    let response = client.get(
      "/assets/data.txt",
      extra_headers=Map([
        (@http.CaseInsensitiveString("Accept-Encoding"), "gzip"),
        (@http.CaseInsensitiveString("If-Match"), "\"v1\""),
      ]),
    )
    assert_eq(response.code, 200)
    assert_eq(
      response.headers.get(@http.CaseInsensitiveString("Content-Encoding")),
      Some("gzip"),
    )
    assert_eq(
      response.headers.get(@http.CaseInsensitiveString("ETag")),
      Some("W/\"v1\""),
    )
    ignore(client.read_all())
  })
  @fs.rmdir(dir, recursive=true)
}
