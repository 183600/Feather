///|
/// Whether a fresh TCP connection to `port` is refused (the listener is gone).
async fn port_refuses_connections(port : Int) -> Bool {
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
async test "serve_with_until stops the server when the stop task resolves" {
  let app = @feather.App::new().get("/hello", fn(ctx) { ctx.text(200, "hi") })
  @async.with_task_group(group => {
    let server = @http.Server(@socket.Addr::parse("127.0.0.1:0"))
    let port = server.addr.port()
    let finished : Ref[Bool] = Ref(false)
    group.spawn_bg(no_wait=true, () => {
      app.serve_with_until(server, stop=() => { @async.sleep(200) })
      finished.val = true
    })
    @async.sleep(50)
    let client = @http.Client("http://127.0.0.1:\{port}")
    let response = client.get("/hello")
    assert_eq(response.code, 200)
    assert_eq(client.read_all().text(), "hi")
    client.close()
    let mut waited = 0
    while !finished.val && waited < 200 {
      @async.sleep(10)
      waited = waited + 1
    }
    assert_true(finished.val)
    assert_true(port_refuses_connections(port))
  })
}

///|
async test "serve_with_until cancels a blocked accept loop" {
  let app = @feather.App::new().get("/hello", fn(ctx) { ctx.text(200, "hi") })
  @async.with_task_group(group => {
    let server = @http.Server(@socket.Addr::parse("127.0.0.1:0"))
    let port = server.addr.port()
    let finished : Ref[Bool] = Ref(false)
    group.spawn_bg(no_wait=true, () => {
      app.serve_with_until(server, stop=() => { @async.sleep(10) })
      finished.val = true
    })
    @async.sleep(50)
    assert_true(port_refuses_connections(port))
    let mut waited = 0
    while !finished.val && waited < 200 {
      @async.sleep(10)
      waited = waited + 1
    }
    assert_true(finished.val)
  })
}
