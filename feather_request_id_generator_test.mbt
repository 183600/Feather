///|
fn request_id_app(
  middleware : @feather.Middleware,
) -> @feather.App {
  @feather.App::new()
    .use(middleware)
    .get("/id", fn(ctx) { ctx.text(200, ctx.request_id()) })
}

///|
fn request_id_of(
  app : @feather.App,
  headers : Map[String, String],
) -> @feather.Response {
  app.respond({
    method: "GET",
    path: "/id",
    headers,
    body: "",
  })
}

///|
test "request id uses a custom generator when the client sends none" {
  let sequence = Ref(0)
  let app = request_id_app(
    @feather.middleware_request_id(
      generate=fn() {
        sequence.val = sequence.val + 1
        "req-" + sequence.val.to_string()
      },
    ),
  )
  let first = request_id_of(app, Map([]))
  assert_eq(first.headers.get("X-Request-Id"), Some("req-1"))
  assert_eq(first.body, "req-1")
  let second = request_id_of(app, Map([]))
  assert_eq(second.headers.get("X-Request-Id"), Some("req-2"))
  assert_eq(second.body, "req-2")
}

///|
test "an incoming request id wins over the generator" {
  let calls = Ref(0)
  let app = request_id_app(
    @feather.middleware_request_id(
      generate=fn() {
        calls.val = calls.val + 1
        "generated"
      },
    ),
  )
  let response = request_id_of(app, Map([("X-Request-Id", " trace-9 ")]))
  assert_eq(response.headers.get("X-Request-Id"), Some("trace-9"))
  assert_eq(response.body, "trace-9")
  assert_eq(calls.val, 0)
}

///|
test "generated ids are sanitized and empty output falls back" {
  let outputs = ["  gen-1\t", "\r\n", "ok-2"]
  let next = Ref(0)
  let app = request_id_app(
    @feather.middleware_request_id(
      generate=fn() {
        let index = next.val
        next.val = next.val + 1
        outputs[index]
      },
    ),
  )
  let first = request_id_of(app, Map([]))
  assert_eq(first.headers.get("X-Request-Id"), Some("gen-1"))
  let second = request_id_of(app, Map([]))
  assert_eq(second.headers.get("X-Request-Id"), Some("feather-1"))
  let third = request_id_of(app, Map([]))
  assert_eq(third.headers.get("X-Request-Id"), Some("ok-2"))
}

///|
test "request id max length rejects over-long incoming values" {
  let app = request_id_app(@feather.middleware_request_id(max_length=4))
  let overlong = request_id_of(app, Map([("X-Request-Id", "trace-123")]))
  assert_eq(overlong.headers.get("X-Request-Id"), Some("feather-1"))
  let exact = request_id_of(app, Map([("X-Request-Id", "abc")]))
  assert_eq(exact.headers.get("X-Request-Id"), Some("abc"))
  let generated = request_id_app(
    @feather.middleware_request_id(
      max_length=4,
      generate=fn() { "too-long" },
    ),
  )
  assert_eq(
    request_id_of(generated, Map([])).headers.get("X-Request-Id"),
    Some("feather-1"),
  )
}

///|
test "request id max length zero or negative leaves ids unbounded" {
  for limit in [0, -1] {
    let app = request_id_app(@feather.middleware_request_id(max_length=limit))
    let response = request_id_of(
      app,
      Map([("X-Request-Id", "a-long-incoming-request-id")]),
    )
    assert_eq(
      response.headers.get("X-Request-Id"),
      Some("a-long-incoming-request-id"),
      msg=limit.to_string(),
    )
  }
}
