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
