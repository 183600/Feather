///|
fn vary_error_response(accept : String) -> @feather.Response {
  let app = @feather.App::new()
  app.respond({
    method: "GET",
    path: "/missing",
    headers: Map([("Accept", accept)]),
    body: "",
  })
}

///|
test "negotiated error responses vary on Accept" {
  let plain = vary_error_response("text/plain")
  assert_eq(plain.status, 404)
  assert_eq(plain.headers.get("Vary"), Some("Accept"))
  assert_eq(plain.headers.get("Content-Type"), Some("text/plain; charset=utf-8"))

  let problem = vary_error_response("application/problem+json")
  assert_eq(problem.status, 404)
  assert_eq(problem.headers.get("Vary"), Some("Accept"))
  assert_eq(
    problem.headers.get("Content-Type"),
    Some("application/problem+json; charset=utf-8"),
  )
  assert_true(problem.body.contains("\"type\":\"about:blank\""))
}

///|
test "error helpers mark their Accept-dependent rendering" {
  let ctx = @feather.create_context()
  @feather.error_response(ctx, 500, "boom")
  assert_eq(ctx.response.headers.get("Vary"), Some("Accept"))

  let payload = @feather.create_context()
  @feather.error_response_with_payload(payload, 422, "bad", Json::object(Map([])))
  assert_eq(payload.response.headers.get("Vary"), Some("Accept"))

  let not_found = @feather.create_context()
  @feather.not_found(not_found)
  assert_eq(not_found.response.headers.get("Vary"), Some("Accept"))

  let internal = @feather.create_context()
  @feather.internal_error(internal, "detail")
  assert_eq(internal.response.headers.get("Vary"), Some("Accept"))
}
