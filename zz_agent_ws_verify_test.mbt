///|
/// `moonbitlang/async`'s `@websocket.from_http_server` (0.22.5) writes the `101`
/// handshake response itself, takes no extra headers, and exposes no public
/// `Conn` constructor, so a pass-through websocket handshake cannot carry
/// middleware headers or cookies in Feather. Middleware that answers without
/// calling through does carry them, which this test pins.
async test "agent websocket middleware short-circuit carries response headers" {
  let app = @feather.App::new()
    .use(fn(next) {
      fn(ctx) raise {
        ctx.set_header("X-App", "feather")
        ctx.set_cookie("seen", "yes", path="/")
        if ctx.header("X-Token") == "ok" {
          next(ctx)
        } else {
          ctx.text(401, "unauthorized")
        }
      }
    })
    .websocket("/ws", fn(_ctx, _ws) { () })
  with_server(app, client => {
    let response = client.get("/ws")
    assert_eq(response.code, 401)
    assert_eq(
      response.headers.get(@http.CaseInsensitiveString("X-App")),
      Some("feather"),
    )
    assert_eq(client.read_all().text(), "unauthorized")
  })
}

///|
async test "agent empty dynamic body must not keep middleware content length" {
  let app = @feather.App::new()
    .use(fn(next) {
      fn(ctx) {
        ctx.set_header("Content-Length", "999")
        next(ctx)
      }
    })
    .get("/empty", fn(ctx) { ctx.text(200, "") })
  with_raw_server(app, conn => {
    conn.write(
      @utf8.encode(
        "GET /empty HTTP/1.1\r\nHost: test\r\nConnection: close\r\n\r\n",
      ),
    )
    let head = read_http_head(conn)
    assert_true(head.has_prefix("HTTP/1.1 200"))
    assert_false(head.contains("Content-Length: 999"))
  })
}
