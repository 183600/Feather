///|
fn scope_test_request(path : String) -> @feather.Request {
  { method: "GET", path, headers: Map([]), body: "", }
}

///|
fn scope_test_handler(ctx : @feather.Context) -> Unit raise {
  ctx.text(200, if ctx.get("scoped") == "yes" { "in" } else { "out" })
}

///|
fn scope_test_mark(value : String, calls : Ref[Int32]) -> @feather.Middleware {
  fn(next) {
    fn(ctx) raise {
      calls.val = calls.val + 1
      ctx.set("scoped", value)
      next(ctx)
    }
  }
}

///|
fn scope_test_event(
  tag : String,
  events : Ref[Array[String]],
) -> @feather.Middleware {
  fn(next) {
    fn(ctx) raise {
      events.val.push(tag)
      next(ctx)
    }
  }
}

///|
test "use prefix matches whole path segments and ignores the query" {
  let calls = Ref(0)
  let app = @feather.App::new()
    .use_prefix("api/", scope_test_mark("yes", calls))
    .get("/api", scope_test_handler)
    .get("/api/users", scope_test_handler)
    .get("/apiary", scope_test_handler)
    .get("/other", scope_test_handler)
  for path in ["/api", "/api/users", "/api/users?tag=a"] {
    let response = app.respond(scope_test_request(path))
    assert_eq(response.status, 200)
    assert_eq(response.body, "in")
  }
  assert_eq(calls.val, 3)
  for path in ["/apiary", "/other"] {
    let response = app.respond(scope_test_request(path))
    assert_eq(response.status, 200)
    assert_eq(response.body, "out")
  }
  // The scoped middleware must not run for paths outside the prefix, including
  // the trailing-slash boundary case that does not name a route here.
  assert_eq(calls.val, 3)
}

///|
test "use prefix normalizes slashes like route groups" {
  let calls = Ref(0)
  let app = @feather.App::new()
    .use_prefix("api//v1/", scope_test_mark("yes", calls))
    .get("/api/v1/items", scope_test_handler)
    .get("/api/v2/items", scope_test_handler)
  assert_eq(app.respond(scope_test_request("/api/v1/items")).body, "in")
  assert_eq(app.respond(scope_test_request("/api/v2/items")).body, "out")
  assert_eq(calls.val, 1)
}

///|
test "root prefix installs middleware application wide" {
  let calls = Ref(0)
  let app = @feather.App::new()
    .use_prefix("/", scope_test_mark("yes", calls))
    .get("/one", scope_test_handler)
    .get("/two", scope_test_handler)
  assert_eq(app.respond(scope_test_request("/one")).body, "in")
  assert_eq(app.respond(scope_test_request("/two")).body, "in")
  assert_eq(calls.val, 2)
  let empty = @feather.App::new()
    .use_prefix("", scope_test_mark("yes", calls))
    .get("/three", scope_test_handler)
  assert_eq(empty.respond(scope_test_request("/three")).body, "in")
  assert_eq(calls.val, 3)
}

///|
test "scoped middleware can answer without reaching the handler" {
  let calls = Ref(0)
  let app = @feather.App::new()
    .use_prefix("/admin", fn(_next) {
      fn(ctx) raise {
        calls.val = calls.val + 1
        ctx.text(401, "denied")
      }
    })
    .get("/admin/panel", fn(ctx) { ctx.text(200, "secret") })
    .get("/public", fn(ctx) { ctx.text(200, "open") })
  let admin = app.respond(scope_test_request("/admin/panel"))
  assert_eq(admin.status, 401)
  assert_eq(admin.body, "denied")
  let public = app.respond(scope_test_request("/public"))
  assert_eq(public.status, 200)
  assert_eq(public.body, "open")
  assert_eq(calls.val, 1)
}

///|
test "scoped middleware keeps its position in the application chain" {
  let events : Ref[Array[String]] = Ref([])
  let app = @feather.App::new()
    .use(scope_test_event("before", events))
    .use_prefix("/api", scope_test_event("scoped", events))
    .use(scope_test_event("after", events))
    .get("/api/items", fn(ctx) {
      events.val.push("handler")
      ctx.text(200, "ok")
    })
    .get("/other", fn(ctx) {
      events.val.push("handler")
      ctx.text(200, "ok")
    })
  ignore(app.respond(scope_test_request("/api/items")))
  assert_eq(events.val.join(","), "before,scoped,after,handler")
  events.val.clear()
  ignore(app.respond(scope_test_request("/other")))
  assert_eq(events.val.join(","), "before,after,handler")
}

///|
test "use when sees state from earlier middleware and skips per request" {
  let calls = Ref(0)
  let app = @feather.App::new()
    .use(fn(next) {
      fn(ctx) raise {
        ctx.set("tenant", "acme")
        next(ctx)
      }
    })
    .use_when(fn(ctx) {
      ctx.get("tenant") == "acme" && ctx.get_method() == "GET"
    }, scope_test_mark("yes", calls))
    .get("/items", scope_test_handler)
    .post("/items", scope_test_handler)
  assert_eq(app.respond(scope_test_request("/items")).body, "in")
  let posted = app.respond({
    method: "POST",
    path: "/items",
    headers: Map([]),
    body: "",
  })
  assert_eq(posted.body, "out")
  assert_eq(calls.val, 1)
}

///|
test "feather facade exposes scoped middleware" {
  let calls = Ref(0)
  let feather = @feather.create_feather({
      host: "127.0.0.1",
      port: 0,
      timeout: 0,
    })
    .use_prefix("/api", scope_test_mark("yes", calls))
    .get("/api/items", scope_test_handler)
    .get("/health", scope_test_handler)
  assert_eq(feather.handle(scope_test_request("/api/items")).body, "in")
  assert_eq(feather.handle(scope_test_request("/health")).body, "out")
  assert_eq(calls.val, 1)
}
