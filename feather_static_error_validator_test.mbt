///|
async test "static error responses drop stale file validators" {
  let dir = @fs.tmpdir(prefix="feather-static-error-validators")
  @fs.write_file(dir + "/asset.txt", "asset body")
  let app = @feather.App::new()
    .use(fn(next) {
      fn(ctx) {
        ctx.set_header("ETag", "\"stale-file-tag\"")
        ctx.set_header("Last-Modified", "Wed, 21 Oct 2015 07:28:00 GMT")
        next(ctx)
      }
    })
    .static_files("/assets", dir)
  with_server(app, client => {
    let missing = client.get("/assets/missing.txt")
    assert_eq(missing.code, 404)
    assert_eq(
      missing.headers.get(@http.CaseInsensitiveString("ETag")),
      None,
    )
    assert_eq(
      missing.headers.get(@http.CaseInsensitiveString("Last-Modified")),
      None,
    )
    ignore(client.read_all())
    let refused = client.get(
      "/assets/asset.txt",
      extra_headers=Map([
        (@http.CaseInsensitiveString("Accept-Encoding"), "identity;q=0"),
      ]),
    )
    assert_eq(refused.code, 406)
    assert_eq(
      refused.headers.get(@http.CaseInsensitiveString("ETag")),
      None,
    )
    assert_eq(
      refused.headers.get(@http.CaseInsensitiveString("Last-Modified")),
      None,
    )
    ignore(client.read_all())
  })
  @fs.rmdir(dir, recursive=true)
}
