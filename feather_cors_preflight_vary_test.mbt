///|
test "rejected CORS preflights vary on origin and requested headers" {
  let app = @feather.App::new()
    .use(
      @feather.middleware_cors_allowlist(
        ["https://good.example"],
        allow_credentials=true,
      ),
    )
    .get("/me", fn(ctx) { ctx.text(200, "ok") })
  let response = app.respond({
    method: "OPTIONS",
    path: "/me",
    headers: Map([
      ("Origin", "https://evil.example"),
      ("Access-Control-Request-Method", "POST"),
      ("Access-Control-Request-Headers", "X-Token"),
    ]),
    body: "",
  })
  assert_eq(response.status, 204)
  assert_eq(response.headers.get("Access-Control-Allow-Origin"), None)
  assert_eq(response.headers.get("Access-Control-Allow-Methods"), None)
  assert_eq(response.headers.get("Access-Control-Allow-Headers"), None)
  assert_eq(response.headers.get("Access-Control-Allow-Credentials"), None)
  let vary = response.headers.get("Vary").unwrap_or("")
  assert_true(vary.contains("Origin"), msg=vary)
  assert_true(vary.contains("Access-Control-Request-Method"), msg=vary)
  assert_true(vary.contains("Access-Control-Request-Headers"), msg=vary)
}

///|
test "accepted CORS preflights vary on origin and requested headers" {
  let app = @feather.App::new()
    .use(@feather.middleware_cors_with(allow_origin=fn(origin) {
      origin == "https://good.example"
    }))
    .get("/me", fn(ctx) { ctx.text(200, "ok") })
  let response = app.respond({
    method: "OPTIONS",
    path: "/me",
    headers: Map([
      ("Origin", "https://good.example"),
      ("Access-Control-Request-Method", "GET"),
    ]),
    body: "",
  })
  assert_eq(response.status, 204)
  assert_eq(
    response.headers.get("Access-Control-Allow-Origin"),
    Some("https://good.example"),
  )
  let vary = response.headers.get("Vary").unwrap_or("")
  assert_true(vary.contains("Origin"), msg=vary)
  assert_true(vary.contains("Access-Control-Request-Method"), msg=vary)
  assert_true(vary.contains("Access-Control-Request-Headers"), msg=vary)
}
