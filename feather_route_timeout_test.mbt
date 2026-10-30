///|
test "route timeout applies to parameter and wildcard patterns" {
  let app = @feather.App::new()
    .get("/items/:id", fn(ctx) { ctx.text(200, ctx.param("id")) })
    .get("/files/*path", fn(ctx) { ctx.text(200, ctx.param("path")) })
    .route_timeout("GET", "/items/:id", 25)
    .route_timeout("GET", "/files/*path", 75)
  assert_eq(app.router.timeout_for("GET", "/items/42"), 25)
  assert_eq(app.router.timeout_for("HEAD", "/items/42"), 25)
  assert_eq(app.router.timeout_for("GET", "/files/a/b"), 75)
  assert_eq(app.router.timeout_for("GET", "/other"), 0)
}

///|
test "route timeout can be cleared and is reset by re-registration" {
  let app = @feather.App::new()
    .get("/items/:id", fn(ctx) { ctx.text(200, ctx.param("id")) })
    .route_timeout("GET", "/items/:id", 25)
  assert_eq(app.router.timeout_for("GET", "/items/1"), 25)
  ignore(app.route_timeout("GET", "/items/:id", 0))
  assert_eq(app.router.timeout_for("GET", "/items/1"), 0)
  ignore(app.route_timeout("GET", "/items/:id", 25))
  ignore(app.get("/items/:id", fn(ctx) { ctx.text(201, ctx.param("id")) }))
  assert_eq(app.router.timeout_for("GET", "/items/1"), 0)
}

///|
test "route timeout through a group uses the prefixed path" {
  let app = @feather.App::new()
  let group = app.group("/api")
    .get("/slow", fn(ctx) { ctx.text(200, "slow") })
    .route_timeout("GET", "/slow", 30)
  ignore(group)
  assert_eq(app.router.timeout_for("GET", "/api/slow"), 30)
  assert_eq(app.router.timeout_for("GET", "/slow"), 0)
}

///|
test "mounted routes keep their per-route timeout" {
  let child = @feather.App::new()
    .get("/slow", fn(ctx) { ctx.text(200, "slow") })
    .route_timeout("GET", "/slow", 40)
  let parent = @feather.App::new().mount("/api", child)
  assert_eq(parent.router.timeout_for("GET", "/api/slow"), 40)
}

///|
async test "a route timeout overrides the application timeout for body reads" {
  let app = @feather.App::new()
    .request_timeout(2000)
    .post("/fast", fn(ctx) raise { ctx.text(200, ctx.body_text()) })
    .post("/slow", fn(ctx) raise { ctx.text(200, ctx.body_text()) })
    .route_timeout("POST", "/fast", 50)
  with_raw_server(app, conn => {
    conn.write(
      @utf8.encode(
        "POST /fast HTTP/1.1\r\nHost: test\r\nContent-Length: 10\r\nConnection: close\r\n\r\n",
      ),
    )
    let head = read_http_head(conn)
    assert_true(head.has_prefix("HTTP/1.1 504"), msg=head)
  })
}
