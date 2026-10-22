///|
test "session_touch requires an attached session" {
  let ctx = @feather.create_context()
  assert_false(ctx.session_touch())
}

///|
test "session_touch extends an attached session and marks it modified" {
  let ctx = @feather.create_context()
  let store = @feather.SessionStore::new(ttl=600_000L)
  let session = store.create()
  session.expires_at = 1L
  session.modified = false
  ctx.session = Some(session)
  assert_true(ctx.session_touch())
  assert_true(session.modified)
  assert_true(session.expires_at > 1L)
}

///|
fn rolling_request(path : String, cookie? : String) -> @feather.Request {
  let headers : Map[String, String] = Map([])
  match cookie {
    Some(value) => headers.set("Cookie", "feather_session=" + value)
    None => ()
  }
  { method: "GET", path, headers, body: "", }
}

///|
test "rolling sessions refresh the store and cookie on a read-only request" {
  let store = @feather.SessionStore::new(ttl=600_000L)
  let app = @feather.App::new()
    .use(@feather.middleware_session(store, rolling=true))
    .get("/seed", fn(ctx) {
      ignore(ctx.session_set("user", "alice"))
      ctx.text(200, "seeded")
    })
    .get("/read", fn(ctx) { ctx.text(200, "read") })
  let seeded = app.respond(rolling_request("/seed"))
  let id = seeded.cookies[0].value
  let before = match store.get(id) {
    Some(session) => {
      session.expires_at = @async.now() + 1000L
      session.modified = false
      session.expires_at
    }
    None => fail("expected the seeded session in the store")
  }
  let read = app.respond(rolling_request("/read", cookie=id))
  assert_eq(read.status, 200)
  assert_eq(read.cookies.length(), 1)
  assert_eq(read.cookies[0].value, id)
  match store.get(id) {
    Some(session) => assert_true(session.expires_at > before)
    None => fail("expected the rolling session to stay in the store")
  }
}

///|
test "sessions keep a fixed lifetime unless rolling is enabled" {
  let store = @feather.SessionStore::new(ttl=600_000L)
  let app = @feather.App::new()
    .use(@feather.middleware_session(store))
    .get("/seed", fn(ctx) {
      ignore(ctx.session_set("user", "alice"))
      ctx.text(200, "seeded")
    })
    .get("/read", fn(ctx) { ctx.text(200, "read") })
  let seeded = app.respond(rolling_request("/seed"))
  let id = seeded.cookies[0].value
  let before = match store.get(id) {
    Some(session) => {
      session.expires_at = @async.now() + 1000L
      session.expires_at
    }
    None => fail("expected the seeded session in the store")
  }
  let read = app.respond(rolling_request("/read", cookie=id))
  assert_eq(read.status, 200)
  assert_eq(read.cookies.length(), 0)
  match store.get(id) {
    Some(session) => assert_eq(session.expires_at, before)
    None => fail("expected the fixed-lifetime session in the store")
  }
}

///|
test "session_touch persists a new deadline from a handler" {
  let store = @feather.SessionStore::new(ttl=600_000L)
  let app = @feather.App::new()
    .use(@feather.middleware_session(store))
    .get("/seed", fn(ctx) {
      ignore(ctx.session_set("user", "alice"))
      ctx.text(200, "seeded")
    })
    .get("/extend", fn(ctx) {
      assert_true(ctx.session_touch())
      ctx.text(200, "extended")
    })
  let seeded = app.respond(rolling_request("/seed"))
  let id = seeded.cookies[0].value
  let before = match store.get(id) {
    Some(session) => {
      session.expires_at = @async.now() + 1000L
      session.expires_at
    }
    None => fail("expected the seeded session in the store")
  }
  let extended = app.respond(rolling_request("/extend", cookie=id))
  assert_eq(extended.status, 200)
  assert_eq(extended.cookies.length(), 1)
  match store.get(id) {
    Some(session) => assert_true(session.expires_at > before)
    None => fail("expected the touched session to stay in the store")
  }
}
