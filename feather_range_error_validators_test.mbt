///|
async test "unsatisfiable static ranges drop representation validators" {
  let dir = @fs.tmpdir(prefix="feather-static-416-validators")
  @fs.write_file(dir + "/asset.txt", "asset body")
  let app = @feather.App::new().static_files("/assets", dir)
  with_server(app, client => {
    let response = client.get(
      "/assets/asset.txt",
      extra_headers=Map([
        (@http.CaseInsensitiveString("Range"), "bytes=99-"),
      ]),
    )
    assert_eq(response.code, 416)
    assert_eq(
      response.headers.get(@http.CaseInsensitiveString("ETag")),
      None,
    )
    assert_eq(
      response.headers.get(@http.CaseInsensitiveString("Last-Modified")),
      None,
    )
    assert_eq(
      response.headers.get(@http.CaseInsensitiveString("Content-Range")),
      Some("bytes */10"),
    )
    ignore(client.read_all())
  })
  @fs.rmdir(dir, recursive=true)
}

///|
async test "unsatisfiable queued-file ranges drop representation validators" {
  let dir = @fs.tmpdir(prefix="feather-file-416-validators")
  @fs.write_file(dir + "/asset.txt", "asset body")
  let app = @feather.App::new().get("/download", fn(ctx) {
    ctx.file(200, dir + "/asset.txt")
  })
  with_server(app, client => {
    let response = client.get(
      "/download",
      extra_headers=Map([
        (@http.CaseInsensitiveString("Range"), "bytes=99-"),
      ]),
    )
    assert_eq(response.code, 416)
    assert_eq(
      response.headers.get(@http.CaseInsensitiveString("ETag")),
      None,
    )
    assert_eq(
      response.headers.get(@http.CaseInsensitiveString("Last-Modified")),
      None,
    )
    assert_eq(
      response.headers.get(@http.CaseInsensitiveString("Content-Range")),
      Some("bytes */10"),
    )
    ignore(client.read_all())
  })
  @fs.rmdir(dir, recursive=true)
}
