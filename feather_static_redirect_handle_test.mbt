///|
/// Number of open file descriptors on Linux, or `None` on hosts without
/// `/proc`. The directory handle used for the count is included on both sides
/// of a before/after comparison, so its own descriptor cancels out.
async fn static_redirect_fd_count() -> Int? {
  let dir = @fs.opendir("/proc/self/fd") catch { _ => return None }
  let entries = dir.read_all() catch {
    _ => {
      dir.close()
      return None
    }
  }
  dir.close()
  Some(entries.length())
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
    match static_redirect_fd_count() {
      Some(before) => {
        let first = static_redirect_get(conn, "/assets")
        assert_true(first.has_prefix("HTTP/1.1 301"), msg=first)
        let second = static_redirect_get(conn, "/assets?theme=dark")
        assert_true(second.has_prefix("HTTP/1.1 301"), msg=second)
        match static_redirect_fd_count() {
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
