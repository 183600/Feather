///|
/// Boundary routes: the root path, trailing slashes, wildcard captures and the
/// static > param > wildcard matching precedence.
test "a route registered at the root path serves the root request" {
  let app = @feather.App::new().get("/", fn(ctx) {
    ctx.set_header("X-Route-Pattern", ctx.route_pattern())
    ctx.text(200, "root")
  })
  let response = app.respond({
    method: "GET",
    path: "/",
    headers: Map([]),
    body: "",
  })
  assert_eq(response.status, 200)
  assert_eq(response.body, "root")
  assert_eq(response.headers.get("X-Route-Pattern"), Some("/"))
}

test "the empty path routes to the root node" {
  let app = @feather.App::new().get("", fn(ctx) { ctx.text(200, "empty") })
  let response = app.respond({
    method: "GET",
    path: "",
    headers: Map([]),
    body: "",
  })
  assert_eq(response.status, 200)
  assert_eq(response.body, "empty")
}

test "a trailing slash matches the route registered without one" {
  let app = @feather.App::new().get("/api", fn(ctx) { ctx.text(200, "api") })
  let response = app.respond({
    method: "GET",
    path: "/api/",
    headers: Map([]),
    body: "",
  })
  assert_eq(response.status, 200)
  assert_eq(response.body, "api")
}

test "a static segment wins over a parameter for the same path" {
  let app = @feather.App::new()
    .get("/api", fn(ctx) { ctx.text(200, "static-text") })
    .get("/:id", fn(ctx) { ctx.text(200, "param:" + ctx.param("id")) })
  let response = app.respond({
    method: "GET",
    path: "/api",
    headers: Map([]),
    body: "",
  })
  assert_eq(response.status, 200)
  assert_eq(response.body, "static-text")
}

test "a parameter wins over a wildcard for a single segment" {
  let app = @feather.App::new()
    .get("/:id", fn(ctx) { ctx.text(200, "param:" + ctx.param("id")) })
    .get("/*rest", fn(ctx) { ctx.text(200, "wild:" + ctx.param("rest")) })
  let response = app.respond({
    method: "GET",
    path: "/users",
    headers: Map([]),
    body: "",
  })
  assert_eq(response.status, 200)
  assert_eq(response.body, "param:users")
}

test "a wildcard still matches a multi-segment path when no parameter fits" {
  let app = @feather.App::new()
    .get("/:id", fn(ctx) { ctx.text(200, "param:" + ctx.param("id")) })
    .get("/*rest", fn(ctx) { ctx.text(200, "wild:" + ctx.param("rest")) })
  let response = app.respond({
    method: "GET",
    path: "/users/42",
    headers: Map([]),
    body: "",
  })
  assert_eq(response.status, 200)
  assert_eq(response.body, "wild:users/42")
}

test "a wildcard captures the remainder including nested segments" {
  let app = @feather.App::new().get("/*path", fn(ctx) {
    ctx.text(200, "wild:" + ctx.param("path"))
  })
  let response = app.respond({
    method: "GET",
    path: "/files/a/b/c.txt",
    headers: Map([]),
    body: "",
  })
  assert_eq(response.status, 200)
  assert_eq(response.body, "wild:files/a/b/c.txt")
}

test "a wildcard matches the empty remainder at the root" {
  let app = @feather.App::new().get("/*path", fn(ctx) {
    ctx.text(200, "wild:" + ctx.param("path"))
  })
  let response = app.respond({
    method: "GET",
    path: "/",
    headers: Map([]),
    body: "",
  })
  assert_eq(response.status, 200)
  assert_eq(response.body, "wild:")
}

test "a parameter route does not match the empty root segment" {
  let app = @feather.App::new()
    .get("/:id", fn(ctx) { ctx.text(200, "param:" + ctx.param("id")) })
    .fallback(fn(ctx) { ctx.text(404, "fallback") })
  let response = app.respond({
    method: "GET",
    path: "/",
    headers: Map([]),
    body: "",
  })
  assert_eq(response.status, 404)
  assert_eq(response.body, "fallback")
}

test "has_param reports a wildcard capture even when it is empty" {
  let app = @feather.App::new().get("/*path", fn(ctx) {
    ctx.text(200, ctx.has_param("path").to_string())
  })
  let response = app.respond({
    method: "GET",
    path: "/",
    headers: Map([]),
    body: "",
  })
  assert_eq(response.status, 200)
  assert_eq(response.body, "true")
}
