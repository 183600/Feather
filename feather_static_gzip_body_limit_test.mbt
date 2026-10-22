///|
async test "static fast path limits the decoded gzip request body" {
  let dir = @fs.tmpdir(prefix="feather-static-gzip-body-limit")
  @fs.write_file(dir + "/hello.txt", "hello")
  let app = @feather.App::new().static_files("/assets", dir)
  let compressed = gzip_encode_for_test(@utf8.encode("x".repeat(2000)))
  with_raw_server(app, conn => {
    conn.write(
      @utf8.encode(
        "GET /assets/hello.txt HTTP/1.1\r\nHost: test\r\nContent-Encoding: gzip\r\nContent-Length: " +
        compressed.length().to_string() +
        "\r\nConnection: close\r\n\r\n",
      ),
    )
    conn.write(compressed)
    let head = read_http_head(conn)
    assert_true(head.has_prefix("HTTP/1.1 413"), msg=head)
  })
  @fs.rmdir(dir, recursive=true)
}

///|
async test "static fast path accepts a gzip request body under the limit" {
  let dir = @fs.tmpdir(prefix="feather-static-gzip-body-ok")
  @fs.write_file(dir + "/hello.txt", "hello")
  let app = @feather.App::new().static_files("/assets", dir)
  let compressed = gzip_encode_for_test(@utf8.encode("small body"))
  with_raw_server(app, conn => {
    conn.write(
      @utf8.encode(
        "GET /assets/hello.txt HTTP/1.1\r\nHost: test\r\nContent-Encoding: gzip\r\nContent-Length: " +
        compressed.length().to_string() +
        "\r\nConnection: close\r\n\r\n",
      ),
    )
    conn.write(compressed)
    let head = read_http_head(conn)
    assert_true(head.has_prefix("HTTP/1.1 200"), msg=head)
  })
  @fs.rmdir(dir, recursive=true)
}
