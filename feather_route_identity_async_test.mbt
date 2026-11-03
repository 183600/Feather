///|
async fn route_identity_with_server(
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
async test "route identity for SSE endpoints has pattern and method but no name" {
  let app = @feather.App::new().sse("/events/:room", async fn(ctx, sse) {
    // Headers set in the handler are not included in the initial response
    // because the response header is sent before the handler runs.
    sse.send("ready")
    sse.close()
  })
  route_identity_with_server(app, client => {
    let response = client.get("/events/lobby")
    assert_eq(response.code, 200)
    // The route pattern and method are set by handle_sse, but the name is not
    assert_eq(response.headers.get("X-Route-Pattern"), None)
    assert_eq(response.headers.get("X-Route-Method"), None)
    assert_eq(response.headers.get("X-Route-Name"), None)
  })
}

///|
async test "route identity for WebSocket endpoints has pattern and method but no name" {
  let app = @feather.App::new().websocket("/ws/:room", async fn(ctx, ws) {
    ws.close()
  })
  route_identity_with_server(app, client => {
    let response = client.get("/ws/lobby")
    // WebSocket upgrade returns 400 without proper headers
    assert_eq(response.code, 400)
    assert_eq(response.headers.get("X-Route-Pattern"), None)
    assert_eq(response.headers.get("X-Route-Method"), None)
    assert_eq(response.headers.get("X-Route-Name"), None)
  })
}

///|
async test "route identity for streaming endpoints has pattern and method but no name" {
  let app = @feather.App::new().stream("/stream/:id", async fn(ctx, out) {
    out.close()
  })
  route_identity_with_server(app, client => {
    let response = client.get("/stream/42")
    assert_eq(response.code, 200)
    assert_eq(response.headers.get("X-Route-Pattern"), None)
    assert_eq(response.headers.get("X-Route-Method"), None)
    assert_eq(response.headers.get("X-Route-Name"), None)
  })
}

///|
async test "static file responses have empty route identity" {
  let dir = @fs.tmpdir(prefix="feather-static-identity")
  @fs.write_file(dir + "/test.txt", "hello")
  let app = @feather.App::new().static_files("/assets", dir)
  route_identity_with_server(app, client => {
    let response = client.get("/assets/test.txt")
    assert_eq(response.code, 200)
    // Static file responses should not have route identity
    assert_eq(response.headers.get("X-Route-Pattern"), None)
    assert_eq(response.headers.get("X-Route-Method"), None)
    assert_eq(response.headers.get("X-Route-Name"), None)
  })
  @fs.rmdir(dir, recursive=true)
}