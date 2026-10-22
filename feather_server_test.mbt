///|
async fn with_server(
  app : @feather.App,
  run : async (@http.Client) -> Unit,
) -> Unit {
  @async.with_task_group(group => {
    let server = @http.Server(@socket.Addr::parse("127.0.0.1:0"))
    let addr = server.addr
    group.spawn_bg(no_wait=true, () => app.serve_with(server))
    @async.sleep(50)
    let client = @http.Client("http://127.0.0.1:\{addr.port()}")
    defer client.close()
    run(client)
    server.close()
  })
}

///|
/// Like `with_server`, but hands the test a raw TCP connection so it can
/// drive partial requests and observe the bytes the server actually sends.
async fn with_raw_server(
  app : @feather.App,
  run : async (@socket.Tcp) -> Unit,
) -> Unit {
  @async.with_task_group(group => {
    let server = @http.Server(@socket.Addr::parse("127.0.0.1:0"))
    let addr = server.addr
    group.spawn_bg(no_wait=true, () => app.serve_with(server))
    @async.sleep(50)
    let conn = @socket.Tcp::connect(
      @socket.Addr::parse("127.0.0.1:\{addr.port()}"),
    )
    defer conn.close()
    run(conn)
    server.close()
  })
}

///|
/// Read from a raw connection until the end of the response head.
async fn read_http_head(conn : @socket.Tcp) -> String {
  let buffer = @buffer.Buffer::Buffer(size_hint=1024)
  while !@utf8.decode_lossy(buffer.to_bytes()).contains("\r\n\r\n") {
    match conn.read_some() {
      Some(chunk) => buffer.write_bytes(chunk)
      None => break
    }
  }
  @utf8.decode_lossy(buffer.to_bytes())
}

///|
async test "server serves text route" {
  let app = @feather.App::new().get("/hello", fn(ctx) {
    ctx.text(200, "hello world")
  })
  with_server(app, client => {
    let response = client.get("/hello")
    assert_eq(response.code, 200)
    assert_eq(client.read_all().text(), "hello world")
  })
}

///|
async test "server closes the connection when the client requests it" {
  let app = @feather.App::new().get("/hello", fn(ctx) {
    ctx.text(200, "hello")
  })
  with_raw_server(app, conn => {
    conn.write(
      @utf8.encode(
        "GET /hello HTTP/1.1\r\nHost: test\r\nConnection: close\r\n\r\n",
      ),
    )
    let head = @async.with_timeout(2000, () => read_http_head(conn)) catch {
      _ => ""
    }
    assert_true(head.has_prefix("HTTP/1.1 200"))
    let closed = try {
      @async.with_timeout(2000, () => {
        let mut done = false
        while !done {
          match conn.read_some() {
            Some(_) => ()
            None => done = true
          }
        }
      })
      true
    } catch {
      _ => false
    }
    assert_true(closed)
  })
}

///|
async test "server exposes route parameters" {
  let app = @feather.App::new().get("/users/:id", fn(ctx) {
    ctx.text(200, "user=" + ctx.param("id"))
  })
  with_server(app, client => {
    let response = client.get("/users/42")
    assert_eq(response.code, 200)
    assert_eq(client.read_all().text(), "user=42")
  })
}

///|
async test "server serves json route" {
  let app = @feather.App::new().get("/api/status", fn(ctx) {
    ctx.json(200, { "ok": "true" })
  })
  with_server(app, client => {
    let response = client.get("/api/status")
    assert_eq(response.code, 200)
    assert_eq(client.read_all().text(), "{\"ok\":\"true\"}")
  })
}

///|
async test "server returns 404 for unknown route" {
  let app = @feather.App::new().get("/known", fn(ctx) { ctx.text(200, "known") })
  with_server(app, client => {
    let response = client.get("/unknown")
    assert_eq(response.code, 404)
    assert_eq(client.read_all().text(), "404 Not Found")
  })
}

///|
async test "server returns 405 for wrong method" {
  let app = @feather.App::new().get("/resource", fn(ctx) { ctx.text(200, "ok") })
  with_server(app, client => {
    let response = client.post("/resource", "")
    assert_eq(response.code, 405)
    assert_eq(client.read_all().text(), "405 Method Not Allowed")
  })
}

///|
async test "server echoes form values" {
  let app = @feather.App::new().post("/echo", fn(ctx) {
    ctx.text(200, ctx.form("name"))
  })
  with_server(app, client => {
    let response = client.post(
      "/echo",
      "name=feather",
      extra_headers=Map([
        (
          @http.CaseInsensitiveString("Content-Type"),
          "application/x-www-form-urlencoded",
        ),
      ]),
    )
    assert_eq(response.code, 200)
    assert_eq(client.read_all().text(), "feather")
  })
}

///|
async test "server reads query parameters" {
  let app = @feather.App::new().get("/search", fn(ctx) {
    ctx.text(200, ctx.query("q"))
  })
  with_server(app, client => {
    let response = client.get("/search?q=feather%20web")
    assert_eq(response.code, 200)
    assert_eq(client.read_all().text(), "feather web")
  })
}

///|
async test "server serves wildcard route" {
  let app = @feather.App::new().get("/static/*path", fn(ctx) {
    ctx.text(200, "path=" + ctx.param("path"))
  })
  with_server(app, client => {
    let response = client.get("/static/css/app.css")
    assert_eq(response.code, 200)
    assert_eq(client.read_all().text(), "path=css/app.css")
  })
}

///|
async test "server applies middleware" {
  let app = @feather.App::new()
    .use(@feather.middleware_cors())
    .get("/hello", fn(ctx) { ctx.text(200, "hello") })
  with_server(app, client => {
    let response = client.get("/hello")
    assert_eq(response.code, 200)
    assert_eq(
      response.headers.get(
        @http.CaseInsensitiveString("Access-Control-Allow-Origin"),
      ),
      Some("*"),
    )
    ignore(client.read_all())
  })
}

///|
async test "server recovers from handler errors" {
  let app = @feather.App::new()
    .use(@feather.middleware_recover())
    .get("/boom", fn(_ctx) raise { raise Failure("boom") })
  with_server(app, client => {
    let response = client.get("/boom")
    assert_eq(response.code, 500)
    assert_eq(client.read_all().text(), "Internal Server Error")
  })
}

///|
async test "server rejects oversized bodies" {
  let app = @feather.App::new().post("/upload", fn(ctx) {
    ctx.text(200, ctx.request.body)
  })
  with_server(app, client => {
    let response = client.post("/upload", "x".repeat(2000))
    assert_eq(response.code, 413)
    ignore(client.read_all())
  })
}

///|
async test "server answers expect 100-continue before reading the body" {
  let app = @feather.App::new().post("/upload", fn(ctx) {
    ctx.text(200, ctx.request.body)
  })
  with_raw_server(app, conn => {
    conn.write(
      @utf8.encode(
        "POST /upload HTTP/1.1\r\nHost: test\r\nContent-Length: 4\r\nExpect: 100-continue\r\n\r\n",
      ),
    )
    let interim = @async.with_timeout(2000, () => read_http_head(conn)) catch {
      _ => ""
    }
    assert_true(interim.has_prefix("HTTP/1.1 100"))
    conn.write(@utf8.encode("ping"))
    let final = @async.with_timeout(2000, () => read_http_head(conn)) catch {
      _ => ""
    }
    assert_true(final.has_prefix("HTTP/1.1 200"))
  })
}

///|
async test "server closes the connection after an oversized body" {
  let app = @feather.App::new().post("/upload", fn(ctx) {
    ctx.text(200, ctx.request.body)
  })
  with_raw_server(app, conn => {
    conn.write(
      @utf8.encode(
        "POST /upload HTTP/1.1\r\nHost: test\r\nContent-Length: 2000\r\n\r\n",
      ),
    )
    conn.write(@utf8.encode("x".repeat(2000)))
    let head = read_http_head(conn)
    assert_true(head.has_prefix("HTTP/1.1 413"))
    let closed = try {
      @async.with_timeout(2000, () => {
        let mut done = false
        while !done {
          match conn.read_some() {
            Some(_) => ()
            None => done = true
          }
        }
      })
      true
    } catch {
      _ => false
    }
    assert_true(closed)
  })
}

///|
async test "server handles head requests" {
  let app = @feather.App::new().get("/head", fn(ctx) { ctx.text(200, "body") })
  with_server(app, client => {
    client.request(@http.RequestMethod::Head, "/head")
    let response = client.end_request()
    assert_eq(response.code, 200)
    ignore(client.read_all())
  })
}

///|
async test "server records the client ip without the port" {
  let app = @feather.App::new().get("/ip", fn(ctx) { ctx.text(200, ctx.ip()) })
  with_server(app, client => {
    let response = client.get("/ip")
    assert_eq(response.code, 200)
    let body = client.read_all().text()
    assert_eq(body, "127.0.0.1")
  })
}

///|
async test "server strips bodies from no-content responses" {
  let app = @feather.App::new().get("/empty", fn(ctx) {
    ctx.text(200, "payload")
    ctx.status(204)
  })
  with_server(app, client => {
    let response = client.get("/empty")
    assert_eq(response.code, 204)
    assert_eq(
      response.headers.get(@http.CaseInsensitiveString("Content-Length")),
      None,
    )
    assert_eq(client.read_all().text(), "")
    let follow_up = client.get("/empty")
    assert_eq(follow_up.code, 204)
    assert_eq(client.read_all().text(), "")
  })
}

///|
async test "connect success responses are bodyless and unframed" {
  let app = @feather.App::new().connect("/tunnel", fn(ctx) {
    ctx.text(200, "hello-connect")
  })
  with_raw_server(app, conn => {
    conn.write(
      @utf8.encode(
        "CONNECT /tunnel HTTP/1.1\r\nHost: test\r\nConnection: close\r\n\r\n",
      ),
    )
    let head = @async.with_timeout(2000, () => read_http_head(conn)) catch {
      _ => ""
    }
    assert_true(head.has_prefix("HTTP/1.1 200"), msg=head)
    let lower = head.to_lower()
    assert_false(lower.contains("content-length"), msg=head)
    assert_false(lower.contains("transfer-encoding"), msg=head)
  })
}
