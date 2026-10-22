///|
test "cors does not echo a malformed origin into response headers" {
  let app = @feather.App::new()
    .use(@feather.middleware_cors(allow_credentials=true))
    .get("/", fn(ctx) { ctx.text(200, "ok") })
  let response = app.respond({
    method: "GET",
    path: "/",
    headers: Map([("Origin", "https://app.test\r\nX-Injected: yes")]),
    body: "",
  })
  let allowed = response.headers.get("Access-Control-Allow-Origin").unwrap_or("")
  assert_false(allowed.contains("\r"))
  assert_false(allowed.contains("\n"))
  assert_false(allowed.contains("X-Injected"))
  assert_eq(response.headers.get("Vary"), None)
  assert_eq(response.status, 200)
}

///|
test "cors does not echo malformed requested headers" {
  let app = @feather.App::new()
    .use(@feather.middleware_cors(allow_credentials=true))
    .get("/", fn(ctx) { ctx.text(200, "ok") })
  let response = app.respond({
    method: "OPTIONS",
    path: "/",
    headers: Map([
      ("Origin", "https://app.test"),
      ("Access-Control-Request-Method", "GET"),
      ("Access-Control-Request-Headers", "X-One\r\nX-Injected: yes"),
    ]),
    body: "",
  })
  assert_eq(response.status, 204)
  let allowed = response.headers.get("Access-Control-Allow-Headers").unwrap_or("")
  assert_false(allowed.contains("\r"))
  assert_false(allowed.contains("\n"))
  assert_eq(allowed, "X-OneX-Injected: yes")
}

///|
test "https redirect passes through a host with control characters" {
  let app = @feather.App::new()
    .use(@feather.middleware_https_redirect())
    .get("/", fn(ctx) { ctx.text(200, "ok") })
  let response = app.respond({
    method: "GET",
    path: "/",
    headers: Map([("Host", "example.test\r\nX-Injected: yes")]),
    body: "",
  })
  assert_eq(response.status, 200)
  assert_eq(response.headers.get("Location"), None)
}

///|
test "https redirect strips control characters from the request path" {
  let app = @feather.App::new()
    .use(@feather.middleware_https_redirect())
    .get("/", fn(ctx) { ctx.text(200, "ok") })
  let response = app.respond({
    method: "GET",
    path: "/dashboard\r\nX-Injected: yes?tab=1",
    headers: Map([("Host", "example.test")]),
    body: "",
  })
  assert_eq(response.status, 308)
  let location = response.headers.get("Location").unwrap_or("")
  assert_false(location.contains("\r"))
  assert_false(location.contains("\n"))
  assert_eq(location, "https://example.test/dashboardX-Injected: yes?tab=1")
}
