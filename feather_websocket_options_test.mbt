///|
test "server-wide OPTIONS does not advertise HEAD for a WebSocket-only app" {
  let app = @feather.App::new().websocket("/ws", async fn(_ctx, _ws) { () })
  let response = app.respond({
    method: "OPTIONS",
    path: "*",
    headers: Map([]),
    body: "",
  })
  assert_eq(response.status, 204)
  assert_eq(response.headers.get("Allow"), Some("GET, OPTIONS"))
}

///|
test "server-wide OPTIONS drops HEAD for a GET route shadowed by a WebSocket" {
  let app = @feather.App::new()
    .get("/ws", fn(ctx) { ctx.text(200, "get") })
    .websocket("/ws", fn(_ctx, _ws) { () })
  let star = app.respond({
    method: "OPTIONS",
    path: "*",
    headers: Map([]),
    body: "",
  })
  assert_eq(star.status, 204)
  assert_eq(star.headers.get("Allow"), Some("GET, OPTIONS"))
  let path = app.respond({
    method: "OPTIONS",
    path: "/ws",
    headers: Map([]),
    body: "",
  })
  assert_eq(path.headers.get("Allow"), Some("GET"))
}

///|
test "server-wide OPTIONS keeps HEAD when another GET route is reachable" {
  let app = @feather.App::new()
    .get("/ws", fn(ctx) { ctx.text(200, "get") })
    .get("/plain", fn(ctx) { ctx.text(200, "plain") })
    .websocket("/ws", fn(_ctx, _ws) { () })
  let response = app.respond({
    method: "OPTIONS",
    path: "*",
    headers: Map([]),
    body: "",
  })
  assert_eq(response.headers.get("Allow"), Some("GET, HEAD, OPTIONS"))
}

///|
test "server-wide OPTIONS keeps HEAD for SSE and static endpoints" {
  let sse = @feather.App::new().sse("/events", async fn(_ctx, _sse) { () })
  let sse_response = sse.respond({
    method: "OPTIONS",
    path: "*",
    headers: Map([]),
    body: "",
  })
  assert_eq(
    sse_response.headers.get("Allow"),
    Some("GET, HEAD, OPTIONS"),
  )
  let static = @feather.App::new().static_files("/assets", "/tmp/feather-options")
  let static_response = static.respond({
    method: "OPTIONS",
    path: "*",
    headers: Map([]),
    body: "",
  })
  assert_eq(
    static_response.headers.get("Allow"),
    Some("GET, HEAD, OPTIONS"),
  )
}
