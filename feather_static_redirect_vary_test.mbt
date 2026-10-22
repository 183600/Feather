///|
async test "precompressed-only directory redirect varies on accept-encoding" {
  let dir = @fs.tmpdir(prefix="feather-static-redirect-vary")
  @fs.mkdir(dir + "/guide")
  @fs.write_file(
    dir + "/guide/index.html.gz",
    gzip_encode_for_test(@utf8.encode("<h1>guide</h1>")),
  )
  let app = @feather.App::new().static_files("/assets", dir, precompressed=true)
  with_server(app, client => {
    let redirect = client.get(
      "/assets/guide",
      extra_headers=Map([
        (@http.CaseInsensitiveString("Accept-Encoding"), "gzip"),
      ]),
    )
    assert_eq(redirect.code, 301)
    assert_eq(
      redirect.headers.get(@http.CaseInsensitiveString("Location")),
      Some("/assets/guide/"),
    )
    let vary = redirect
      .headers
      .get(@http.CaseInsensitiveString("Vary"))
      .unwrap_or("")
    assert_true(vary.contains("Accept-Encoding"), msg=vary)
    ignore(client.read_all())
  })
  @fs.rmdir(dir, recursive=true)
}
