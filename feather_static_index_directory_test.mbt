///|
async test "a directory used as the index does not redirect to itself" {
  let dir = @fs.tmpdir(prefix="feather-static-index-directory")
  @fs.mkdir(dir + "/index.html")
  let app = @feather.App::new().static_files("/site", dir)
  with_server(app, client => {
    let response = client.get("/site/")
    assert_eq(response.code, 404)
    assert_eq(
      response.headers.get(@http.CaseInsensitiveString("Location")),
      None,
    )
    assert_eq(client.read_all().text(), "404 Not Found")
  })
  @fs.rmdir(dir, recursive=true)
}

///|
async test "a subdirectory redirect waits for its configured index" {
  let dir = @fs.tmpdir(prefix="feather-static-subdir-index")
  @fs.mkdir(dir + "/empty")
  @fs.write_file(dir + "/index.html", "<h1>root</h1>")
  let app = @feather.App::new().static_files("/assets", dir)
  with_server(app, client => {
    let response = client.get("/assets/empty")
    assert_eq(response.code, 404)
    assert_eq(
      response.headers.get(@http.CaseInsensitiveString("Location")),
      None,
    )
    assert_eq(client.read_all().text(), "404 Not Found")
  })
  @fs.rmdir(dir, recursive=true)
}
