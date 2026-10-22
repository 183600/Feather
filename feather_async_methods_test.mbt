///|
fn async_methods_app() -> @feather.App {
  @feather.App::new()
    .sse("/events", async fn(_ctx, sse) { sse.close() })
    .stream("/stream", async fn(_ctx, out) { out.close() })
    .websocket("/ws", async fn(_ctx, ws) { ws.close() })
}

///|
fn method_response(app : @feather.App, method : String, path : String) -> @feather.Response {
  app.respond({ method, path, headers: Map([]), body: "" })
}

///|
test "automatic OPTIONS includes asynchronous endpoints" {
  let app = async_methods_app()
  for path in ["/events", "/stream"] {
    let response = method_response(app, "OPTIONS", path)
    assert_eq(response.status, 204, msg=path)
    assert_eq(response.headers.get("Allow"), Some("GET, HEAD"), msg=path)
  }
  let websocket = method_response(app, "OPTIONS", "/ws")
  assert_eq(websocket.status, 204)
  // A WebSocket upgrade cannot be described by HEAD.
  assert_eq(websocket.headers.get("Allow"), Some("GET"))
  // Neither an ordinary GET route nor an explicit HEAD route can shadow the
  // upgrade, so the combined Allow still must not advertise HEAD.
  let shadowed = @feather.App::new()
    .get("/ws", fn(ctx) { ctx.text(200, "get") })
    .head("/ws", fn(ctx) { ctx.text(200, "head") })
    .websocket("/ws", async fn(_ctx, ws) { ws.close() })
  assert_eq(
    method_response(shadowed, "OPTIONS", "/ws").headers.get("Allow"),
    Some("GET"),
  )
}

///|
test "automatic OPTIONS combines async endpoints with ordinary routes" {
  let app = @feather.App::new()
    .sse("/events", async fn(_ctx, sse) { sse.close() })
    .post("/events", fn(ctx) { ctx.text(201, "post") })
  let response = method_response(app, "OPTIONS", "/events")
  assert_eq(response.status, 204)
  assert_eq(response.headers.get("Allow"), Some("GET, HEAD, POST"))
}

///|
test "non-OPTIONS methods still fall through to the ordinary router" {
  let app = async_methods_app()
  // Async endpoints only participate in automatic OPTIONS; other methods keep
  // the established fallback/404 behaviour.
  assert_eq(method_response(app, "POST", "/ws").status, 404)
  assert_eq(method_response(app, "POST", "/events").status, 404)
}

///|
test "explicit ordinary routes win over asynchronous method handling" {
  let app = @feather.App::new()
    .sse("/events", async fn(_ctx, sse) { sse.close() })
    .options("/events", fn(ctx) { ctx.text(200, "explicit options") })
    .post("/events", fn(ctx) { ctx.text(201, "ordinary post") })
  let options = method_response(app, "OPTIONS", "/events")
  assert_eq(options.status, 200)
  assert_eq(options.body, "explicit options")
  let post = method_response(app, "POST", "/events")
  assert_eq(post.status, 201)
  assert_eq(post.body, "ordinary post")
}

