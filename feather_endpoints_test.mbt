///|
fn endpoint_kind_label(kind : @feather.EndpointKind) -> String {
  match kind {
    @feather.EndpointRoute => "route"
    @feather.EndpointWebSocket => "websocket"
    @feather.EndpointSse => "sse"
    @feather.EndpointStream => "stream"
    @feather.EndpointStatic => "static"
  }
}

///|
test "endpoints include ordinary, asynchronous and static registrations" {
  let app = @feather.App::new()
    .get("/z", fn(ctx) { ctx.text(200, "z") })
    .post("/a", fn(ctx) { ctx.text(201, "a") })
    .sse("/events", async fn(_ctx, sse) { sse.send("tick") })
    .stream("/feed", async fn(_ctx, stream) { stream.write("chunk") })
    .websocket("/ws", fn(_ctx, _ws) { () })
    .static_files("/assets", "public")
  let endpoints = app.endpoints()
  assert_eq(endpoints.length(), 6)
  assert_eq(endpoints[0].method, "GET")
  assert_eq(endpoints[0].path, "/assets")
  assert_eq(endpoint_kind_label(endpoints[0].kind), "static")
  assert_eq(endpoints[1].path, "/events")
  assert_eq(endpoint_kind_label(endpoints[1].kind), "sse")
  assert_eq(endpoints[2].path, "/feed")
  assert_eq(endpoint_kind_label(endpoints[2].kind), "stream")
  assert_eq(endpoints[3].path, "/ws")
  assert_eq(endpoint_kind_label(endpoints[3].kind), "websocket")
  assert_eq(endpoints[4].path, "/z")
  assert_eq(endpoint_kind_label(endpoints[4].kind), "route")
  assert_eq(endpoints[5].method, "POST")
  assert_eq(endpoints[5].path, "/a")
  // `routes` keeps its documented ordinary-route-only contract.
  assert_eq(app.routes(), [("GET", "/z"), ("POST", "/a")])
}

///|
test "endpoints include async and static registrations from mounted apps" {
  let child = @feather.App::new()
    .get("/health", fn(ctx) { ctx.json(200, { "ok": "true" }) })
    .sse("/events", async fn(_ctx, _sse) { () })
    .static_files("/files", "public")
  let parent = @feather.App::new().mount("/api", child)
  let endpoints = parent.endpoints()
  assert_eq(endpoints.length(), 3)
  assert_eq(endpoints[0].path, "/api/events")
  assert_eq(endpoint_kind_label(endpoints[0].kind), "sse")
  assert_eq(endpoints[1].path, "/api/files")
  assert_eq(endpoint_kind_label(endpoints[1].kind), "static")
  assert_eq(endpoints[2].path, "/api/health")
  assert_eq(endpoint_kind_label(endpoints[2].kind), "route")
}

///|
test "endpoints with the same method and path follow dispatch precedence" {
  let app = @feather.App::new()
    .get("/same", fn(ctx) { ctx.text(200, "route") })
    .websocket("/same", fn(_ctx, _ws) { () })
    .sse("/same", async fn(_ctx, _sse) { () })
    .stream("/same", async fn(_ctx, _stream) { () })
  let endpoints = app.endpoints()
  let labels : Array[String] = []
  for endpoint in endpoints {
    assert_eq(endpoint.method, "GET")
    assert_eq(endpoint.path, "/same")
    labels.push(endpoint_kind_label(endpoint.kind))
  }
  assert_eq(labels, ["websocket", "sse", "stream", "route"])
}

///|
test "a root static mount is reported as the root path" {
  let app = @feather.App::new().static_files("/", "public")
  let endpoints = app.endpoints()
  assert_eq(endpoints.length(), 1)
  assert_eq(endpoints[0].method, "GET")
  assert_eq(endpoints[0].path, "/")
  assert_eq(endpoint_kind_label(endpoints[0].kind), "static")
}

///|
test "the Feather facade exposes endpoint introspection" {
  let feather = @feather.create_feather({
    host: "127.0.0.1",
    port: 8080,
    timeout: 1_000,
  })
  ignore(feather.app.get("/hello", fn(ctx) { ctx.text(200, "hello") }))
  assert_eq(feather.endpoints().length(), 1)
  assert_eq(feather.endpoints()[0].path, "/hello")
  assert_eq(endpoint_kind_label(feather.endpoints()[0].kind), "route")
}
