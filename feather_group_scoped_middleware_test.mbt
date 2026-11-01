///|
fn group_scope_request(method : String, path : String) -> @feather.Request {
  { method, path, headers: Map([]), body: "" }
}

///|
fn group_scope_marker(
  name : String,
  value : String,
  calls : Ref[Int32],
) -> @feather.Middleware {
  fn(next) {
    fn(ctx) raise {
      calls.val = calls.val + 1
      ctx.set_header(name, value)
      next(ctx)
    }
  }
}

///|
test "group use_when sees earlier group middleware and skips per request" {
  let calls = Ref(0)
  let app = @feather.App::new()
  let api = app
    .group("/api")
    .use(fn(next) {
      fn(ctx) raise {
        ctx.set("tenant", "acme")
        next(ctx)
      }
    })
    .use_when(fn(ctx) {
      ctx.get("tenant") == "acme" && ctx.get_method() == "GET"
    }, group_scope_marker("X-Scoped", "yes", calls))
  ignore(api.get("/items", fn(ctx) { ctx.text(200, "items") }))
  ignore(api.post("/items", fn(ctx) { ctx.text(200, "created") }))
  let get = app.respond(group_scope_request("GET", "/api/items"))
  assert_eq(get.status, 200)
  assert_eq(get.headers.get("X-Scoped"), Some("yes"))
  let post = app.respond(group_scope_request("POST", "/api/items"))
  assert_eq(post.status, 200)
  assert_eq(post.headers.get("X-Scoped"), None)
  assert_eq(calls.val, 1)
}

///|
test "group use_prefix is relative to the group prefix" {
  let calls = Ref(0)
  let app = @feather.App::new()
  let api = app.group("api").use_prefix("admin", group_scope_marker(
    "X-Admin", "yes", calls,
  ))
  ignore(api.get("/admin", fn(ctx) { ctx.text(200, "admin") }))
  ignore(api.get("/admin/panel", fn(ctx) { ctx.text(200, "panel") }))
  ignore(api.get("/adminish", fn(ctx) { ctx.text(200, "adminish") }))
  ignore(api.get("/items", fn(ctx) { ctx.text(200, "items") }))
  for path in ["/api/admin", "/api/admin/panel"] {
    let response = app.respond(group_scope_request("GET", path))
    assert_eq(response.status, 200)
    assert_eq(response.headers.get("X-Admin"), Some("yes"))
  }
  for path in ["/api/adminish", "/api/items"] {
    let response = app.respond(group_scope_request("GET", path))
    assert_eq(response.status, 200)
    assert_eq(response.headers.get("X-Admin"), None)
  }
  assert_eq(calls.val, 2)
}

///|
test "group use_prefix follows a dynamic group prefix" {
  let calls = Ref(0)
  let app = @feather.App::new()
  let tenant = app.group("/tenant/:id").use_prefix("/admin", group_scope_marker(
    "X-Admin", "yes", calls,
  ))
  ignore(tenant.get("/admin/panel", fn(ctx) { ctx.text(200, ctx.param("id")) }))
  ignore(tenant.get("/profile", fn(ctx) { ctx.text(200, ctx.param("id")) }))
  let scoped = app.respond(group_scope_request(
    "GET",
    "/tenant/acme/admin/panel",
  ))
  assert_eq(scoped.status, 200)
  assert_eq(scoped.body, "acme")
  assert_eq(scoped.headers.get("X-Admin"), Some("yes"))
  let outside = app.respond(group_scope_request("GET", "/tenant/acme/profile"))
  assert_eq(outside.status, 200)
  assert_eq(outside.body, "acme")
  assert_eq(outside.headers.get("X-Admin"), None)
  assert_eq(calls.val, 1)
}

///|
test "group use_prefix applies only to later registrations" {
  let calls = Ref(0)
  let app = @feather.App::new()
  let api = app.group("/api")
  ignore(api.get("/before", fn(ctx) { ctx.text(200, "before") }))
  ignore(api.use_prefix("/later", group_scope_marker(
    "X-Later", "yes", calls,
  )))
  ignore(api.get("/later/after", fn(ctx) { ctx.text(200, "after") }))
  let before = app.respond(group_scope_request("GET", "/api/before"))
  assert_eq(before.status, 200)
  assert_eq(before.headers.get("X-Later"), None)
  let after = app.respond(group_scope_request("GET", "/api/later/after"))
  assert_eq(after.status, 200)
  assert_eq(after.headers.get("X-Later"), Some("yes"))
  assert_eq(calls.val, 1)
}
