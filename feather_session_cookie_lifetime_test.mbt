///|
/// Build a request carrying the session cookie pair from a prior response.
fn session_cookie_lifetime_request(path : String, cookie : String) -> @feather.Request {
  {
    method: "GET",
    path,
    headers: Map([("Cookie", "feather_session=" + cookie)]),
    body: "",
  }
}

///|
test "writing a fixed-lifetime session advertises only its remaining lifetime" {
  let store = @feather.SessionStore::new(ttl=600_000L)
  let app = @feather.App::new()
    .use(@feather.middleware_session(store))
    .get("/seed", fn(ctx) {
      ignore(ctx.session_set("user", "alice"))
      ctx.text(200, "seeded")
    })
    .get("/write", fn(ctx) {
      ignore(ctx.session_set("user", "bob"))
      ctx.text(200, "written")
    })
  let seeded = app.respond({
    method: "GET",
    path: "/seed",
    headers: Map([]),
    body: "",
  })
  let id = seeded.cookies[0].value
  let deadline = @async.now() + 5_000L
  match store.get(id) {
    Some(session) => {
      session.expires_at = deadline
      session.modified = false
    }
    None => fail("expected the seeded session in the store")
  }
  let written = app.respond(
    session_cookie_lifetime_request("/write", id),
  )
  assert_eq(written.status, 200)
  assert_eq(written.cookies.length(), 1)
  let remaining = match written.cookies[0].max_age {
    Some(seconds) => seconds
    None => fail("expected the re-sent session cookie to keep a Max-Age")
  }
  // The server deadline is unchanged, so the browser must not be told the
  // session has another full ten minutes to live.
  assert_true(remaining > 0L, msg=remaining.to_string())
  assert_true(remaining <= 5L, msg=remaining.to_string())
  match store.get(id) {
    Some(session) => assert_eq(session.expires_at, deadline)
    None => fail("expected the fixed-lifetime session in the store")
  }
}
