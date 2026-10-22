///|
async test "static requests honor the request timeout while reading a body" {
  let dir = @fs.tmpdir(prefix="feather-static-timeout")
  @fs.write_file(dir + "/hello.txt", "hello")
  let app = @feather.App::new()
    .static_files("/assets", dir)
    .request_timeout(50)
  with_raw_server(app, conn => {
    conn.write(
      @utf8.encode(
        "GET /assets/hello.txt HTTP/1.1\r\nHost: test\r\nContent-Length: 20\r\nConnection: close\r\n\r\n",
      ),
    )
    let head = read_http_head(conn)
    assert_true(head.has_prefix("HTTP/1.1 504"))
  })
  @fs.rmdir(dir, recursive=true)
}
