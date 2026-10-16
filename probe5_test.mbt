// Additional regression tests for Feather.
test "Context redirect and html helpers" {
  let ctx = create_context()
  ctx.html(201, "<h1>hi</h1>")
  assert_eq(ctx.response.status, 201)
  assert_eq(ctx.response.headers.get("Content-Type"), Some("text/html; charset=utf-8"))
  assert_eq(ctx.response.body, "<h1>hi</h1>")
  ctx.redirect(302, "/elsewhere")
  assert_eq(ctx.response.status, 302)
  assert_eq(ctx.response.headers.get("Location"), Some("/elsewhere"))
  assert_eq(ctx.response.body, "")
}

test "Context ip returns remote address from state" {
  let ctx = create_context()
  ctx.state.set("remote_addr", "10.0.0.1:5555")
  assert_eq(ctx.ip(), "10.0.0.1:5555")
}

test "middleware logger receives formatted line" {
  let lines : Array[String] = []
  let app = App::new()
    .use(middleware_logger(log=line => lines.push(line)))
    .get("/logged", fn(ctx) { ctx.text(200, "ok") })
  let ctx = Context::new({ method: "GET", path: "/logged", headers: Map([]), body: "" })
  app.handle(ctx)
  assert_eq(lines.length(), 1)
  assert_eq(lines[0], "[200] GET /logged")
}

test "Router matching returns params for dynamic routes" {
  let router = create_router()
  router.add_route("GET", "/users/:id/posts/:post_id", fn(ctx) { ctx.text(200, "ok") })
  match router.matching("GET", "/users/7/posts/9") {
    Some(route) => {
      assert_eq(route.params.get("id"), Some("7"))
      assert_eq(route.params.get("post_id"), Some("9"))
    }
    None => fail("expected route match")
  }
}

test "url_decode decodes percent and plus" {
  assert_eq(url_decode("%20"), " ")
  assert_eq(url_decode("a+b"), "a b")
  assert_eq(url_decode("%2B"), "+")
  assert_eq(url_decode("%E4%B8%96"), "世")
  assert_eq(url_decode("100%"), "100%")
  assert_eq(url_decode("%zz"), "%zz")
}

test "middleware cors preflight short circuits" {
  let app = App::new()
    .use(middleware_cors())
    .get("/cors", fn(ctx) { ctx.text(200, "ok") })
  let ctx = Context::new({ method: "OPTIONS", path: "/cors", headers: Map([]), body: "" })
  app.handle(ctx)
  assert_eq(ctx.response.status, 204)
  assert_eq(
    ctx.response.headers.get("Access-Control-Allow-Origin"),
    Some("*"),
  )
}

test "method not allowed lists allowed methods" {
  let router = create_router()
  router.add_route("GET", "/res", fn(ctx) { ctx.text(200, "g") })
  router.add_route("POST", "/res", fn(ctx) { ctx.text(200, "p") })
  let ctx = Context::new({ method: "DELETE", path: "/res", headers: Map([]), body: "" })
  router.dispatch(ctx)
  assert_eq(ctx.response.status, 405)
  let allow = ctx.response.headers.get("Allow").unwrap_or("")
  assert_true(allow.contains("GET"))
  assert_true(allow.contains("POST"))
}
