///|
async test "Context no_etag suppresses a queued file validator" {
  let dir = @fs.tmpdir(prefix="feather-file-noetag")
  @fs.write_file(dir + "/asset.txt", "file body")
  let app = @feather.App::new().get("/asset", fn(ctx) {
    ctx.no_etag()
    ctx.file(200, dir + "/asset.txt")
  })
  with_server(app, client => {
    let response = client.get("/asset")
    assert_eq(response.code, 200)
    assert_eq(
      response.headers.get(@http.CaseInsensitiveString("ETag")),
      None,
    )
    assert_eq(client.read_all().text(), "file body")
  })
  @fs.rmdir(dir, recursive=true)
}

///|
async test "Context no_etag keeps an explicit queued file validator" {
  let dir = @fs.tmpdir(prefix="feather-file-noetag")
  @fs.write_file(dir + "/asset.txt", "file body")
  let app = @feather.App::new().get("/asset", fn(ctx) {
    ctx.set_header("ETag", "\"manual\"")
    ctx.no_etag()
    ctx.file(200, dir + "/asset.txt")
  })
  with_server(app, client => {
    let response = client.get("/asset")
    assert_eq(response.code, 200)
    assert_eq(
      response.headers.get(@http.CaseInsensitiveString("ETag")),
      Some("\"manual\""),
    )
    assert_eq(client.read_all().text(), "file body")
  })
  @fs.rmdir(dir, recursive=true)
}

///|
async test "Context no_etag suppresses a static mount validator" {
  let dir = @fs.tmpdir(prefix="feather-static-noetag")
  @fs.write_file(dir + "/asset.txt", "static body")
  let app = @feather.App::new()
    .use(fn(next) {
      fn(ctx) raise {
        ctx.no_etag()
        next(ctx)
      }
    })
    .static_files("/assets", dir)
  with_server(app, client => {
    let response = client.get("/assets/asset.txt")
    assert_eq(response.code, 200)
    assert_eq(
      response.headers.get(@http.CaseInsensitiveString("ETag")),
      None,
    )
    assert_eq(client.read_all().text(), "static body")
  })
  @fs.rmdir(dir, recursive=true)
}
