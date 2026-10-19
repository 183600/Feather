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
  let feather = create_feather({
    host: "127.0.0.1",
    port: 0,
    timeout: 0,
  })
  ignore(feather.post("/submit", fn(ctx) { ctx.text(201, "ok") }))
  let routes = feather.routes()
  assert_eq(routes.length(), 1)
  assert_eq(routes[0].0, "POST")
  assert_eq(routes[0].1, "/submit")
}

///|
test "Feather facade exposes route queries" {
  let feather = create_feather({
    host: "127.0.0.1",
    port: 0,
    timeout: 0,
  })
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
