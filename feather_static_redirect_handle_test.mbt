///|
/// Number of open descriptors on Linux whose target is `prefix` or a file below
/// it, or `None` on hosts without `/proc`. Restricting the count to the test's
/// temporary directory keeps unrelated descriptors held by concurrently running
/// tests from making the leak check flaky.
async fn static_redirect_fd_count(prefix : String) -> Int? {
  let dir = @fs.opendir("/proc/self/fd") catch { _ => return None }
  let entries = dir.read_all() catch {
    _ => {
      dir.close()
      return None
    }
  }
  dir.close()
  let mut count = 0
  for entry in entries {
    let target = @fs.realpath("/proc/self/fd/" + entry) catch { _ => "" }
    if target == prefix || target.has_prefix(prefix + "/") {
      count = count + 1
    }
  }
  Some(count)
}

///|
/// Issue one keep-alive request on an already connected raw socket.
async fn static_redirect_get(conn : @socket.Tcp, path : String) -> String {
  conn.write(
    @utf8.encode(
      "GET " + path + " HTTP/1.1\r\nHost: test\r\n\r\n",
    ),
  )
  @async.with_timeout(2000, () => read_http_head(conn)) catch { _ => "" }
}

///|
async test "static mount root redirects release their probe handles" {
  let dir = @fs.tmpdir(prefix="feather-static-redirect-handles")
  @fs.write_file(dir + "/index.html", "<h1>root</h1>")
  let app = @feather.App::new().static_files("/assets", dir)
  with_raw_server(app, conn => {
    // Warm up the connection, then compare snapshots taken on the same
    // keep-alive socket so connection descriptors cannot skew the result.
    let warm = static_redirect_get(conn, "/assets")
    assert_true(warm.has_prefix("HTTP/1.1 301"), msg=warm)
    match static_redirect_fd_count(dir) {
      Some(before) => {
        let first = static_redirect_get(conn, "/assets")
        assert_true(first.has_prefix("HTTP/1.1 301"), msg=first)
        let second = static_redirect_get(conn, "/assets?theme=dark")
        assert_true(second.has_prefix("HTTP/1.1 301"), msg=second)
        match static_redirect_fd_count(dir) {
          Some(after) =>
            assert_true(
              after <= before,
              msg="root redirect leaked a file descriptor: \{before} -> \{after}",
            )
          None => ()
        }
      }
      None => ()
    }
  })
  @fs.rmdir(dir, recursive=true)
}
