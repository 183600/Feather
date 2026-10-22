///|
async test "static mount root redirects to the canonical trailing slash" {
  let dir = @fs.tmpdir(prefix="feather-static-root-redirect")
  @fs.write_file(dir + "/index.html", "<h1>root</h1>")
  let app = @feather.App::new().static_files("/assets", dir)
  with_server(app, client => {
    let redirect = client.get("/assets")
    assert_eq(redirect.code, 301)
    assert_eq(
      redirect.headers.get(@http.CaseInsensitiveString("Location")),
      Some("/assets/"),
    )
    assert_eq(
      redirect.headers.get(@http.CaseInsensitiveString("Content-Type")),
      None,
    )
    assert_eq(client.read_all().text(), "")
    let page = client.get("/assets/")
    assert_eq(page.code, 200)
    assert_eq(client.read_all().text(), "<h1>root</h1>")
  })
  @fs.rmdir(dir, recursive=true)
}

///|
async test "static mount root redirect keeps the query string" {
  let dir = @fs.tmpdir(prefix="feather-static-root-redirect-query")
  @fs.write_file(dir + "/index.html", "<h1>root</h1>")
  let app = @feather.App::new().static_files("/assets", dir)
  with_server(app, client => {
    let redirect = client.get("/assets?theme=dark")
    assert_eq(redirect.code, 301)
    assert_eq(
      redirect.headers.get(@http.CaseInsensitiveString("Location")),
      Some("/assets/?theme=dark"),
    )
    ignore(client.read_all())
  })
  @fs.rmdir(dir, recursive=true)
}

///|
async test "HEAD on a static mount root gets the same redirect" {
  let dir = @fs.tmpdir(prefix="feather-static-root-redirect-head")
  @fs.write_file(dir + "/index.html", "<h1>root</h1>")
  let app = @feather.App::new().static_files("/assets", dir)
  with_server(app, client => {
    client.request(@http.RequestMethod::Head, "/assets")
    let response = client.end_request()
    assert_eq(response.code, 301)
    assert_eq(
      response.headers.get(@http.CaseInsensitiveString("Location")),
      Some("/assets/"),
    )
    assert_eq(client.read_all().text(), "")
  })
  @fs.rmdir(dir, recursive=true)
}

///|
async test "a mount root without an index still reports 404 instead of redirecting" {
  let dir = @fs.tmpdir(prefix="feather-static-root-missing-index")
  @fs.write_file(dir + "/app.css", "body {}")
  let app = @feather.App::new().static_files("/assets", dir)
  with_server(app, client => {
    let response = client.get("/assets")
    assert_eq(response.code, 404)
    assert_eq(
      response.headers.get(@http.CaseInsensitiveString("Location")),
      None,
    )
    ignore(client.read_all())
  })
  @fs.rmdir(dir, recursive=true)
}

///|
async test "a precompressed-only subdirectory index still redirects" {
  let dir = @fs.tmpdir(prefix="feather-static-gzip-index-redirect")
  @fs.mkdir(dir + "/guide")
  @fs.write_file(
    dir + "/guide/index.html.gz",
    gzip_encode_for_test(@utf8.encode("<h1>guide</h1>")),
  )
  let app = @feather.App::new().static_files("/assets", dir, precompressed=true)
  with_server(app, client => {
    let redirect = client.get(
      "/assets/guide",
      extra_headers=Map([(ext_accept_encoding, "gzip")]),
    )
    assert_eq(redirect.code, 301)
    assert_eq(
      redirect.headers.get(@http.CaseInsensitiveString("Location")),
      Some("/assets/guide/"),
    )
    ignore(client.read_all())
    let page = client.get(
      "/assets/guide/",
      extra_headers=Map([(ext_accept_encoding, "gzip")]),
    )
    assert_eq(page.code, 200)
    assert_eq(
      page.headers.get(ext_content_encoding),
      Some("gzip"),
    )
    assert_eq(
      @utf8.decode_lossy(gunzip_for_test(client.read_all().binary())),
      "<h1>guide</h1>",
    )
  })
  @fs.rmdir(dir, recursive=true)
}
