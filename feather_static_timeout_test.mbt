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

///|
async test "static timeout after the response starts closes the connection" {
  let dir = @fs.tmpdir(prefix="feather-static-timeout-body")
  @fs.write_file(dir + "/large.bin", "x".repeat(8 * 1024 * 1024))
  let app = @feather.App::new()
    .static_files("/assets", dir)
    .request_timeout(10)
  with_raw_server(app, conn => {
    conn.write(
      @utf8.encode(
        "GET /assets/large.bin HTTP/1.1\r\nHost: test\r\nConnection: close\r\n\r\n",
      ),
    )
    let head = read_http_head(conn)
    assert_true(head.has_prefix("HTTP/1.1 200"), msg=head)
    // Do not drain the body. The response write blocks once the socket buffer
    // is full, the timeout fires, and the server must close rather than try to
    // send a second response on a connection already framing a file.
    @async.sleep(100)
    let rest = conn.read_all().text()
    assert_false(rest.contains("HTTP/1.1 504"), msg=rest)
  })
  @fs.rmdir(dir, recursive=true)
}
