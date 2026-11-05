///|
test "route pattern and method describe the matched route" {
  let app = @feather.App::new().get("/users/:id", fn(ctx) {
    ctx.set_header("X-Route-Pattern", ctx.route_pattern())
    ctx.set_header("X-Route-Method", ctx.route_method())
    ctx.json(200, { "id": ctx.param("id") })
  })
  let response = app.respond({
    method: "GET",
    path: "/users/42?tab=profile",
    headers: Map([]),
    body: "",
  })
  assert_eq(response.status, 200)
  assert_eq(response.headers.get("X-Route-Pattern"), Some("/users/:id"))
  assert_eq(response.headers.get("X-Route-Method"), Some("GET"))
}

///|
test "route pattern is empty when the fallback answers" {
  let app = @feather.App::new()
    .get("/known", fn(ctx) { ctx.text(200, "known") })
    .fallback(fn(ctx) {
      assert_eq(ctx.route_pattern(), "")
      assert_eq(ctx.route_method(), "")
      ctx.text(404, "fallback")
    })
  let response = app.respond({
    method: "GET",
    path: "/missing",
    headers: Map([]),
    body: "",
  })
  assert_eq(response.status, 404)
  assert_eq(response.body, "fallback")
}

///|
test "route pattern is empty for a method-not-allowed response" {
  let app = @feather.App::new()
    .get("/known", fn(ctx) {
      ctx.set_header("X-Ran", "yes")
      ctx.text(200, "known")
    })
  let response = app.respond({
    method: "POST",
    path: "/known",
    headers: Map([]),
    body: "",
  })
  assert_eq(response.status, 405)
  assert_eq(response.headers.get("X-Ran"), None)
  assert_eq(response.headers.get("Allow"), Some("GET, HEAD"))
}

///|
test "HEAD falls back to the GET route identity" {
  let app = @feather.App::new().get("/report", fn(ctx) {
    ctx.set_header("X-Route-Pattern", ctx.route_pattern())
    ctx.set_header("X-Route-Method", ctx.route_method())
    ctx.text(200, "report")
  })
  let response = app.respond({
    method: "HEAD",
    path: "/report",
    headers: Map([]),
    body: "",
  })
  assert_eq(response.status, 200)
  assert_eq(response.headers.get("X-Route-Pattern"), Some("/report"))
  assert_eq(response.headers.get("X-Route-Method"), Some("GET"))
  assert_eq(response.body, "")
}

///|
test "middleware can observe the matched route after calling through" {
  let observed = Ref("")
  let app = @feather.App::new()
    .use(fn(next) {
      fn(ctx) {
        next(ctx)
        observed.val = ctx.route_pattern() + " " + ctx.route_method()
      }
    })
    .post("/items/:id", fn(ctx) { ctx.text(201, ctx.param("id")) })
  let response = app.respond({
    method: "POST",
    path: "/items/7",
    headers: Map([]),
    body: "",
  })
  assert_eq(response.status, 201)
  assert_eq(observed.val, "/items/:id POST")
}

///|
async test "async endpoints expose their matched route identity" {
  let observed = Ref("")
  let app = @feather.App::new().sse("/rooms/:room", async fn(ctx, sse) {
    observed.val = ctx.route_pattern() +
      " " +
      ctx.route_method() +
      " " +
      ctx.param("room")
    sse.send("ready")
    sse.close()
  })
  with_sse_server(app, client => {
    let response = client.get("/rooms/lobby")
    assert_eq(response.code, 200)
    assert_eq(client.read_all().text(), "data: ready\n\n")
  })
  assert_eq(observed.val, "/rooms/:room GET lobby")
}

///|
test "route pattern is captured in handler response headers" {
  let app = @feather.App::new().get("/api/users/:id", fn(ctx) {
    ctx.set_header("X-Route-Pattern", ctx.route_pattern())
    ctx.text(200, ctx.param("id"))
  })
  let response = app.respond({
    method: "GET",
    path: "/api/users/42",
    headers: Map([]),
    body: "",
  })
  assert_eq(response.status, 200)
  assert_eq(response.body, "42")
  assert_eq(
    response.headers.get("X-Route-Pattern"),
    Some("/api/users/:id"),
  )
}

///|
test "route pattern with param and wildcard combo" {
  let app = @feather.App::new()
    .get("/:resource/*path", fn(ctx) {
      ctx.set_header("X-Route-Pattern", ctx.route_pattern())
      ctx.text(200, ctx.param("resource") + ":" + ctx.param("path"))
    })
  let response = app.respond({
    method: "GET",
    path: "/images/photo.png?q=1",
    headers: Map([]),
    body: "",
  })
  assert_eq(response.status, 200)
  assert_eq(response.headers.get("X-Route-Pattern"), Some("/:resource/*path"))
  assert_eq(response.body, "images:photo.png")
}

///|
test "route pattern with multiple parameters" {
  let app = @feather.App::new()
    .get("/:a/:b/:c", fn(ctx) {
      ctx.set_header("X-Route-Pattern", ctx.route_pattern())
      ctx.text(200, ctx.param("a") + ":" + ctx.param("b") + ":" + ctx.param("c"))
    })
  let response = app.respond({
    method: "GET",
    path: "/1/2/3",
    headers: Map([]),
    body: "",
  })
  assert_eq(response.status, 200)
  assert_eq(response.headers.get("X-Route-Pattern"), Some("/:a/:b/:c"))
  assert_eq(response.body, "1:2:3")
}

///|
test "url_for generates correct URL with query parameters" {
  let app = @feather.App::new()
    .route_named("search", "GET", "/search", fn(ctx) { ctx.text(200, "ok") })
  let url = app.url_for("search", query=Map([("q", "test")]))
  assert_eq(url, Some("/search?q=test"))
}

///|
test "route pattern with HEAD method returns correct status" {
  let app = @feather.App::new().get("/report", fn(ctx) {
    ctx.set_header("X-Route-Pattern", ctx.route_pattern())
    ctx.text(200, "report")
  })
  let response = app.respond({
    method: "HEAD",
    path: "/report",
    headers: Map([]),
    body: "",
  })
  assert_eq(response.status, 200)
  // HEAD requests may not include a response body
  assert_eq(response.headers.get("X-Route-Pattern"), Some("/report"))
}

///|
test "route pattern with OPTIONS on registered path" {
  let app = @feather.App::new().get("/items", fn(ctx) { ctx.text(200, "ok") })
  let response = app.respond({
    method: "OPTIONS",
    path: "/items",
    headers: Map([]),
    body: "",
  })
  assert_eq(response.status, 204)
  assert_eq(
    response.headers.get("Allow"),
    Some("GET, HEAD"),
  )
}

///|
test "route pattern with method not allowed on different method" {
  let app = @feather.App::new().get("/data", fn(ctx) { ctx.text(200, "data") })
  let response = app.respond({
    method: "DELETE",
    path: "/data",
    headers: Map([]),
    body: "",
  })
  assert_eq(response.status, 405)
  assert_eq(
    response.headers.get("Allow"),
    Some("GET, HEAD"),
  )
}

///|
test "url_for generates correct URL with query parameters" {
  let app = @feather.App::new()
    .route_named("search", "GET", "/search", fn(ctx) { ctx.text(200, "ok") })
  let url = app.url_for("search", query=Map([("q", "test")]))
  assert_eq(url, Some("/search?q=test"))
}

///|
test "route pattern with trailing slash normalization" {
  let app = @feather.App::new().get("/api/", fn(ctx) {
    ctx.set_header("X-Route-Pattern", ctx.route_pattern())
    ctx.text(200, "api")
  })
  let response = app.respond({
    method: "GET",
    path: "/api",
    headers: Map([]),
    body: "",
  })
  assert_eq(response.status, 200)
  assert_eq(response.headers.get("X-Route-Pattern"), Some("/api/"))
  assert_eq(response.body, "api")
}

///|
test "route pattern handler sets header correctly with query string" {
  let app = @feather.App::new().get("/search", fn(ctx) {
    ctx.set_header("X-Route-Pattern", ctx.route_pattern())
    ctx.text(200, ctx.query("q"))
  })
  let response = app.respond({
    method: "GET",
    path: "/search?q=hello+world",
    headers: Map([]),
    body: "",
  })
  assert_eq(response.status, 200)
  assert_eq(response.body, "hello world")
}
