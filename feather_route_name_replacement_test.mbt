///|
test "re-registering the same path under a new name drops the old name" {
  let app = @feather.App::new()
    .route_named("old", "GET", "/thing", fn(ctx) { ctx.text(200, "old") })
    .route_named("new", "GET", "/thing", fn(ctx) {
      ctx.text(200, ctx.route_name())
    })
  assert_eq(
    app.respond({
      method: "GET",
      path: "/thing",
      headers: Map([]),
      body: "",
    }).body,
    "new",
  )
  assert_eq(app.url_for("old"), None)
  assert_true(app.router.route_name("old") is None)
  assert_eq(app.url_for("new"), Some("/thing"))
}

///|
test "moving a route name clears it from the previous route" {
  let app = @feather.App::new()
    .route_named("same", "GET", "/a", fn(ctx) {
      ctx.text(200, "a:[" + ctx.route_name() + "]")
    })
    .route_named("same", "GET", "/b", fn(ctx) {
      ctx.text(200, "b:[" + ctx.route_name() + "]")
    })
  assert_eq(app.url_for("same"), Some("/b"))
  assert_eq(
    app.respond({
      method: "GET",
      path: "/a",
      headers: Map([]),
      body: "",
    }).body,
    "a:[]",
  )
  assert_eq(
    app.respond({
      method: "GET",
      path: "/b",
      headers: Map([]),
      body: "",
    }).body,
    "b:[same]",
  )
}

///|
test "moving a route name to another method clears the old registration" {
  let app = @feather.App::new()
    .route_named("same", "GET", "/a", fn(ctx) {
      ctx.text(200, "get:[" + ctx.route_name() + "]")
    })
    .route_named("same", "POST", "/a", fn(ctx) {
      ctx.text(200, "post:[" + ctx.route_name() + "]")
    })
  assert_eq(
    app.respond({
      method: "GET",
      path: "/a",
      headers: Map([]),
      body: "",
    }).body,
    "get:[]",
  )
  assert_eq(
    app.respond({
      method: "POST",
      path: "/a",
      headers: Map([]),
      body: "",
    }).body,
    "post:[same]",
  )
}

///|
test "mounting a colliding child name clears the parent route name" {
  let parent = @feather.App::new().route_named("shared", "GET", "/parent", fn(ctx) {
    ctx.text(200, "parent:[" + ctx.route_name() + "]")
  })
  let child = @feather.App::new().route_named("shared", "GET", "/child", fn(ctx) {
    ctx.text(200, "child:[" + ctx.route_name() + "]")
  })
  ignore(parent.mount("/api", child))
  assert_eq(parent.url_for("shared"), Some("/api/child"))
  assert_eq(
    parent.respond({
      method: "GET",
      path: "/parent",
      headers: Map([]),
      body: "",
    }).body,
    "parent:[]",
  )
  assert_eq(
    parent.respond({
      method: "GET",
      path: "/api/child",
      headers: Map([]),
      body: "",
    }).body,
    "child:[shared]",
  )
}
