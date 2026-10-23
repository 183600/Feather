///|
async test "bodyless queued-file statuses do not depend on the file existing" {
  let app = @feather.App::new()
    .get("/early", fn(ctx) { ctx.file(103, "/definitely/not/here.txt") })
    .get("/no-content", fn(ctx) { ctx.file(204, "/definitely/not/here.txt") })
    .get("/reset", fn(ctx) { ctx.file(205, "/definitely/not/here.txt") })
    .get("/cached", fn(ctx) { ctx.file(304, "/definitely/not/here.txt") })
  with_server(app, client => {
    let no_content = client.get("/no-content")
    assert_eq(no_content.code, 204)
    assert_eq(
      no_content.headers.get(@http.CaseInsensitiveString("Content-Length")),
      None,
    )
    assert_eq(
      no_content.headers.get(@http.CaseInsensitiveString("Content-Type")),
      None,
    )
    assert_eq(client.read_all().text(), "")

    let reset = client.get("/reset")
    assert_eq(reset.code, 205)
    assert_eq(
      reset.headers.get(@http.CaseInsensitiveString("Content-Length")),
      Some("0"),
    )
    assert_eq(client.read_all().text(), "")

    let cached = client.get("/cached")
    assert_eq(cached.code, 304)
    assert_eq(client.read_all().text(), "")
  })
  // The offline facade already reports the status without a file lookup; the
  // server path must agree.
  for (path, status) in [
    ("/early", 103),
    ("/no-content", 204),
    ("/reset", 205),
    ("/cached", 304),
  ] {
    let response = app.respond({
      method: "GET",
      path,
      headers: Map([]),
      body: "",
    })
    assert_eq(response.status, status, msg=path)
  }
}

///|
async test "a bodyless queued-file status keeps handler validators" {
  let app = @feather.App::new().get("/cached", fn(ctx) {
    ctx.set_header("ETag", "\"v1\"")
    ctx.file(304, "/definitely/not/here.txt")
  })
  with_server(app, client => {
    let response = client.get("/cached")
    assert_eq(response.code, 304)
    assert_eq(
      response.headers.get(@http.CaseInsensitiveString("ETag")),
      Some("\"v1\""),
    )
    assert_eq(client.read_all().text(), "")
  })
}

///|
async test "an unsatisfiable queued-file range still advertises range support" {
  let dir = @fs.tmpdir(prefix="feather-file-416-accept-ranges")
  @fs.write_file(dir + "/asset.txt", "0123456789")
  let app = @feather.App::new().get("/asset", fn(ctx) {
    ctx.file(200, dir + "/asset.txt")
  })
  with_server(app, client => {
    let response = client.get(
      "/asset",
      extra_headers=Map([
        (@http.CaseInsensitiveString("Range"), "bytes=99-"),
      ]),
    )
    assert_eq(response.code, 416)
    assert_eq(
      response.headers.get(@http.CaseInsensitiveString("Accept-Ranges")),
      Some("bytes"),
    )
    assert_eq(
      response.headers.get(@http.CaseInsensitiveString("Content-Range")),
      Some("bytes */10"),
    )
    ignore(client.read_all())
  })
  @fs.rmdir(dir, recursive=true)
}
