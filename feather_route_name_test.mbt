///|
test "named routes expose their name through Context::route_name" {
  let app = @feather.App::new().route_named(
    "user",
    "GET",
    "/users/:id",
    fn(ctx) {
      ctx.set_header("X-Route-Name", ctx.route_name())
      ctx.text(200, ctx.param("id"))
    },
  )
  let response = app.respond({
    method: "GET",
    path: "/users/42",
    headers: Map([]),
    body: "",
  })
  assert_eq(response.status, 200)
  assert_eq(response.body, "42")
  assert_eq(response.headers.get("X-Route-Name"), Some("user"))
}

///|
test "HEAD fallback reports the name of the GET route" {
  let app = @feather.App::new().route_named(
    "user",
    "GET",
    "/users/:id",
    fn(ctx) {
      ctx.set_header("X-Route-Name", ctx.route_name())
      ctx.set_header("X-Route-Method", ctx.route_method())
      ctx.text(200, "body")
    },
  )
  let response = app.respond({
    method: "HEAD",
    path: "/users/7",
    headers: Map([]),
    body: "",
  })
  assert_eq(response.status, 200)
  assert_eq(response.headers.get("X-Route-Name"), Some("user"))
  assert_eq(response.headers.get("X-Route-Method"), Some("GET"))
  assert_eq(response.body, "")
}

///|
test "route groups and unnamed routes report the expected names" {
  let app = @feather.App::new()
  let api = app.group("/api")
  ignore(
    api.route_named("health", "GET", "/health", fn(ctx) {
      ctx.text(200, ctx.route_name())
    }),
  )
  ignore(api.get("/plain", fn(ctx) {
    ctx.text(200, "[" + ctx.route_name() + "]")
  }))
  assert_eq(
    app.respond({
      method: "GET",
      path: "/api/health",
      headers: Map([]),
      body: "",
    }).body,
    "health",
  )
  assert_eq(
    app.respond({
      method: "GET",
      path: "/api/plain",
      headers: Map([]),
      body: "",
    }).body,
    "[]",
  )
}

///|
test "re-registering a path without a name clears the old name" {
  let app = @feather.App::new().route_named(
    "old",
    "GET",
    "/thing",
    fn(ctx) {
      ctx.text(200, ctx.route_name())
    },
  )
  ignore(app.get("/thing", fn(ctx) { ctx.text(200, "[" + ctx.route_name() + "]") }))
  let response = app.respond({
    method: "GET",
    path: "/thing",
    headers: Map([]),
    body: "",
  })
  assert_eq(response.body, "[]")
}

///|
test "mounted named routes keep their names and URL generation" {
  let child = @feather.App::new().route_named(
    "child_user",
    "GET",
    "/users/:id",
    fn(ctx) { ctx.text(200, ctx.route_name()) },
  )
  let parent = @feather.App::new().mount("/api", child)
  let response = parent.respond({
    method: "GET",
    path: "/api/users/9",
    headers: Map([]),
    body: "",
  })
  assert_eq(response.body, "child_user")
  assert_eq(
    parent.url_for("child_user", params=Map([("id", "9")])),
    Some("/api/users/9"),
  )
}

///|
test "Router::route reports the registered name" {
  let router = @feather.create_router()
  router.add_named_route(
    "item",
    "get",
    "/items/:id",
    fn(ctx) { ctx.text(200, ctx.param("id")) },
  )
  match router.route("GET", "/items/3") {
    @feather.RouteFound(route) => {
      assert_eq(route.name, "item")
      assert_eq(route.method, "GET")
      assert_eq(route.params.get("id"), Some("3"))
    }
    _ => fail("expected the named route to match")
  }
  router.add_route("POST", "/items", fn(ctx) { ctx.text(200, "post") })
  match router.route("POST", "/items") {
    @feather.RouteFound(route) => assert_eq(route.name, "")
    _ => fail("expected the unnamed route to match")
  }
}

///|
test "a named parameter route is not confused with a static colon sibling" {
  let router = @feather.create_router()
  router.add_route("GET", "/users/%3Aid", fn(ctx) { ctx.text(200, "static") })
  router.add_named_route("dynamic", "GET", "/users/:id", fn(ctx) {
    ctx.text(200, "dynamic")
  })
  // Static segments outrank parameters, so the literal `:id` path still hits
  // the static sibling; only the parameter match carries the dynamic name.
  match router.route("GET", "/users/:id") {
    @feather.RouteFound(route) => assert_eq(route.name, "")
    _ => fail("expected the static sibling to match")
  }
  match router.route("GET", "/users/42") {
    @feather.RouteFound(route) => {
      assert_eq(route.name, "dynamic")
      assert_eq(route.params.get("id"), Some("42"))
    }
    _ => fail("expected the named parameter route to match")
  }
}

