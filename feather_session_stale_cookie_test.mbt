///|
fn stale_session_request(
  path : String,
  cookie? : String,
) -> @feather.Request {
  let headers = match cookie {
    Some(value) => Map([("Cookie", "feather_session=" + value)])
    None => Map([])
  }
  { method: "GET", path, headers, body: "", }
}

///|
fn clearing_session_cookie(
  response : @feather.Response,
) -> @http.Cookie raise {
  assert_eq(response.cookies.length(), 1)
  let cookie = response.cookies[0]
  assert_eq(cookie.name, "feather_session")
  assert_eq(cookie.value, "")
  assert_eq(cookie.max_age, Some(0L))
  cookie
}

///|
test "session middleware clears an unknown cookie without a session write" {
  let store = @feather.SessionStore::new()
  let app = @feather.App::new()
    .use(@feather.middleware_session(store))
    .get("/me", fn(ctx) { ctx.text(200, "ok") })

  let response = app.respond(
    stale_session_request("/me", cookie="unknown-session-id"),
  )
  assert_eq(response.status, 200)
  assert_eq(response.body, "ok")
  ignore(clearing_session_cookie(response))
  assert_eq(store.count(), 0)
}

///|
test "session middleware clears an expired stored session" {
  let store = @feather.SessionStore::new()
  let app = @feather.App::new()
    .use(@feather.middleware_session(store))
    .get("/login", fn(ctx) {
      ignore(ctx.session_set("user", "alice"))
      ctx.text(200, "login")
    })
    .get("/me", fn(ctx) { ctx.text(200, "ok") })

  let login = app.respond(stale_session_request("/login"))
  let id = login.cookies[0].value
  let stored = store.get(id).unwrap()
  stored.expires_at = 0L

  let response = app.respond(stale_session_request("/me", cookie=id))
  assert_eq(response.status, 200)
  ignore(clearing_session_cookie(response))
  assert_eq(store.count(), 0)
}

///|
test "session middleware clears a stale cookie after a read-only session access" {
  let store = @feather.SessionStore::new()
  let app = @feather.App::new()
    .use(@feather.middleware_session(store))
    .get("/peek", fn(ctx) {
      ignore(ctx.session())
      ctx.text(200, "peek")
    })

  let response = app.respond(
    stale_session_request("/peek", cookie="another-unknown-id"),
  )
  assert_eq(response.status, 200)
  ignore(clearing_session_cookie(response))
  assert_eq(store.count(), 0)
}

///|
test "session middleware keeps a live cookie on a read-only request" {
  let store = @feather.SessionStore::new()
  let app = @feather.App::new()
    .use(@feather.middleware_session(store))
    .get("/login", fn(ctx) {
      ignore(ctx.session_set("user", "alice"))
      ctx.text(200, "login")
    })
    .get("/me", fn(ctx) { ctx.text(200, "ok") })

  let login = app.respond(stale_session_request("/login"))
  let id = login.cookies[0].value
  assert_eq(store.count(), 1)

  let response = app.respond(stale_session_request("/me", cookie=id))
  assert_eq(response.status, 200)
  assert_eq(response.cookies.length(), 0)
  assert_eq(store.count(), 1)
}

///|
test "session middleware sends no cookie when the request has none" {
  let store = @feather.SessionStore::new()
  let app = @feather.App::new()
    .use(@feather.middleware_session(store))
    .get("/me", fn(ctx) { ctx.text(200, "ok") })

  let response = app.respond(stale_session_request("/me"))
  assert_eq(response.status, 200)
  assert_eq(response.cookies.length(), 0)
  assert_eq(store.count(), 0)
}
