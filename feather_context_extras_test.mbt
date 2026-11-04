///|
test "send_status writes the reason phrase as the body" {
  let ctx = @feather.Context::new({
    method: "GET",
    path: "/",
    headers: Map([]),
    body: "",
  })
  ctx.send_status(418)
  assert_eq(ctx.response.status, 418)
  assert_eq(ctx.response.body, @feather.status_text(418))
  assert_eq(
    ctx.response_header("Content-Type"),
    "text/plain; charset=utf-8",
  )
}

///|
test "send_status replaces a body prepared earlier" {
  let ctx = @feather.Context::new({
    method: "GET",
    path: "/",
    headers: Map([]),
    body: "",
  })
  ctx.html(200, "<html></html>")
  ctx.send_status(503)
  assert_eq(ctx.response.status, 503)
  assert_eq(ctx.response.body, @feather.status_text(503))
  assert_eq(ctx.response_header("Content-Type"), "text/plain; charset=utf-8")
}

///|
test "send_status answers 204 and 205 without a body" {
  let ctx = @feather.Context::new({
    method: "GET",
    path: "/",
    headers: Map([]),
    body: "",
  })
  ctx.text(200, "previous")
  ctx.send_status(204)
  assert_eq(ctx.response.status, 204)
  assert_eq(ctx.response.body, "")
  assert_false(ctx.has_response_header("Content-Type"))

  let reset = @feather.Context::new({
    method: "GET",
    path: "/",
    headers: Map([]),
    body: "",
  })
  reset.send_status(205)
  assert_eq(reset.response.status, 205)
  assert_eq(reset.response.body, "")
}

///|
test "send_status answers 304 without a body but keeps validators" {
  let ctx = @feather.Context::new({
    method: "GET",
    path: "/",
    headers: Map([]),
    body: "",
  })
  ctx.json(200, { "id": "1" })
  ctx.set_header("ETag", "\"v1\"")
  ctx.send_status(304)
  assert_eq(ctx.response.status, 304)
  assert_eq(ctx.response.body, "")
  assert_false(ctx.has_response_header("Content-Type"))
  assert_eq(ctx.response_header("ETag"), "\"v1\"")
}

///|
test "location installs the header without touching status or body" {
  let ctx = @feather.Context::new({
    method: "POST",
    path: "/items",
    headers: Map([]),
    body: "",
  })
  ctx.json(201, { "created": "true" })
  ctx.location("/items/42")
  assert_eq(ctx.response.status, 201)
  assert_eq(ctx.response.body, "{\"created\":\"true\"}")
  assert_eq(ctx.response_header("Location"), "/items/42")
}

///|
test "location strips control characters" {
  let ctx = @feather.Context::new({
    method: "GET",
    path: "/",
    headers: Map([]),
    body: "",
  })
  ctx.location("/next\r\nX-Injected: 1")
  assert_eq(ctx.response_header("Location"), "/nextX-Injected: 1")
}

///|
test "redirect overwrites a previously installed location" {
  let ctx = @feather.Context::new({
    method: "GET",
    path: "/",
    headers: Map([]),
    body: "",
  })
  ctx.location("/stale")
  ctx.redirect(303, "/fresh")
  assert_eq(ctx.response.status, 303)
  assert_eq(ctx.response_header("Location"), "/fresh")
}

///|
test "ips reports only the peer without a trusted proxy" {
  let app = @feather.App::new().get("/ips", fn(ctx) {
    ctx.json(200, { "ips": ctx.ips().join(",") })
  })
  // Without `trust_proxy` the forwarded headers are untrusted, so the list
  // holds just the (offline default) peer address.
  let response = app.respond({
    method: "GET",
    path: "/ips",
    headers: Map([("X-Forwarded-For", "203.0.113.7")]),
    body: "",
  })
  assert_eq(response.status, 200)
  assert_eq(response.body, "{\"ips\":\"127.0.0.1\"}")
}

///|
test "ips lists the trusted forwarded chain with the peer last" {
  let app = @feather.App::new()
    .trust_proxy(2)
    .get("/ips", fn(ctx) {
      let ips = ctx.ips()
      ctx.json(200, {
        "count": ips.length().to_string(),
        "first": ips[0],
        "last": ips[ips.length() - 1],
      })
    })
  // The chain is closest proxy first and the peer (offline default
  // `127.0.0.1`) is appended, so the address `ip()` selects sits at index
  // `hops - 1`.
  let response = app.respond({
    method: "GET",
    path: "/ips",
    headers: Map([("X-Forwarded-For", "203.0.113.7, 198.51.100.9")]),
    body: "",
  })
  assert_eq(response.status, 200)
  assert_true(response.body.contains("\"count\":\"3\""))
  assert_true(response.body.contains("\"first\":\"198.51.100.9\""))
  assert_true(response.body.contains("\"last\":\"127.0.0.1\""))
}

///|
test "ips agrees with ip at the trusted hop" {
  let app = @feather.App::new()
    .trust_proxy(2)
    .get("/ips", fn(ctx) {
      ctx.json(200, { "selected": ctx.ip(), "ips": ctx.ips().join(",") })
    })
  let response = app.respond({
    method: "GET",
    path: "/ips",
    headers: Map([("X-Forwarded-For", "203.0.113.7, 198.51.100.9")]),
    body: "",
  })
  assert_eq(response.status, 200)
  // `ip()` walks `hops` steps back from the peer, which is the same entry the
  // `ips()` list reports at index `hops - 1`.
  assert_true(response.body.contains("\"selected\":\"203.0.113.7\""))
  assert_true(response.body.contains("\"ips\":\"198.51.100.9,203.0.113.7,127.0.0.1\""))
}

///|
test "ips drops placeholder entries from addressless hops" {
  let app = @feather.App::new()
    .trust_proxy(2)
    .get("/ips", fn(ctx) {
      let ips = ctx.ips()
      let mut placeholders = 0
      for address in ips {
        if address == "" {
          placeholders = placeholders + 1
        }
      }
      ctx.json(200, { "placeholders": placeholders.to_string() })
    })
  let response = app.respond({
    method: "GET",
    path: "/ips",
    headers: Map([("X-Forwarded-For", "198.51.100.9, unknown")]),
    body: "",
  })
  assert_eq(response.status, 200)
  assert_true(response.body.contains("\"placeholders\":\"0\""))
}

///|
test "method_not_allowed replaces the default 405 body" {
  let app = @feather.App::new()
    .method_not_allowed(fn(ctx) {
      ctx.json_value(405, Json::object({
        "error": "method not allowed",
      }))
    })
    .get("/only-get", fn(ctx) { ctx.text(200, "get") })
  let response = app.respond({
    method: "POST",
    path: "/only-get",
    headers: Map([]),
    body: "",
  })
  assert_eq(response.status, 405)
  assert_true(response.body.contains("method not allowed"))
  // The framework still supplies the RFC-required `Allow` header.
  assert_eq(response.headers.get("Allow"), Some("GET, HEAD"))
}

///|
test "method_not_allowed keeps automatic OPTIONS responses" {
  let app = @feather.App::new()
    .method_not_allowed(fn(ctx) { ctx.text(405, "custom") })
    .get("/only-get", fn(ctx) { ctx.text(200, "get") })
  let response = app.respond({
    method: "OPTIONS",
    path: "/only-get",
    headers: Map([]),
    body: "",
  })
  assert_eq(response.status, 204)
  assert_eq(response.body, "")
  assert_eq(response.headers.get("Allow"), Some("GET, HEAD"))
}

///|
test "method_not_allowed still runs middleware" {
  let app = @feather.App::new()
    .use(fn(next) {
      fn(ctx) {
        ctx.set_header("X-From-Middleware", "yes")
        next(ctx)
      }
    })
    .method_not_allowed(fn(ctx) { ctx.text(405, "custom") })
    .get("/only-get", fn(ctx) { ctx.text(200, "get") })
  let response = app.respond({
    method: "DELETE",
    path: "/only-get",
    headers: Map([]),
    body: "",
  })
  assert_eq(response.status, 405)
  assert_eq(response.body, "custom")
  assert_eq(response.headers.get("X-From-Middleware"), Some("yes"))
}

///|
test "method_not_allowed does not affect unmatched paths" {
  let app = @feather.App::new()
    .method_not_allowed(fn(ctx) { ctx.text(405, "custom") })
    .get("/known", fn(ctx) { ctx.text(200, "get") })
  let response = app.respond({
    method: "POST",
    path: "/unknown",
    headers: Map([]),
    body: "",
  })
  assert_eq(response.status, 404)
}
