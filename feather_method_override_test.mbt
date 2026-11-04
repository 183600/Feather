///|
/// Tests for `middleware_method_override`: a POST request can be retargeted to
/// PUT, PATCH, DELETE or OPTIONS through the `X-HTTP-Method-Override` header or
/// a `_method` form field, while non-POST requests and unknown values pass
/// through unchanged.
fn override_app() -> @feather.App {
  @feather.App::new()
    .use(@feather.middleware_method_override())
    .put("/resource", fn(ctx) {
      ctx.text(200, "put:" + ctx.route_method())
    })
    .patch("/resource", fn(ctx) {
      ctx.text(200, "patch:" + ctx.route_method())
    })
    .delete("/resource", fn(ctx) {
      ctx.text(200, "delete:" + ctx.route_method())
    })
    .options("/resource", fn(ctx) {
      ctx.text(200, "options:" + ctx.route_method())
    })
    .post("/resource", fn(ctx) {
      ctx.text(200, "post:" + ctx.route_method())
    })
    .get("/resource", fn(ctx) {
      ctx.text(200, "get:" + ctx.route_method())
    })
}

///|
fn post_ctx(body : String, extra_headers : Map[String, String]) -> @feather.Context {
  let headers : Map[String, String] = Map([])
  headers.set("Content-Type", "application/x-www-form-urlencoded")
  for name, value in extra_headers {
    headers.set(name, value)
  }
  @feather.Context::new({
    method: "POST",
    path: "/resource",
    headers,
    body,
  })
}

///|
test "method override header retargets POST to PUT" {
  let app = override_app()
  let ctx = @feather.Context::new({
    method: "POST",
    path: "/resource",
    headers: Map([
      ("X-HTTP-Method-Override", "PUT"),
    ]),
    body: "",
  })
  app.handle(ctx)
  assert_eq(ctx.response.status, 200)
  assert_eq(ctx.response.body, "put:PUT")
  assert_eq(ctx.route_method(), "PUT")
}

///|
test "method override header retargets POST to DELETE" {
  let app = override_app()
  let ctx = @feather.Context::new({
    method: "POST",
    path: "/resource",
    headers: Map([
      ("X-HTTP-Method-Override", "DELETE"),
    ]),
    body: "",
  })
  app.handle(ctx)
  assert_eq(ctx.response.status, 200)
  assert_eq(ctx.response.body, "delete:DELETE")
}

///|
test "method override header is case insensitive" {
  let app = override_app()
  let ctx = @feather.Context::new({
    method: "POST",
    path: "/resource",
    headers: Map([
      ("X-HTTP-Method-Override", "patch"),
    ]),
    body: "",
  })
  app.handle(ctx)
  assert_eq(ctx.response.status, 200)
  assert_eq(ctx.response.body, "patch:PATCH")
}

///|
test "method override form field retargets POST to DELETE" {
  let app = override_app()
  let ctx = post_ctx("_method=DELETE", Map([]))
  app.handle(ctx)
  assert_eq(ctx.response.status, 200)
  assert_eq(ctx.response.body, "delete:DELETE")
}

///|
test "method override header wins over the form field" {
  let app = override_app()
  let ctx = post_ctx("_method=DELETE", Map([
    ("X-HTTP-Method-Override", "PUT"),
  ]))
  app.handle(ctx)
  assert_eq(ctx.response.status, 200)
  assert_eq(ctx.response.body, "put:PUT")
}

///|
test "unknown override leaves the method as POST" {
  let app = override_app()
  let ctx = @feather.Context::new({
    method: "POST",
    path: "/resource",
    headers: Map([
      ("X-HTTP-Method-Override", "PROPFIND"),
    ]),
    body: "",
  })
  app.handle(ctx)
  assert_eq(ctx.response.status, 200)
  assert_eq(ctx.response.body, "post:POST")
}

///|
test "a non-POST request is not retargeted by the override header" {
  let app = override_app()
  let ctx = @feather.Context::new({
    method: "GET",
    path: "/resource",
    headers: Map([
      ("X-HTTP-Method-Override", "PUT"),
    ]),
    body: "",
  })
  app.handle(ctx)
  assert_eq(ctx.response.status, 200)
  assert_eq(ctx.response.body, "get:GET")
}

///|
test "method override with a custom form field name" {
  let app = @feather.App::new()
    .use(@feather.middleware_method_override(field="_m"))
    .put("/resource", fn(ctx) {
      ctx.text(200, "put:" + ctx.route_method())
    })
    .post("/resource", fn(ctx) {
      ctx.text(200, "post:" + ctx.route_method())
    })
  let ctx = post_ctx("_m=PUT", Map([]))
  app.handle(ctx)
  assert_eq(ctx.response.status, 200)
  assert_eq(ctx.response.body, "put:PUT")
}

///|
