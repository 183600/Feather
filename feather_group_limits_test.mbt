///|
fn group_limit_handler(_ctx : @feather.Context) -> Unit raise {
  ()
}

///|
test "route group defaults apply to later routes" {
  let router = @feather.create_router()
  let api = router.group("/api").timeout(250).body_limit(128)
  ignore(api.get("/health", group_limit_handler))
  ignore(api.route_with("PATCH", "/thing", [], group_limit_handler))
  ignore(api.route_named("item", "PUT", "/items/:id", group_limit_handler))
  ignore(api.all("/everything", group_limit_handler))

  assert_eq(router.timeout_for("GET", "/api/health"), 250)
  assert_eq(router.body_limit_for("GET", "/api/health"), 128)
  assert_eq(router.timeout_for("PATCH", "/api/thing"), 250)
  assert_eq(router.body_limit_for("PATCH", "/api/thing"), 128)
  assert_eq(router.timeout_for("PUT", "/api/items/9"), 250)
  assert_eq(router.body_limit_for("PUT", "/api/items/9"), 128)
  for method in ["GET", "POST", "PUT", "PATCH", "DELETE", "HEAD"] {
    assert_eq(router.timeout_for(method, "/api/everything"), 250)
    assert_eq(router.body_limit_for(method, "/api/everything"), 128)
  }
}

///|
test "nested route groups inherit and can replace defaults" {
  let router = @feather.create_router()
  let api = router.group("/api").timeout(250).body_limit(128)
  let v1 = api.group("/v1").timeout(100).body_limit(64)
  ignore(api.get("/inherits", group_limit_handler))
  ignore(v1.post("/upload", group_limit_handler))

  assert_eq(router.timeout_for("GET", "/api/inherits"), 250)
  assert_eq(router.body_limit_for("GET", "/api/inherits"), 128)
  assert_eq(router.timeout_for("POST", "/api/v1/upload"), 100)
  assert_eq(router.body_limit_for("POST", "/api/v1/upload"), 64)
}

///|
test "route group defaults do not affect earlier routes" {
  let router = @feather.create_router()
  let group = router.group("/late")
  ignore(group.get("/before", group_limit_handler))
  let configured = group.timeout(90).body_limit(32)
  ignore(configured.get("/after", group_limit_handler))

  assert_eq(router.timeout_for("GET", "/late/before"), 0)
  assert_eq(router.body_limit_for("GET", "/late/before"), 0)
  assert_eq(router.timeout_for("GET", "/late/after"), 90)
  assert_eq(router.body_limit_for("GET", "/late/after"), 32)
}

///|
test "per-route limits override group defaults" {
  let router = @feather.create_router()
  let group = router.group("/api").timeout(250).body_limit(128)
  ignore(group.get("/other", group_limit_handler))
  ignore(group.route_timeout("GET", "/other", 0))
  ignore(group.route_body_limit("GET", "/other", 512))

  assert_eq(router.timeout_for("GET", "/api/other"), 0)
  assert_eq(router.body_limit_for("GET", "/api/other"), 512)
}

///|
test "negative route group defaults are treated as unset" {
  let router = @feather.create_router()
  let group = router.group("/clamped").timeout(-5).body_limit(-1)
  ignore(group.get("/item", group_limit_handler))

  assert_eq(router.timeout_for("GET", "/clamped/item"), 0)
  assert_eq(router.body_limit_for("GET", "/clamped/item"), 0)
}

///|
test "application route groups apply defaults under their prefix" {
  let app = @feather.App::new()
  let group = app.group("/api").timeout(300).body_limit(40)
  ignore(group.post("/upload", fn(ctx) { ctx.text(200, ctx.request.body) }))
  assert_eq(app.router.timeout_for("POST", "/api/upload"), 300)
  assert_eq(app.router.body_limit_for("POST", "/api/upload"), 40)
  assert_eq(app.router.timeout_for("POST", "/upload"), 0)
}

///|
async test "a route group body limit is enforced by the server" {
  let app = @feather.App::new()
  let group = app.group("/api").body_limit(4)
  ignore(group.post("/upload", fn(ctx) { ctx.text(200, ctx.request.body) }))
  with_server(app, client => {
    let rejected = client.post("/api/upload", "hello")
    assert_eq(rejected.code, 413)
    ignore(client.read_all())
  })
}
