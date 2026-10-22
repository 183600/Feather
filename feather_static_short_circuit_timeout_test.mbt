///|
async test "static middleware file responses close after the response starts" {
  let dir = @fs.tmpdir(prefix="feather-static-short-circuit-timeout")
  @fs.write_file(dir + "/large.bin", "x".repeat(8 * 1024 * 1024))
  let app = @feather.App::new()
    .static_files_with("/assets", dir, [
      fn(_next) {
        fn(ctx) { ctx.file(200, dir + "/large.bin") }
      },
    ])
    .request_timeout(10)
  with_raw_server(app, conn => {
    conn.write(
      @utf8.encode(
        "GET /assets/ignored.bin HTTP/1.1\r\nHost: test\r\nConnection: close\r\n\r\n",
      ),
    )
    let head = read_http_head(conn)
    assert_true(head.has_prefix("HTTP/1.1 200"), msg=head)
    @async.sleep(100)
    let rest = conn.read_all().text()
    assert_false(rest.contains("HTTP/1.1 504"), msg=rest)
  })
  @fs.rmdir(dir, recursive=true)
}
