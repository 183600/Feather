///|
fn session_test_cookie_pair(set_cookie : String) -> String {
  match set_cookie.find(";") {
    Some(end) => set_cookie[:end].to_owned()
    None => set_cookie
  }
}

///|
test "a session that expires during a request is not written back" {
  let store = @feather.SessionStore::new(ttl=600_000L)
  let app = @feather.App::new()
    .use(@feather.middleware_session(store))
    .get("/login", fn(ctx) {
      ignore(ctx.session_set("user", "alice"))
      ctx.text(200, "login")
    })
    .get("/expire", fn(ctx) {
      ignore(ctx.session_set("late", "value"))
      match ctx.session() {
        Some(session) => session.expires_at = 0L
        None => ()
      }
      ctx.text(200, "expired")
    })
  let login = app.respond({
    method: "GET",
    path: "/login",
    headers: Map([]),
    body: "",
  })
  assert_eq(login.status, 200)
  assert_eq(store.count(), 1)
  let cookie = session_test_cookie_pair(
    login.headers.get("Set-Cookie").unwrap(),
  )
  let expired = app.respond({
    method: "GET",
    path: "/expire",
    headers: Map([("Cookie", cookie)]),
    body: "",
  })
  assert_eq(expired.status, 200)
  assert_eq(expired.body, "expired")
  assert_eq(store.count(), 0)
  let cleared = expired.headers.get("Set-Cookie").unwrap_or("")
  assert_true(cleared.has_prefix("feather_session=;"))
  assert_true(cleared.contains("Max-Age=0"))
}

///|
test "a fresh session that expires during its first request sends no cookie" {
  let store = @feather.SessionStore::new(ttl=600_000L)
  let app = @feather.App::new()
    .use(@feather.middleware_session(store))
    .get("/first", fn(ctx) {
      ignore(ctx.session_set("key", "value"))
      match ctx.session() {
        Some(session) => session.expires_at = 0L
        None => ()
      }
      ctx.text(200, "done")
    })
  let response = app.respond({
    method: "GET",
    path: "/first",
    headers: Map([]),
    body: "",
  })
  assert_eq(response.status, 200)
  assert_eq(store.count(), 0)
  assert_eq(response.headers.get("Set-Cookie"), None)
}
