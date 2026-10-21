///|
fn first_http_status_line(head : String) -> String {
  match head.split("\r\n").next() {
    Some(line) => line.to_string()
    None => ""
  }
}

///|
async test "static mounts never escape their root over the wire" {
  let dir = @fs.tmpdir(prefix="feather-trav")
  @fs.mkdir(dir + "/assets")
  @fs.write_file(dir + "/assets/ok.txt", "ok")
  @fs.write_file(dir + "/secret.txt", "secret")
  let app = @feather.App::new().static_files("/assets", dir + "/assets")
  for
    path in [
      "/assets/../secret.txt", "/assets/%2e%2e/secret.txt", "/assets/..%2fsecret.txt",
      "/assets/%2e%2e%2fsecret.txt", "/assets//../secret.txt",
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

///|
async test "static mounts survive hostile percent escapes" {
  let dir = @fs.tmpdir(prefix="feather-trav2")
  @fs.mkdir(dir + "/assets")
  @fs.write_file(dir + "/assets/ok.txt", "ok")
  let app = @feather.App::new().static_files("/assets", dir + "/assets")
  for
    path in [
      "/assets/ok%00.txt", "/assets/%80.txt", "/assets/%c0%af.txt", "/assets/ok.txt%",
      "/assets/%2e%2e%2e%2fok.txt",
    ] {
    with_raw_server(app, conn => {
      conn.write(
        @utf8.encode(
          "GET \{path} HTTP/1.1\r\nHost: test\r\nConnection: close\r\n\r\n",
        ),
      )
      let head = read_http_head(conn)
      let status = first_http_status_line(head)
      assert_true(
        status.has_prefix("HTTP/1.1 404") || status.has_prefix("HTTP/1.1 400"),
      )
    })
  }
  @fs.rmdir(dir, recursive=true)
}
