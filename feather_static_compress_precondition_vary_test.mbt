///|
async test "compressed static precondition failures vary on accept-encoding" {
  let dir = @fs.tmpdir(prefix="feather-static-compress-412-vary")
  @fs.write_file(dir + "/data.txt", "precondition validator ".repeat(64))
  let app = @feather.App::new()
    .compress(min_size=0)
    .use(fn(next) {
      fn(ctx) {
        ctx.set_header("ETag", "\"custom\"")
        next(ctx)
      }
    })
    .static_files("/assets", dir)
  with_server(app, client => {
    let response = client.get(
      "/assets/data.txt",
      extra_headers=Map([
        (@http.CaseInsensitiveString("Accept-Encoding"), "gzip"),
        (@http.CaseInsensitiveString("If-Match"), "\"stale\""),
      ]),
    )
    assert_eq(response.code, 412)
    assert_true(
      response.headers
      .get(@http.CaseInsensitiveString("Vary"))
      .unwrap_or("")
      .contains("Accept-Encoding"),
    )
    ignore(client.read_all())
  })
  @fs.rmdir(dir, recursive=true)
}
