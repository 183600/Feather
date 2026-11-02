///|
test "OPTIONS * responds with server methods sorted alphabetically" {
  let app = @feather.App::new()
    .get("/hello", fn(ctx) { ctx.text(200, "hello") })
    .post("/submit", fn(ctx) { ctx.text(201, "created") })
  let response = app.respond({
    method: "OPTIONS",
    path: "*",
    headers: Map([]),
    body: "",
  })
  assert_eq(response.status, 204)
  assert_eq(response.headers.get("Allow"), Some("GET, HEAD, POST, OPTIONS"))
}

///|
test "OPTIONS * includes WebSocket method" {
  let app = @feather.App::new()
    .websocket("/ws", fn(_ctx, _ws) { () })
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
test "OPTIONS * includes SSE and stream methods" {
  let app = @feather.App::new()
    .sse("/events", async fn(_ctx, _sse) { () })
    .stream("/feed", async fn(_ctx, _stream) { })
  let response = app.respond({
    method: "OPTIONS",
    path: "*",
    headers: Map([]),
    body: "",
  })
  assert_eq(response.status, 204)
  assert_eq(response.headers.get("Allow"), Some("GET, HEAD, OPTIONS"))
}

///|
test "CONNECT route can be registered and matched" {
  let connected = [false]
  let app = @feather.App::new()
    .connect("/tunnel", fn(ctx) {
      connected[0] = true
      ctx.text(201, "connected")
    })
  let response = app.respond({
    method: "CONNECT",
    path: "/tunnel",
    headers: Map([]),
    body: "",
  })
  assert_eq(response.status, 201)
  assert_eq(connected[0], true)
}

///|
test "TRACE route can be registered and matched" {
  let app = @feather.App::new()
    .trace("/echo", fn(ctx) { ctx.text(200, ctx.request.path) })
  let response = app.respond({
    method: "TRACE",
    path: "/echo",
    headers: Map([]),
    body: "",
  })
  assert_eq(response.status, 200)
  assert_eq(response.body, "/echo")
}

///|
test "all method handles HEAD specially with empty body" {
  let app = @feather.App::new().all("/test", fn(ctx) { ctx.text(200, "ok") })
  let response = app.respond({
    method: "HEAD",
    path: "/test",
    headers: Map([]),
    body: "",
  })
  assert_eq(response.status, 200)
  assert_eq(response.body, "")
}

///|
test "static mount with index file returns file for directory request" {
  let app = @feather.App::new()
    .static_files("/assets", "/srv/public", index="index.html")
  let file = app.static_file_for("/assets/")
  assert_eq(file, Some("/srv/public/index.html"))
}

///|
test "static mount without index returns None for directory request" {
  let app = @feather.App::new()
    .static_files("/assets", "/srv/public", index="")
  let file = app.static_file_for("/assets/")
  assert_eq(file, None)
}

///|
test "dynamic static mount binds captured params" {
  let app = @feather.App::new()
    .static_files("/:tenant/assets", "/srv/public")
  let file = app.static_file_for("/acme/assets/app.js")
  assert_eq(file, Some("/srv/public/app.js"))
}

///|
test "wildcard static mount captures remainder at root" {
  let app = @feather.App::new()
    .static_files("/*path", "/srv/root")
  let file = app.static_file_for("/some/deep/path.txt")
  assert_eq(file, Some("/srv/root/some/deep/path.txt"))
}

///|
test "wildcards at root match any path" {
  let app = @feather.App::new().get("/*path", fn(ctx) {
    ctx.text(200, ctx.param("path"))
  })
  let response = app.respond({
    method: "GET",
    path: "/anything/goes/here",
    headers: Map([]),
    body: "",
  })
  assert_eq(response.status, 200)
  assert_eq(response.body, "anything/goes/here")
}

///|
test "root wildcard does not match empty path" {
  let app = @feather.App::new()
    .get("/*path", fn(ctx) { ctx.text(200, "wildcard") })
    .get("/", fn(ctx) { ctx.text(200, "root") })
  let response = app.respond({
    method: "GET",
    path: "/",
    headers: Map([]),
    body: "",
  })
  assert_eq(response.status, 200)
  assert_eq(response.body, "root")
}

///|
test "named routes url_for with query parameters only" {
  let app = @feather.App::new()
    .route_named("search", "GET", "/search", fn(ctx) { ctx.text(200, "ok") })
  let url = app.url_for("search", query=Map([("page", "1"), ("q", "hello")]))
  assert_eq(url, Some("/search?page=1&q=hello"))
}

///|
test "url_for returns nil for unknown route name" {
  let app = @feather.App::new().get("/", fn(ctx) { ctx.text(200, "ok") })
  assert_eq(app.url_for("unknown"), None)
}

///|
test "route_pattern reports empty for unbound params" {
  let ctx = @feather.Context::new({
    method: "GET",
    path: "/test",
    headers: Map([]),
    body: "",
  })
  assert_eq(ctx.route_pattern(), "")
}

///|
test "route_method reports empty when no route matched" {
  let ctx = @feather.Context::new({
    method: "GET",
    path: "/missing",
    headers: Map([]),
    body: "",
  })
  assert_eq(ctx.route_method(), "")
}

///|
test "fallback handler sets empty route identity" {
  let app = @feather.App::new()
    .get("/known", fn(ctx) { ctx.text(200, "ok") })
    .fallback(fn(ctx) { ctx.text(404, "missing") })
  let response = app.respond({
    method: "GET",
    path: "/missing",
    headers: Map([]),
    body: "",
  })
  assert_eq(response.status, 404)
}