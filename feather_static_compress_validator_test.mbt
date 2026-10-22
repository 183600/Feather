///|
async test "compressed static responses weaken middleware etags" {
  let dir = @fs.tmpdir(prefix="feather-static-compress-validator")
  @fs.write_file(dir + "/data.txt", "custom validator ".repeat(64))
  let app = @feather.App::new()
    .compress(min_size=0)
    .static_files_with("/assets", dir, [
      fn(next) {
        fn(ctx) {
          ctx.set_header("ETag", "\"custom\"")
          next(ctx)
        }
      },
    ])
  with_server(app, client => {
    let response = client.get(
      "/assets/data.txt",
      extra_headers=Map([(@http.CaseInsensitiveString("Accept-Encoding"), "gzip")]),
    )
    assert_eq(response.code, 200)
    assert_eq(
      response.headers.get(@http.CaseInsensitiveString("Content-Encoding")),
      Some("gzip"),
    )
    assert_eq(
      response.headers.get(@http.CaseInsensitiveString("ETag")),
      Some("W/\"custom\""),
    )
    ignore(client.read_all())
  })
  @fs.rmdir(dir, recursive=true)
}

///|
async test "precompressed static responses weaken middleware etags" {
  let dir = @fs.tmpdir(prefix="feather-static-precompressed-validator")
  @fs.write_file(dir + "/data.txt", "custom validator ".repeat(64))
  @fs.write_file(dir + "/data.txt.gz", b"gzip bytes")
  let app = @feather.App::new()
    .static_files_with("/assets", dir, [
      fn(next) {
        fn(ctx) {
          ctx.set_header("ETag", "\"custom\"")
          next(ctx)
        }
      },
    ], precompressed=true)
  with_server(app, client => {
    let response = client.get(
      "/assets/data.txt",
      extra_headers=Map([(@http.CaseInsensitiveString("Accept-Encoding"), "gzip")]),
    )
    assert_eq(response.code, 200)
    assert_eq(
      response.headers.get(@http.CaseInsensitiveString("Content-Encoding")),
      Some("gzip"),
    )
    assert_eq(
      response.headers.get(@http.CaseInsensitiveString("ETag")),
      Some("W/\"custom\""),
    )
    ignore(client.read_all())
  })
  @fs.rmdir(dir, recursive=true)
}
