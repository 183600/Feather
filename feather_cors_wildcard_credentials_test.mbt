///|
test "wildcard CORS with credentials varies on origin and omits an invalid grant" {
  let app = @feather.App::new()
    .use(@feather.middleware_cors(allow_credentials=true))
    .get("/me", fn(ctx) { ctx.text(200, "ok") })

  let anonymous = @feather.Context::new({
    method: "GET",
    path: "/me",
    headers: Map([]),
    body: "",
  })
  app.handle(anonymous)
  assert_eq(
    anonymous.response.headers.get("Access-Control-Allow-Origin"),
    Some("*"),
  )
  assert_eq(
    anonymous.response.headers.get("Access-Control-Allow-Credentials"),
    None,
  )
  assert_eq(anonymous.response.headers.get("Vary"), Some("Origin"))

  let credentialed = @feather.Context::new({
    method: "GET",
    path: "/me",
    headers: Map([("Origin", "https://app.example")]),
    body: "",
  })
  app.handle(credentialed)
  assert_eq(
    credentialed.response.headers.get("Access-Control-Allow-Origin"),
    Some("https://app.example"),
  )
  assert_eq(
    credentialed.response.headers.get("Access-Control-Allow-Credentials"),
    Some("true"),
  )
  assert_eq(credentialed.response.headers.get("Vary"), Some("Origin"))
}
