///|
async test "static compression honors a middleware content type override" {
  let dir = @fs.tmpdir(prefix="feather-static-compress-content-type")
  @fs.write_file(dir + "/asset.bin", "compressible text ".repeat(64))
  let binary_app = @feather.App::new()
    .compress(min_size=0)
    .static_files_with("/assets", dir, [
      fn(next) {
        fn(ctx) {
          ctx.set_header("Content-Type", "image/png")
          next(ctx)
        }
      },
    ])
  with_server(binary_app, client => {
    let response = client.get(
      "/assets/asset.bin",
      extra_headers=Map([(@http.CaseInsensitiveString("Accept-Encoding"), "gzip")]),
    )
    assert_eq(response.code, 200)
    assert_eq(
      response.headers.get(@http.CaseInsensitiveString("Content-Encoding")),
      None,
    )
    assert_eq(
      response.headers.get(@http.CaseInsensitiveString("Content-Type")),
      Some("image/png"),
    )
    assert_eq(client.read_all().text(), "compressible text ".repeat(64))
  })
  @fs.rmdir(dir, recursive=true)
}

///|
async test "static compression accepts a middleware text content type" {
  let dir = @fs.tmpdir(prefix="feather-static-compress-content-type-text")
  let payload = "compressible text ".repeat(64)
  @fs.write_file(dir + "/asset.bin", payload)
  let app = @feather.App::new()
    .compress(min_size=0)
    .static_files_with("/assets", dir, [
      fn(next) {
        fn(ctx) {
          ctx.set_header("Content-Type", "text/plain; charset=utf-8")
          next(ctx)
        }
      },
    ])
  with_server(app, client => {
    let response = client.get(
      "/assets/asset.bin",
      extra_headers=Map([(@http.CaseInsensitiveString("Accept-Encoding"), "gzip")]),
    )
    assert_eq(response.code, 200)
    assert_eq(
      response.headers.get(@http.CaseInsensitiveString("Content-Encoding")),
      Some("gzip"),
    )
    let compressed = client.read_all().binary()
    assert_eq(@utf8.decode_lossy(gunzip_for_test(compressed)), payload)
  })
  @fs.rmdir(dir, recursive=true)
}
