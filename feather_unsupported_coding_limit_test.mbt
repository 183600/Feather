///|
async fn send_unsupported_chunked_request(
  conn : @socket.Tcp,
  method : String,
  path : String,
) -> String {
  conn.write(
    @utf8.encode(
      method +
      " " +
      path +
      " HTTP/1.1\r\nHost: test\r\n" +
      "Content-Encoding: deflate\r\n" +
      "Transfer-Encoding: chunked\r\nConnection: close\r\n\r\n" +
      "400\r\n" +
      "x".repeat(1024) +
      "\r\n0\r\n\r\n",
    ),
  )
  @async.with_timeout(2000, () => read_http_head(conn)) catch { _ => "" }
}

///|
async test "unsupported request coding wins over an oversized static body" {
  let dir = @fs.tmpdir(prefix="feather-unsupported-static-limit")
  @fs.write_file(dir + "/asset.txt", "asset")
  let app = @feather.App::new().static_files("/assets", dir)
  with_raw_server(app, conn => {
    let head = send_unsupported_chunked_request(
      conn,
      "GET",
      "/assets/asset.txt",
    )
    assert_true(head.has_prefix("HTTP/1.1 415"), msg=head)
  })
  @fs.rmdir(dir, recursive=true)
}

///|
async test "unsupported request coding wins over an oversized dynamic body" {
  let app = @feather.App::new().post("/echo", fn(ctx) {
    ctx.text(200, ctx.request.body)
  })
  with_raw_server(app, conn => {
    let head = send_unsupported_chunked_request(conn, "POST", "/echo")
    assert_true(head.has_prefix("HTTP/1.1 415"), msg=head)
  })
}
