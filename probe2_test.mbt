// Router backtracking and request parsing regression tests

///|
test "probe backtrack param to wildcard" {
  let router = create_router()
  router.add_route("GET", "/a/:x/d", fn(ctx) { ctx.text(200, "param") })
  router.add_route("GET", "/a/*rest", fn(ctx) { ctx.text(200, "wild") })
  let ctx = Context::new({
    method: "GET",
    path: "/a/b/c",
    headers: Map([]),
    body: "",
  })
  router.dispatch(ctx)
  assert_eq(ctx.response.body, "wild")
  assert_eq(ctx.param("rest"), "b/c")
  assert_eq(ctx.param("x"), "")
}

///|
test "probe backtrack static to param" {
  let router = create_router()
  router.add_route("GET", "/a/b/d", fn(ctx) { ctx.text(200, "static") })
  router.add_route("GET", "/a/:x/c", fn(ctx) { ctx.text(200, "param") })
  let ctx = Context::new({
    method: "GET",
    path: "/a/b/c",
    headers: Map([]),
    body: "",
  })
  router.dispatch(ctx)
  assert_eq(ctx.response.body, "param")
  assert_eq(ctx.param("x"), "b")
}

///|
test "probe captures survive wildcard with ancestor param" {
  let router = create_router()
  router.add_route("GET", "/u/:id/x", fn(ctx) { ctx.text(200, "x") })
  router.add_route("GET", "/u/:id/*rest", fn(ctx) { ctx.text(200, "wild") })
  let ctx = Context::new({
    method: "GET",
    path: "/u/5/y",
    headers: Map([]),
    body: "",
  })
  router.dispatch(ctx)
  assert_eq(ctx.response.body, "wild")
  assert_eq(ctx.param("id"), "5")
  assert_eq(ctx.param("rest"), "y")
}

///|
test "probe middleware added after first handle still applies" {
  let app = App::new().get("/p", fn(ctx) { ctx.text(200, "p") })
  let ctx1 = Context::new({
    method: "GET",
    path: "/p",
    headers: Map([]),
    body: "",
  })
  app.handle(ctx1)
  assert_eq(ctx1.response.headers.get("X-After"), None)
  ignore(
    app.use(fn(next) {
      fn(ctx) raise {
        ctx.response.headers.set("X-After", "yes")
        next(ctx)
      }
    }),
  )
  let ctx2 = Context::new({
    method: "GET",
    path: "/p",
    headers: Map([]),
    body: "",
  })
  app.handle(ctx2)
  assert_eq(ctx2.response.headers.get("X-After"), Some("yes"))
}

///|
test "probe feather routes and middleware" {
  let feather = create_feather({ host: "localhost", port: 8080, timeout: 0, })
  ignore(feather.get("/f", fn(ctx) { ctx.text(200, "f") }))
  ignore(
    feather.use(fn(next) {
      fn(ctx) raise {
        ctx.response.headers.set("X-F", "1")
        next(ctx)
      }
    }),
  )
  let resp = feather.handle({
    method: "GET",
    path: "/f",
    headers: Map([]),
    body: "",
  })
  assert_eq(resp.body, "f")
  assert_eq(resp.headers.get("X-F"), Some("1"))
}

///|
test "probe json escaping" {
  let ctx = create_context()
  ctx.json(200, { "quote": "he said \"hi\"", "nl": "a\nb" })
  assert_eq(
    ctx.response.headers.get("Content-Type"),
    Some("application/json; charset=utf-8"),
  )
  assert_true(ctx.response.body.contains("\\\""))
}

///|
test "probe html and redirect" {
  let ctx = create_context()
  ctx.html(201, "<h1>hi</h1>")
  assert_eq(ctx.response.status, 201)
  assert_eq(
    ctx.response.headers.get("Content-Type"),
    Some("text/html; charset=utf-8"),
  )
  assert_eq(ctx.response.body, "<h1>hi</h1>")
  ctx.redirect(302, "/elsewhere")
  assert_eq(ctx.response.status, 302)
  assert_eq(ctx.response.headers.get("Location"), Some("/elsewhere"))
}

///|
test "probe 405 for wrong method dynamic route" {
  let router = create_router()
  router.add_route("GET", "/items/:id", fn(ctx) { ctx.text(200, "g") })
  let ctx = Context::new({
    method: "POST",
    path: "/items/3",
    headers: Map([]),
    body: "",
  })
  router.dispatch(ctx)
  assert_eq(ctx.response.status, 405)
}

///|
test "probe unknown method with dynamic tree" {
  let router = create_router()
  router.add_route("GET", "/x/:id", fn(ctx) { ctx.text(200, "g") })
  match router.route("PUT", "/x/1") {
    RouteMethodNotAllowed(methods) => assert_eq(methods.length(), 1)
    _ => fail("expected 405")
  }
}

///|
test "probe parse_urlencoded duplicate and empty" {
  let m = parse_urlencoded("a=1&a=2&b&c=&=d")
  assert_eq(m.get("a"), Some("2"))
  assert_eq(m.get("b"), Some(""))
  assert_eq(m.get("c"), Some(""))
  assert_eq(m.get(""), Some("d"))
}

///|
test "probe query missing and empty" {
  let ctx = Context::new({
    method: "GET",
    path: "/p?flag&empty=",
    headers: Map([]),
    body: "",
  })
  assert_eq(ctx.query("flag"), "")
  assert_eq(ctx.query("empty"), "")
  assert_eq(ctx.query("nope"), "")
}

///|
test "probe HEAD tree shadows GET fallback" {
  let router = create_router()
  router.add_route("HEAD", "/only-head", fn(ctx) { ctx.text(200, "h") })
  router.add_route("GET", "/only-get", fn(ctx) { ctx.text(200, "g") })
  match router.route("HEAD", "/only-get") {
    RouteFound(_) => ()
    other => {
      ignore(other)
      fail("HEAD /only-get should fall back to GET route")
    }
  }
}

///|
test "probe conflicting param names at same position" {
  let router = create_router()
  router.add_route("GET", "/u/:id", fn(ctx) {
    ctx.text(200, "id=" + ctx.param("id"))
  })
  router.add_route("GET", "/u/:name/posts", fn(ctx) {
    ctx.text(200, "name=" + ctx.param("name"))
  })
  let ctx = Context::new({
    method: "GET",
    path: "/u/42",
    headers: Map([]),
    body: "",
  })
  router.dispatch(ctx)
  assert_eq(ctx.response.body, "id=42")
}
