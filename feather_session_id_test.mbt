///|
test "session id access persists a stable cookie" {
  let store = @feather.SessionStore::new(ttl=3_600_000L)
  let app = @feather.App::new()
    .use(@feather.middleware_session(store))
    .get("/id", fn(ctx) { ctx.text(200, ctx.session_id().unwrap()) })
  let first = app.respond({
    method: "GET",
    path: "/id",
    headers: Map([]),
    body: "",
  })
  assert_eq(first.cookies.length(), 1)
  assert_eq(store.count(), 1)
  let id = first.body
  // The generated id must remain stable when the client presents its cookie;
  // reading it does not need to rewrite the session or refresh the cookie.
  let second = app.respond({
    method: "GET",
    path: "/id",
    headers: Map([("Cookie", "feather_session=" + id)]),
    body: "",
  })
  assert_eq(second.body, id)
  assert_eq(second.cookies.length(), 0)
}

///|
test "read-only session data access stays cookie-free" {
  let store = @feather.SessionStore::new(ttl=3_600_000L)
  let app = @feather.App::new()
    .use(@feather.middleware_session(store))
    .get("/read", fn(ctx) { ctx.text(200, ctx.session_get("user")) })
  let response = app.respond({
    method: "GET",
    path: "/read",
    headers: Map([]),
    body: "",
  })
  assert_eq(response.body, "")
  assert_eq(response.cookies.length(), 0)
  assert_eq(store.count(), 0)
}
