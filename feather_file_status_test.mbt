///|
async test "file responses with informational statuses carry no body framing" {
  let dir = @fs.tmpdir(prefix="feather-file-informational")
  @fs.write_file(dir + "/early.txt", "not sent")
  let app = @feather.App::new().get("/early", fn(ctx) {
    ctx.file(103, dir + "/early.txt")
  })
  with_raw_server(app, conn => {
    conn.write(
      @utf8.encode(
        "GET /early HTTP/1.1\r\nHost: test\r\nConnection: close\r\n\r\n",
      ),
    )
    let head = read_http_head(conn)
    assert_true(head.has_prefix("HTTP/1.1 103"), msg=head)
    assert_false(head.contains("Content-Length"), msg=head)
    assert_false(head.contains("not sent"), msg=head)
  })
  @fs.rmdir(dir, recursive=true)
}
