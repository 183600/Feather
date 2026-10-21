///|
/// Busy-wait synchronously without yielding. Used only where a handler must
/// observe a flag change without giving the event loop a chance to run.
fn drain_block_ms(ms : Int64) -> Unit {
  let deadline = @async.now() + ms
  while @async.now() < deadline {
    ()
  }
}

///|
async fn drain_port_refuses(port : Int) -> Bool {
  try {
    @async.with_timeout(2000, () => {
      let conn = @socket.Tcp::connect(@socket.Addr::parse("127.0.0.1:\{port}"))
      conn.close()
    })
    false
  } catch {
    @async.TimeoutError => false
    _ => true
  }
}

///|
/// Read from `conn` until `needle` shows up or `max_iters` read attempts pass.
async fn drain_read_until(conn : @socket.Tcp, needle : String, max_iters : Int) -> String {
  let mut received = ""
  let mut iters = 0
  while !received.contains(needle) && iters < max_iters {
    match conn.read_some() {
      Some(chunk) => received = received + @utf8.decode_lossy(chunk)
      None => break
    }
    iters = iters + 1
  }
  received
}

///|
async test "graceful shutdown waits for in-flight requests to finish" {
  let app = @feather.App::new().post("/upload", fn(ctx) {
    ctx.text(200, "uploaded:" + ctx.request.body)
  })
  @async.with_task_group(group => {
    let server = @http.Server(@socket.Addr::parse("127.0.0.1:0"))
    let port = server.addr.port()
    let finished : Ref[Bool] = Ref(false)
    group.spawn_bg(no_wait=true, () => {
      app.serve_with_graceful_until(
        server,
        stop=() => { @async.sleep(120) },
        drain_timeout=3000,
      )
      finished.val = true
    })
    @async.sleep(50)
    let conn = @socket.Tcp::connect(@socket.Addr::parse("127.0.0.1:\{port}"))
    conn.write(
      @utf8.encode(
        "POST /upload HTTP/1.1\r\nHost: localhost\r\nContent-Length: 5\r\nConnection: close\r\n\r\n",
      ),
    )
    @async.sleep(200)
    conn.write(@utf8.encode("hello"))
    let received = drain_read_until(conn, "uploaded:hello", 200)
    conn.close()
    assert_true(received.contains("200 OK"))
    assert_true(received.contains("uploaded:hello"))
    let mut waited = 0
    while !finished.val && waited < 400 {
      @async.sleep(10)
      waited = waited + 1
    }
    assert_true(finished.val)
    assert_true(drain_port_refuses(port))
  })
}

///|
async test "graceful shutdown cancels a stalled request after the drain timeout" {
  let app = @feather.App::new().post("/upload", fn(ctx) {
    ctx.text(200, ctx.request.body)
  })
  @async.with_task_group(group => {
    let server = @http.Server(@socket.Addr::parse("127.0.0.1:0"))
    let port = server.addr.port()
    let finished : Ref[Bool] = Ref(false)
    let started : Ref[Bool] = Ref(false)
    group.spawn_bg(no_wait=true, () => {
      started.val = true
      app.serve_with_graceful_until(
        server,
        stop=() => { @async.sleep(150) },
        drain_timeout=200,
      )
      finished.val = true
    })
    @async.sleep(50)
    let conn = @socket.Tcp::connect(@socket.Addr::parse("127.0.0.1:\{port}"))
    conn.write(
      @utf8.encode(
        "POST /upload HTTP/1.1\r\nHost: localhost\r\nContent-Length: 100\r\nConnection: close\r\n\r\n",
      ),
    )
    let mut waited = 0
    while !finished.val && waited < 600 {
      @async.sleep(10)
      waited = waited + 1
    }
    conn.close()
    assert_true(started.val)
    assert_true(finished.val)
    assert_true(drain_port_refuses(port))
  })
}

///|
async test "graceful shutdown refuses new requests on kept-alive connections" {
  let app = @feather.App::new().get("/hello", fn(ctx) { ctx.text(200, "hi") })
  @async.with_task_group(group => {
    let server = @http.Server(@socket.Addr::parse("127.0.0.1:0"))
    let port = server.addr.port()
    let finished : Ref[Bool] = Ref(false)
    group.spawn_bg(no_wait=true, () => {
      app.serve_with_graceful_until(
        server,
        stop=() => { @async.sleep(150) },
        drain_timeout=2000,
      )
      finished.val = true
    })
    @async.sleep(50)
    let conn = @socket.Tcp::connect(@socket.Addr::parse("127.0.0.1:\{port}"))
    conn.write(
      @utf8.encode("GET /hello HTTP/1.1\r\nHost: localhost\r\n\r\n"),
    )
    let first = drain_read_until(conn, "hi", 100)
    assert_true(first.contains("200 OK"))
    assert_true(first.contains("hi"))
    // The drain starts once `stop` (150ms) resolves; send a second request on
    // the same kept-alive connection while the server is draining.
    @async.sleep(170)
    conn.write(
      @utf8.encode("GET /hello HTTP/1.1\r\nHost: localhost\r\n\r\n"),
    )
    let second = drain_read_until(conn, "503", 100)
    conn.close()
    assert_true(second.contains("503"))
    let mut waited = 0
    while !finished.val && waited < 300 {
      @async.sleep(10)
      waited = waited + 1
    }
    assert_true(finished.val)
  })
}

///|
async test "graceful shutdown closes the listener before draining" {
  let app = @feather.App::new().post("/upload", fn(ctx) {
    ctx.text(200, ctx.request.body)
  })
  @async.with_task_group(group => {
    let server = @http.Server(@socket.Addr::parse("127.0.0.1:0"))
    let port = server.addr.port()
    let finished : Ref[Bool] = Ref(false)
    group.spawn_bg(no_wait=true, () => {
      app.serve_with_graceful_until(
        server,
        stop=() => { @async.sleep(120) },
        drain_timeout=3000,
      )
      finished.val = true
    })
    @async.sleep(40)
    let conn = @socket.Tcp::connect(@socket.Addr::parse("127.0.0.1:\{port}"))
    conn.write(
      @utf8.encode(
        "POST /upload HTTP/1.1\r\nHost: localhost\r\nContent-Length: 4\r\nConnection: close\r\n\r\n",
      ),
    )
    conn.write(@utf8.encode("data"))
    let received = drain_read_until(conn, "data", 100)
    conn.close()
    assert_true(received.contains("200 OK"))
    let mut waited = 0
    while !finished.val && waited < 300 {
      @async.sleep(10)
      waited = waited + 1
    }
    assert_true(finished.val)
    assert_true(drain_port_refuses(port))
  })
}
