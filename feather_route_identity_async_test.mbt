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
async test "route identity is empty for SSE endpoints" {
  let app = @feather.App::new().sse("/events/:room", async fn(ctx, sse) {
    ctx.set_header("X-Route-Pattern", ctx.route_pattern())
    ctx.set_header("X-Route-Method", ctx.route_method())
    ctx.set_header("X-Route-Name", ctx.route_name())
    sse.send("ready")
    sse.close()
  })
  with_server(app, client => {
    let response = client.get("/events/lobby")
    assert_eq(response.code, 200)
    assert_eq(response.headers.get("X-Route-Pattern"), Some(""))
    assert_eq(response.headers.get("X-Route-Method"), Some(""))
    assert_eq(response.headers.get("X-Route-Name"), Some(""))
  })
}

///|
async test "route identity is empty for WebSocket endpoints" {
  let app = @feather.App::new().websocket("/ws/:room", async fn(ctx, ws) {
    ctx.set_header("X-Route-Pattern", ctx.route_pattern())
    ctx.set_header("X-Route-Method", ctx.route_method())
    ctx.set_header("X-Route-Name", ctx.route_name())
    ws.close()
  })
  with_server(app, client => {
    let response = client.get("/ws/lobby")
    // WebSocket upgrade returns 400 without proper headers
    assert_eq(response.code, 400)
    assert_eq(response.headers.get("X-Route-Pattern"), Some(""))
    assert_eq(response.headers.get("X-Route-Method"), Some(""))
    assert_eq(response.headers.get("X-Route-Name"), Some(""))
  })
}

///|
async test "route identity is empty for streaming endpoints" {
  let app = @feather.App::new().stream("/stream/:id", async fn(ctx, out) {
    ctx.set_header("X-Route-Pattern", ctx.route_pattern())
    ctx.set_header("X-Route-Method", ctx.route_method())
    ctx.set_header("X-Route-Name", ctx.route_name())
    out.close()
  })
  with_server(app, client => {
    let response = client.get("/stream/42")
    assert_eq(response.code, 200)
    assert_eq(response.headers.get("X-Route-Pattern"), Some(""))
    assert_eq(response.headers.get("X-Route-Method"), Some(""))
    assert_eq(response.headers.get("X-Route-Name"), Some(""))
  })
}

///|
async test "static file responses have empty route identity" {
  let dir = @fs.tmpdir(prefix="feather-static-identity")
  @fs.write_file(dir + "/test.txt", "hello")
  let app = @feather.App::new().static_files("/assets", dir)
  with_server(app, client => {
    let response = client.get("/assets/test.txt")
    assert_eq(response.code, 200)
    // Static file responses should not have route identity
    assert_eq(response.headers.get("X-Route-Pattern"), None)
    assert_eq(response.headers.get("X-Route-Method"), None)
    assert_eq(response.headers.get("X-Route-Name"), None)
  })
  @fs.rmdir(dir, recursive=true)
}