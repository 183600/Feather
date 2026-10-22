///|
fn encoded_scope_request(path : String) -> @feather.Request {
  { method: "GET", path, headers: Map([]), body: "", }
}

///|
fn encoded_scope_deny() -> @feather.Middleware {
  fn(_next) {
    fn(ctx) raise {
      ctx.text(401, "denied")
    }
  }
}

///|
test "prefix-scoped middleware follows decoded and normalized path segments" {
  let app = @feather.App::new()
    .use_prefix("/admin", encoded_scope_deny())
    .get("/admin/panel", fn(ctx) { ctx.text(200, "secret") })
    .get("/apiary", fn(ctx) { ctx.text(200, "open") })
  for path in [
    "/admin/panel",
    "/ad%6Din/panel",
    "/admin//panel",
    "//admin/panel",
    "///admin///panel",
  ] {
    let response = app.respond(encoded_scope_request(path))
    assert_eq(response.status, 401, msg=path)
    assert_eq(response.body, "denied", msg=path)
  }
  let outside = app.respond(encoded_scope_request("/apiary"))
  assert_eq(outside.status, 200)
  assert_eq(outside.body, "open")
}

///|
test "mounted prefix scopes keep matching encoded mount points" {
  let child = @feather.App::new()
    .use_prefix("/admin", encoded_scope_deny())
    .get("/admin/items", fn(ctx) { ctx.text(200, "secret") })
    .get("/public", fn(ctx) { ctx.text(200, "open") })
  let parent = @feather.App::new().mount("/v1", child)
  for path in [
    "/v1/admin/items",
    "/v%31/admin/items",
    "/v1/ad%6Din/items",
    "//v1//admin/items",
  ] {
    let response = parent.respond(encoded_scope_request(path))
    assert_eq(response.status, 401, msg=path)
    assert_eq(response.body, "denied", msg=path)
  }
  let outside = parent.respond(encoded_scope_request("/v1/public"))
  assert_eq(outside.status, 200)
  assert_eq(outside.body, "open")
}
