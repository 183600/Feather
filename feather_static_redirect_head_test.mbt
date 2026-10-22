///|
async test "HEAD static redirects keep the GET content length" {
  let dir = @fs.tmpdir(prefix="feather-static-redirect-head")
  @fs.write_file(dir + "/index.html", "<h1>root</h1>")
  @fs.mkdir(dir + "/guide")
  @fs.write_file(dir + "/guide/index.html", "<h1>guide</h1>")
  let app = @feather.App::new().static_files("/assets", dir)
  with_server(app, client => {
    for path in ["/assets", "/assets/guide"] {
      let get = client.get(path)
      assert_eq(get.code, 301, msg=path)
      let get_length = get.headers.get(
        @http.CaseInsensitiveString("Content-Length"),
      )
      assert_eq(get_length, Some("0"), msg=path)
      assert_eq(client.read_all().text(), "", msg=path)

      client.request(@http.RequestMethod::Head, path)
      let head = client.end_request()
      assert_eq(head.code, 301, msg=path)
      assert_eq(
        head.headers.get(@http.CaseInsensitiveString("Content-Length")),
        get_length,
        msg=path,
      )
      assert_eq(client.read_all().text(), "", msg=path)
    }
  })
  @fs.rmdir(dir, recursive=true)
}
