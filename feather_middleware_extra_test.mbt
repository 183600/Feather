///|
test "content type helpers normalize the media type" {
  let ctx = @feather.create_context()
  assert_eq(ctx.content_type(), "")
  assert_false(ctx.is_json())
  assert_false(ctx.is_form())
  assert_false(ctx.is_multipart())
  let json = @feather
    .Context::new({
      method: "POST",
      path: "/",
      headers: Map([("Content-Type", "Application/JSON; charset=UTF-8")]),
      body: "{}",
    })
  assert_eq(json.content_type(), "application/json")
  assert_true(json.is_json())
  let problem = @feather
    .Context::new({
      method: "POST",
      path: "/",
      headers: Map([("Content-Type", "application/problem+json")]),
      body: "{}",
    })
  assert_true(problem.is_json())
  let form = @feather
    .Context::new({
      method: "POST",
      path: "/",
      headers: Map([
        ("Content-Type", "application/x-www-form-urlencoded"),
      ]),
      body: "a=1",
    })
  assert_true(form.is_form())
  assert_true(
    @feather
      .Context::new({
        method: "POST",
        path: "/",
        headers: Map([("Content-Type", "multipart/form-data; boundary=X")]),
        body: "",
      })
      .is_multipart(),
  )
}

///|
test "form accessors only parse actual form media types" {
  let junk = @feather
    .Context::new({
      method: "POST",
      path: "/",
      headers: Map([
        ("Content-Type", "application/x-www-form-urlencoded-pwned"),
      ]),
      body: "a=1",
    })
  assert_false(junk.is_form())
  assert_eq(junk.form("a"), "")
  assert_eq(junk.form_values("a").length(), 0)
  assert_eq(junk.form_map().length(), 0)
  let parameterized = @feather
    .Context::new({
      method: "POST",
      path: "/",
      headers: Map([
        ("Content-Type", "application/x-www-form-urlencoded; charset=UTF-8"),
      ]),
      body: "a=1&b=2&a=3",
    })
  assert_true(parameterized.is_form())
  assert_eq(parameterized.form("a"), "3")
  assert_eq(parameterized.form_values("a").length(), 2)
  assert_eq(parameterized.form_map().get("b"), Some("2"))
}

///|
test "multipart accessors only parse actual multipart media types" {
  let junk = @feather
    .Context::new({
      method: "POST",
      path: "/",
      headers: Map([
        ("Content-Type", "multipart/form-data-pwned; boundary=X"),
      ]),
      body: "--X--\r\n",
    })
  assert_false(junk.is_multipart())
  assert_eq(junk.multipart().length(), 0)
}

///|
test "method override rewrites post requests from the header" {
  let app = @feather
    .App::new()
    .use(@feather.middleware_method_override())
    .delete("/items/1", fn(ctx) { ctx.text(200, "deleted") })
  let response = app.respond({
    method: "POST",
    path: "/items/1",
    headers: Map([("X-HTTP-Method-Override", "delete")]),
    body: "",
  })
  assert_eq(response.status, 200)
  assert_eq(response.body, "deleted")
}

///|
test "method override rewrites post requests from the form field" {
  let app = @feather
    .App::new()
    .use(@feather.middleware_method_override())
    .patch("/items/1", fn(ctx) { ctx.text(200, "patched") })
  let response = app.respond({
    method: "POST",
    path: "/items/1",
    headers: Map([
      ("Content-Type", "application/x-www-form-urlencoded"),
    ]),
    body: "_method=PATCH&name=x",
  })
  assert_eq(response.status, 200)
  assert_eq(response.body, "patched")
}

///|
test "method override ignores unknown or non-post overrides" {
  let app = @feather
    .App::new()
    .use(@feather.middleware_method_override())
    .delete("/items/1", fn(ctx) { ctx.text(200, "deleted") })
  let trace = app.respond({
    method: "POST",
    path: "/items/1",
    headers: Map([("X-HTTP-Method-Override", "TRACE")]),
    body: "",
  })
  assert_eq(trace.status, 405)
  let direct = app.respond({
    method: "PUT",
    path: "/items/1",
    headers: Map([("X-HTTP-Method-Override", "DELETE")]),
    body: "",
  })
  assert_eq(direct.status, 405)
}

///|
test "https redirect sends insecure requests to the https url" {
  let app = @feather
    .App::new()
    .use(@feather.middleware_https_redirect())
    .get("/dashboard", fn(ctx) { ctx.text(200, "ok") })
  let insecure = app.respond({
    method: "GET",
    path: "/dashboard?tab=1",
    headers: Map([("Host", "example.com")]),
    body: "",
  })
  assert_eq(insecure.status, 308)
  assert_eq(
    insecure.headers.get("Location"),
    Some("https://example.com/dashboard?tab=1"),
  )
  let secure = app.respond({
    method: "GET",
    path: "/dashboard",
    headers: Map([
      ("Host", "example.com"),
      ("X-Forwarded-Proto", "https"),
    ]),
    body: "",
  })
  assert_eq(secure.status, 200)
  assert_eq(secure.body, "ok")
}

///|
test "https redirect can be temporary and use a fixed host" {
  let app = @feather
    .App::new()
    .use(@feather.middleware_https_redirect(permanent=false, host="api.test"))
    .get("/", fn(ctx) { ctx.text(200, "ok") })
  let response = app.respond({
    method: "GET",
    path: "/",
    headers: Map([("Host", "ignored.test")]),
    body: "",
  })
  assert_eq(response.status, 307)
  assert_eq(response.headers.get("Location"), Some("https://api.test/"))
}

///|
test "https redirect passes requests without a host through" {
  let app = @feather
    .App::new()
    .use(@feather.middleware_https_redirect())
    .get("/", fn(ctx) { ctx.text(200, "ok") })
  let response = app.respond({
    method: "GET",
    path: "/",
    headers: Map([]),
    body: "",
  })
  assert_eq(response.status, 200)
}

///|
test "secure headers include hsts and csp when configured" {
  let app = @feather
    .App::new()
    .use(
      @feather.middleware_secure_headers(
        hsts="max-age=31536000; includeSubDomains",
        content_security_policy="default-src 'self'",
      ),
    )
    .get("/", fn(ctx) { ctx.text(200, "ok") })
  let response = app.respond({
    method: "GET",
    path: "/",
    headers: Map([]),
    body: "",
  })
  assert_eq(response.headers.get("X-Content-Type-Options"), Some("nosniff"))
  assert_eq(response.headers.get("X-Frame-Options"), Some("DENY"))
  assert_eq(response.headers.get("Referrer-Policy"), Some("no-referrer"))
  assert_eq(
    response.headers.get("Strict-Transport-Security"),
    Some("max-age=31536000; includeSubDomains"),
  )
  assert_eq(
    response.headers.get("Content-Security-Policy"),
    Some("default-src 'self'"),
  )
}

///|
test "secure headers leave hsts and csp unset by default" {
  let app = @feather
    .App::new()
    .use(@feather.middleware_secure_headers())
    .get("/", fn(ctx) { ctx.text(200, "ok") })
  let response = app.respond({
    method: "GET",
    path: "/",
    headers: Map([]),
    body: "",
  })
  assert_eq(response.headers.get("Strict-Transport-Security"), None)
  assert_eq(response.headers.get("Content-Security-Policy"), None)
}

///|
test "context vary appends entries once" {
  let ctx = @feather.create_context()
  ctx.vary("Origin")
  ctx.vary("Origin")
  ctx.vary("Accept-Encoding")
  assert_eq(ctx.response.headers.get("Vary"), Some("Origin, Accept-Encoding"))
}

///|
test "context vary matches whole entries, not substrings" {
  let ctx = @feather.create_context()
  ctx.vary("Accept-Encoding")
  ctx.vary("Accept")
  assert_eq(
    ctx.response.headers.get("Vary"),
    Some("Accept-Encoding, Accept"),
  )
  ctx.vary("accept-encoding")
  assert_eq(
    ctx.response.headers.get("Vary"),
    Some("Accept-Encoding, Accept"),
  )
}

///|
test "router normalizes method casing when registering" {
  let app = @feather
    .App::new()
    .route("post", "/submit", fn(ctx) { ctx.text(200, "posted") })
  assert_true(app.has_route("post", "/submit"))
  assert_true(app.has_route("POST", "/submit"))
  let response = app.respond({
    method: "POST",
    path: "/submit",
    headers: Map([]),
    body: "",
  })
  assert_eq(response.status, 200)
  assert_eq(response.body, "posted")
}

///|
test "router normalizes method casing when matching" {
  let app = @feather
    .App::new()
    .get("/ping", fn(ctx) { ctx.text(200, "pong") })
  let response = app.respond({
    method: "get",
    path: "/ping",
    headers: Map([]),
    body: "",
  })
  assert_eq(response.status, 200)
  assert_eq(response.body, "pong")
  assert_true(app.has_route("get", "/ping"))
}

///|
test "named routes keep normalized methods" {
  let app = @feather
    .App::new()
    .route_named("submit", "post", "/submit", fn(ctx) { ctx.text(200, "ok") })
  assert_eq(app.router.route_name("submit").unwrap().method, "POST")
  assert_eq(app.url_for("submit"), Some("/submit"))
}

///|
test "cors does not duplicate an existing vary origin" {
  let app = @feather
    .App::new()
    .use(@feather.middleware_cors(allow_origin="https://app.test"))
    .get("/", fn(ctx) { ctx.text(200, "ok") })
  let response = app.respond({
    method: "GET",
    path: "/",
    headers: Map([("Origin", "https://app.test")]),
    body: "",
  })
  assert_eq(response.headers.get("Vary"), Some("Origin"))
  assert_eq(
    response.headers.get("Access-Control-Allow-Origin"),
    Some("https://app.test"),
  )
}
