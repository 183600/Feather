///|
fn id_trust_app(middleware : @feather.Middleware) -> @feather.App {
  @feather.App::new()
    .use(middleware)
    .get("/id", fn(ctx) { ctx.text(200, ctx.request_id()) })
}

///|
fn id_trust_response(
  app : @feather.App,
  value : String,
) -> @feather.Response {
  app.respond({
    method: "GET",
    path: "/id",
    headers: Map([("X-Request-Id", value)]),
    body: "",
  })
}

///|
test "request id trusts an incoming header by default" {
  let app = id_trust_app(@feather.middleware_request_id())
  let response = id_trust_response(app, "upstream-42")
  assert_eq(response.headers.get("X-Request-Id"), Some("upstream-42"))
  assert_eq(response.body, "upstream-42")
}

///|
test "request id can ignore a spoofable incoming header" {
  let app = id_trust_app(@feather.middleware_request_id(trust_incoming=false))
  let response = id_trust_response(app, "attacker-chosen")
  assert_eq(response.headers.get("X-Request-Id"), Some("feather-1"))
  assert_eq(response.body, "feather-1")

  let next = id_trust_response(app, "another")
  assert_eq(next.headers.get("X-Request-Id"), Some("feather-2"))
  assert_eq(next.body, "feather-2")
}

///|
test "request id ignores incoming values but still uses a custom generator" {
  let calls = Ref(0)
  let app = id_trust_app(
    @feather.middleware_request_id(
      trust_incoming=false,
      generate=fn() {
        calls.val = calls.val + 1
        "generated-" + calls.val.to_string()
      },
    ),
  )
  let response = id_trust_response(app, "client-value")
  assert_eq(response.headers.get("X-Request-Id"), Some("generated-1"))
  assert_eq(response.body, "generated-1")
  assert_eq(calls.val, 1)
}

///|
test "request id still bounds generated ids when incoming values are ignored" {
  let app = id_trust_app(
    @feather.middleware_request_id(
      trust_incoming=false,
      max_length=4,
      generate=fn() { "too-long" },
    ),
  )
  let response = id_trust_response(app, "also-too-long")
  assert_eq(response.headers.get("X-Request-Id"), Some("feather-1"))
  assert_eq(response.body, "feather-1")
}
