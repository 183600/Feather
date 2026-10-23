///|
async test "file 205 responses frame zero length for GET and HEAD" {
  let dir = @fs.tmpdir(prefix="feather-file-reset-content")
  @fs.write_file(dir + "/body.txt", "ignored")
  let app = @feather.App::new().get("/reset-file", fn(ctx) {
    ctx.file(205, dir + "/body.txt")
  })
  with_server(app, client => {
    let get = client.get("/reset-file")
    assert_eq(get.code, 205)
    assert_eq(
      get.headers.get(@http.CaseInsensitiveString("Content-Length")),
      Some("0"),
    )
    assert_eq(
      get.headers.get(@http.CaseInsensitiveString("Content-Type")),
      None,
    )
    assert_eq(client.read_all().text(), "")

    client.request(@http.RequestMethod::Head, "/reset-file")
    let head = client.end_request()
    assert_eq(head.code, 205)
    assert_eq(
      head.headers.get(@http.CaseInsensitiveString("Content-Length")),
      Some("0"),
    )
    assert_eq(
      head.headers.get(@http.CaseInsensitiveString("Content-Type")),
      None,
    )
    assert_eq(client.read_all().text(), "")
  })
  @fs.rmdir(dir, recursive=true)
}
