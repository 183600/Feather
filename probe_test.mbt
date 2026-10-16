///|
test "probe static beats param" {
  let router = create_router()
  router.add_route("GET", "/users/new", fn(ctx) { ctx.text(200, "static") })
  router.add_route("GET", "/users/:id", fn(ctx) { ctx.text(200, "param") })
  let ctx = Context::new({
    method: "GET",
    path: "/users/new",
    headers: Map([]),
    body: "",
  })
  router.dispatch(ctx)
  assert_eq(ctx.response.body, "static")
  assert_eq(ctx.param("id"), "")
}

///|
test "probe param value" {
  let router = create_router()
  router.add_route("GET", "/users/:id", fn(ctx) { ctx.text(200, "param") })
  let ctx = Context::new({
    method: "GET",
    path: "/users/42",
    headers: Map([]),
    body: "",
  })
  router.dispatch(ctx)
  assert_eq(ctx.response.body, "param")
  assert_eq(ctx.param("id"), "42")
}

///|
test "probe wildcard value" {
  let router = create_router()
  router.add_route("GET", "/static/*path", fn(ctx) { ctx.text(200, "wild") })
  let ctx = Context::new({
    method: "GET",
    path: "/static/a/b/c",
    headers: Map([]),
    body: "",
  })
  router.dispatch(ctx)
  assert_eq(ctx.response.body, "wild")
  assert_eq(ctx.param("path"), "a/b/c")
}

///|
test "probe 405 allow" {
  let router = create_router()
  router.add_route("GET", "/resource", fn(ctx) { ctx.text(200, "g") })
  router.add_route("POST", "/resource", fn(ctx) { ctx.text(200, "p") })
  let ctx = Context::new({
    method: "DELETE",
    path: "/resource",
    headers: Map([]),
    body: "",
  })
  router.dispatch(ctx)
  assert_eq(ctx.response.status, 405)
  let allow = ctx.response.headers.get("Allow").unwrap_or("")
  assert_true(allow.contains("GET"))
  assert_true(allow.contains("POST"))
}

///|
test "probe nested param names" {
  let router = create_router()
  router.add_route("GET", "/users/:id/posts/:post_id", fn(ctx) {
    ctx.text(200, "ok")
  })
  let ctx = Context::new({
    method: "GET",
    path: "/users/7/posts/9",
    headers: Map([]),
    body: "",
  })
  router.dispatch(ctx)
  assert_eq(ctx.param("id"), "7")
  assert_eq(ctx.param("post_id"), "9")
}

///|
test "probe query decoding" {
  let ctx = Context::new({
    method: "GET",
    path: "/search?q=hello+world&x=%E4%B8%96",
    headers: Map([]),
    body: "",
  })
  assert_eq(ctx.query("q"), "hello world")
  assert_eq(ctx.query("x"), "世")
}

///|
test "probe form" {
  let ctx = Context::new({
    method: "POST",
    path: "/form",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: "a=1&b=hello+world",
  })
  assert_eq(ctx.form("a"), "1")
  assert_eq(ctx.form("b"), "hello world")
}

///|
test "probe url_decode trailing percent" {
  assert_eq(url_decode("%"), "%")
  assert_eq(url_decode("%2"), "%2")
  assert_eq(url_decode("%20"), " ")
  assert_eq(url_decode("a+b"), "a b")
}

///|
test "probe HEAD falls back to GET" {
  let router = create_router()
  router.add_route("GET", "/thing", fn(ctx) { ctx.text(200, "get") })
  match router.route("HEAD", "/thing") {
    RouteFound(_) => ()
    _ => fail("HEAD should fall back to GET")
  }
}

///|
test "probe root route" {
  let router = create_router()
  router.add_route("GET", "/", fn(ctx) { ctx.text(200, "root") })
  let ctx = Context::new({
    method: "GET",
    path: "/",
    headers: Map([]),
    body: "",
  })
  router.dispatch(ctx)
  assert_eq(ctx.response.body, "root")
}

///|
test "probe empty router has no route" {
  let router = create_router()
  match router.route("GET", "/anything") {
    RouteNotFound => ()
    _ => fail("empty router should be NotFound")
  }
}

///|
test "probe route registered with query" {
  let router = create_router()
  router.add_route("GET", "/q?a=1", fn(ctx) { ctx.text(200, "q") })
  let ctx = Context::new({
    method: "GET",
    path: "/q?b=2",
    headers: Map([]),
    body: "",
  })
  router.dispatch(ctx)
  assert_eq(ctx.response.body, "q")
  assert_eq(ctx.query("b"), "2")
}

///|
test "probe wildcard param exposed" {
  let router = create_router()
  router.add_route("GET", "/files/*rest", fn(ctx) {
    ctx.text(200, ctx.param("rest"))
  })
  let ctx = Context::new({
    method: "GET",
    path: "/files/a.txt",
    headers: Map([]),
    body: "",
  })
  router.dispatch(ctx)
  assert_eq(ctx.response.body, "a.txt")
}

///|
test "probe unnamed wildcard matches and reports value" {
  let router = create_router()
  router.add_route("GET", "/files/*", fn(ctx) { ctx.text(200, "ok") })
  match router.route("GET", "/files/a/b.txt") {
    RouteFound(route) => {
      assert_eq(route.wildcard, "a/b.txt")
      assert_eq(route.wildcard_name, "")
    }
    _ => fail("expected wildcard match")
  }
}
