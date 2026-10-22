///|
test "re-registering an equivalent route path drops the old name" {
  let app = @feather.App::new()
    .route_named("old", "GET", "/thing", fn(ctx) { ctx.text(200, "old") })
    .get("/thing/", fn(ctx) { ctx.text(200, "[" + ctx.route_name() + "]") })
  assert_eq(app.url_for("old"), None)
  assert_eq(
    app.respond({
      method: "GET",
      path: "/thing",
      headers: Map([]),
      body: "",
    }).body,
    "[]",
  )
}

///|
test "encoded and unicode spellings of one static route share its name" {
  let app = @feather.App::new()
    .route_named("cafe", "GET", "/café", fn(ctx) { ctx.text(200, "old") })
    .get("/caf%C3%A9", fn(ctx) { ctx.text(200, "[" + ctx.route_name() + "]") })
  assert_eq(app.url_for("cafe"), None)
  assert_eq(
    app.respond({
      method: "GET",
      path: "/caf%C3%A9",
      headers: Map([]),
      body: "",
    }).body,
    "[]",
  )
}

///|
test "renaming a parameter route drops the old name and params" {
  let app = @feather.App::new()
    .route_named("user", "GET", "/users/:id", fn(ctx) {
      ctx.text(200, "old:" + ctx.param("id"))
    })
    .get("/users/:name", fn(ctx) {
      ctx.text(200, "[" + ctx.route_name() + "]:" + ctx.param("name"))
    })
  assert_eq(app.url_for("user", params=Map([("id", "42")])), None)
  assert_eq(
    app.respond({
      method: "GET",
      path: "/users/42",
      headers: Map([]),
      body: "",
    }).body,
    "[]:42",
  )
}
