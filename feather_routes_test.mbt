///|
test "Router::routes lists registered patterns sorted" {
  let router = create_router()
  router.add_route("GET", "/users/:id", fn(ctx) { ctx.text(200, "u") })
  router.add_route("POST", "/users", fn(ctx) { ctx.text(200, "c") })
  router.add_route("GET", "/", fn(ctx) { ctx.text(200, "root") })
  router.add_route("GET", "/files/*path", fn(ctx) { ctx.text(200, "f") })
  let routes = router.routes()
  assert_eq(routes.length(), 4)
  assert_eq(routes[0].0, "GET")
  assert_eq(routes[0].1, "/")
  assert_eq(routes[1].0, "GET")
  assert_eq(routes[1].1, "/files/*path")
  assert_eq(routes[2].0, "GET")
  assert_eq(routes[2].1, "/users/:id")
  assert_eq(routes[3].0, "POST")
  assert_eq(routes[3].1, "/users")
}

///|
test "Router::routes is empty without registrations" {
  assert_eq(create_router().routes().length(), 0)
}

///|
test "Router::routes reports a pattern once" {
  let router = create_router()
  router.add_route("GET", "/once", fn(ctx) { ctx.text(200, "first") })
  router.add_route("GET", "/once", fn(ctx) { ctx.text(200, "second") })
  let routes = router.routes()
  assert_eq(routes.length(), 1)
  assert_eq(routes[0].1, "/once")
}

///|
test "App::routes includes mounted routes" {
  let child = App::new().get("/ping", fn(ctx) { ctx.text(200, "pong") })
  let app = App::new()
    .get("/", fn(ctx) { ctx.text(200, "root") })
    .mount("/api", child)
  let routes = app.routes()
  assert_eq(routes.length(), 2)
  assert_eq(routes[0].1, "/")
  assert_eq(routes[1].0, "GET")
  assert_eq(routes[1].1, "/api/ping")
}

///|
test "Feather::routes forwards to the application" {
  let feather = create_feather({ host: "127.0.0.1", port: 0, timeout: 0, })
  ignore(feather.post("/submit", fn(ctx) { ctx.text(201, "ok") }))
  let routes = feather.routes()
  assert_eq(routes.length(), 1)
  assert_eq(routes[0].0, "POST")
  assert_eq(routes[0].1, "/submit")
}

///|
test "Feather facade exposes route queries" {
  let feather = create_feather({ host: "127.0.0.1", port: 0, timeout: 0, })
  ignore(feather.get("/hello", fn(ctx) { ctx.text(200, "hi") }))
  ignore(feather.websocket("/ws", async fn(_ctx, _ws) { () }))
  ignore(feather.sse("/events", async fn(_ctx, _sse) { () }))
  ignore(feather.stream("/stream", async fn(_ctx, _stream) { () }))
  assert_true(feather.has_route("GET", "/hello"))
  assert_false(feather.has_route("POST", "/hello"))
  assert_true(feather.has_websocket("/ws"))
  assert_false(feather.has_websocket("/hello"))
  assert_true(feather.has_sse("/events"))
  assert_true(feather.has_stream("/stream"))
}

///|
test "Feather facade resolve methods return handlers for async endpoints" {
  let feather = create_feather({ host: "127.0.0.1", port: 0, timeout: 0, })
  ignore(feather.sse("/events", async fn(_ctx, _sse) { () }))
  ignore(feather.websocket("/ws", async fn(_ctx, _ws) { () }))
  ignore(feather.stream("/stream", async fn(_ctx, _stream) { () }))

  let sse_result = feather.resolve_sse("/events")
  assert_true(sse_result.is_some(), msg="SSE route should resolve")
  let (sse_handler, sse_params) = sse_result.unwrap()
  assert_eq(sse_params.length(), 0)

  let ws_result = feather.resolve_websocket("/ws")
  assert_true(ws_result.is_some(), msg="WebSocket route should resolve")
  let (ws_handler, ws_params) = ws_result.unwrap()
  assert_eq(ws_params.length(), 0)

  let stream_result = feather.resolve_stream("/stream")
  assert_true(stream_result.is_some(), msg="Stream route should resolve")
  let (stream_handler, stream_params) = stream_result.unwrap()
  assert_eq(stream_params.length(), 0)
}

///|
test "Feather facade resolve methods return none for unregistered paths" {
  let feather = create_feather({ host: "127.0.0.1", port: 0, timeout: 0, })
  match feather.resolve_sse("/missing") {
    Some(_) => fail("expected sse result to be none")
    None => ()
  }
  match feather.resolve_websocket("/missing") {
    Some(_) => fail("expected websocket result to be none")
    None => ()
  }
  match feather.resolve_stream("/missing") {
    Some(_) => fail("expected stream result to be none")
    None => ()
  }
}

///|
test "Feather facade resolve methods bind route parameters" {
  let feather = create_feather({ host: "127.0.0.1", port: 0, timeout: 0, })
  ignore(feather.sse("/events/:room", async fn(_ctx, _sse) { () }))
  ignore(feather.websocket("/ws/:room", async fn(_ctx, _ws) { () }))
  ignore(feather.stream("/stream/:id", async fn(_ctx, _stream) { () }))

  let sse_result = feather.resolve_sse("/events/lobby")
  assert_true(sse_result.is_some())
  let (_, sse_params) = sse_result.unwrap()
  assert_eq(sse_params.get("room"), Some("lobby"))

  let ws_result = feather.resolve_websocket("/ws/chat")
  assert_true(ws_result.is_some())
  let (_, ws_params) = ws_result.unwrap()
  assert_eq(ws_params.get("room"), Some("chat"))

  let stream_result = feather.resolve_stream("/stream/42")
  assert_true(stream_result.is_some())
  let (_, stream_params) = stream_result.unwrap()
  assert_eq(stream_params.get("id"), Some("42"))
}
