///|
async test "static mounts never escape their root over the wire" {
  let dir = @fs.tmpdir(prefix="feather-trav")
  @fs.mkdir(dir + "/assets")
  @fs.write_file(dir + "/assets/ok.txt", "ok")
  @fs.write_file(dir + "/secret.txt", "secret")
  let app = @feather.App::new().static_files("/assets", dir + "/assets")
  for path in [
    "/assets/../secret.txt",
    "/assets/%2e%2e/secret.txt",
    "/assets/..%2fsecret.txt",
    "/assets/%2e%2e%2fsecret.txt",
    "/assets//../secret.txt",
  ] {
    with_raw_server(app, conn => {
      conn.write(
        @utf8.encode(
          "GET \{path} HTTP/1.1\r\nHost: test\r\nConnection: close\r\n\r\n",
        ),
      )
      let head = read_http_head(conn)
      assert_true(head.has_prefix("HTTP/1.1 404"))
      assert_false(head.contains("secret"))
    })
  }
  with_raw_server(app, conn => {
    conn.write(
      @utf8.encode(
        "GET /assets/ok.txt HTTP/1.1\r\nHost: test\r\nConnection: close\r\n\r\n",
      ),
    )
    let head = read_http_head(conn)
    assert_true(head.has_prefix("HTTP/1.1 200"))
  })
  @fs.rmdir(dir, recursive=true)
}
