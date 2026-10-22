///|
async test "declared oversized body is rejected before it arrives" {
  let app = @feather.App::new().post("/upload", fn(ctx) {
    ctx.text(200, ctx.request.body)
  })
  with_raw_server(app, conn => {
    conn.write(
      @utf8.encode(
        "POST /upload HTTP/1.1\r\nHost: test\r\nContent-Length: 2000\r\n\r\n",
      ),
    )
    let head = @async.with_timeout(2000, () => read_http_head(conn)) catch {
      _ => ""
    }
    assert_true(head.has_prefix("HTTP/1.1 413"))
  })
}

///|
async test "static fast path still enforces the body size limit" {
  let dir = @fs.tmpdir(prefix="feather-static-body-limit")
  @fs.write_file(dir + "/hello.txt", "hello")
  let app = @feather.App::new().static_files("/assets", dir)
  with_raw_server(app, conn => {
    conn.write(
      @utf8.encode(
        "GET /assets/hello.txt HTTP/1.1\r\nHost: test\r\nContent-Length: 1\r\nConnection: close\r\n\r\nx",
      ),
    )
    let head = read_http_head(conn)
    assert_true(head.has_prefix("HTTP/1.1 200"))
  })
  with_raw_server(app, conn => {
    conn.write(
      @utf8.encode(
        "GET /assets/hello.txt HTTP/1.1\r\nHost: test\r\nContent-Length: 2000\r\n\r\n",
      ),
    )
    conn.write(@utf8.encode("x".repeat(2000)))
    let head = read_http_head(conn)
    assert_true(head.has_prefix("HTTP/1.1 413"))
  })
  @fs.rmdir(dir, recursive=true)
}
