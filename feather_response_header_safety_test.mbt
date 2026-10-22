///|
test "response header values cannot inject extra header lines" {
  let ctx = @feather.create_context()
  ctx.set_header("X-Echo", "ok\r\nX-Injected: yes\r\n")
  assert_eq(
    ctx.response.headers.get("X-Echo"),
    Some("okX-Injected: yes"),
  )
  assert_eq(ctx.response.headers.get("X-Injected"), None)
}

///|
test "response header names must be non-empty HTTP tokens" {
  let ctx = @feather.create_context()
  ctx.set_header("X\r\nInjected", "yes")
  ctx.set_header("Bad Name", "yes")
  ctx.set_header("", "yes")
  ctx.set_header("X-Good", "yes")
  assert_eq(ctx.response.headers.length(), 1)
  assert_eq(ctx.response.headers.get("X-Good"), Some("yes"))
}

///|
test "append_header sanitizes both the name and the appended value" {
  let ctx = @feather.create_context()
  ctx.append_header("Vary", "Origin")
  ctx.append_header("Vary", "Accept\r\nX-Injected: yes")
  assert_eq(ctx.response.headers.get("Vary"), Some("Origin, AcceptX-Injected: yes"))
  ctx.append_header("Bad\r\nName", "value")
  assert_eq(ctx.response.headers.length(), 1)
}

///|
test "set_header_if_absent reports an invalid name instead of setting it" {
  let ctx = @feather.create_context()
  assert_false(ctx.set_header_if_absent("Bad Name", "value"))
  assert_eq(ctx.response.headers.length(), 0)
  assert_true(ctx.set_header_if_absent("X-Default", "a\r\nb"))
  assert_eq(ctx.response.headers.get("X-Default"), Some("ab"))
  assert_false(ctx.set_header_if_absent("x-default", "other"))
  assert_eq(ctx.response.headers.length(), 1)
  assert_eq(ctx.response.headers.get("X-Default"), Some("ab"))
}

///|
async test "the server does not emit a forged header from handler input" {
  let app = @feather.App::new().get("/echo", fn(ctx) {
    ctx.set_header("X-Echo", ctx.query("value"))
    ctx.text(200, "ok")
  })
  with_raw_server(app, conn => {
    conn.write(
      @utf8.encode(
        "GET /echo?value=ok%0D%0AX-Injected:%20yes HTTP/1.1\r\nHost: test\r\nConnection: close\r\n\r\n",
      ),
    )
    let head = @async.with_timeout(2000, () => read_http_head(conn)) catch {
      _ => ""
    }
    assert_true(head.has_prefix("HTTP/1.1 200"))
    assert_true(head.contains("X-Echo: okX-Injected: yes\r\n"))
    assert_false(head.contains("\r\nX-Injected: yes\r\n"))
  })
}
