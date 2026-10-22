///|
async test "dynamic request timeout covers response body writes" {
  let dir = @fs.tmpdir(prefix="feather-dynamic-timeout")
  @fs.write_file(dir + "/large.bin", "x".repeat(8 * 1024 * 1024))
  let app = @feather.App::new()
    .request_timeout(10)
    .get("/large", fn(ctx) { ctx.file(200, dir + "/large.bin") })
  with_raw_server(app, conn => {
    conn.write(
      @utf8.encode(
        "GET /large HTTP/1.1\r\nHost: test\r\nConnection: close\r\n\r\n",
      ),
    )
    let head = read_http_head(conn)
    assert_true(head.has_prefix("HTTP/1.1 200"), msg=head)
    let header_end = match head.find("\r\n\r\n") {
      Some(index) => index + 4
      None => fail("missing response header terminator")
    }
    let received = head.length() - header_end
    // The client deliberately stops reading. Once the socket buffer fills,
    // the write must be cancelled by the request timeout and the connection
    // closed; it must not stay blocked forever or switch to a 504 after the
    // 200 response has already started.
    @async.sleep(100)
    let rest = @async.with_timeout(3000, () => conn.read_all().text()) catch {
      @async.TimeoutError => fail("timed-out response connection stayed open")
      _ => ""
    }
    assert_false(rest.contains("HTTP/1.1 504"), msg=rest)
    assert_true(
      received + rest.length() < 8 * 1024 * 1024,
      msg="client received the full body despite the request timeout",
    )
  })
  @fs.rmdir(dir, recursive=true)
}
