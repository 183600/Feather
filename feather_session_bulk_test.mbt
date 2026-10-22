///|
fn bulk_session_request(path : String, cookie? : String) -> @feather.Request {
  let headers : Map[String, String] = Map([])
  match cookie {
    Some(value) => headers.set("Cookie", value)
    None => ()
  }
  { method: "GET", path, headers, body: "", }
}

///|
test "session bulk helpers are inert without middleware" {
  let ctx = @feather.create_context()
  assert_false(ctx.session_has("missing"))
  assert_eq(ctx.session_keys().length(), 0)
  assert_false(ctx.session_clear())
}

///|
test "session bulk helpers inspect and clear attached sessions" {
  let store = @feather.SessionStore::new()
  let ctx = @feather.create_context()
  ctx.session = Some(store.create())
  assert_true(ctx.session_set("user", "alice"))
  assert_true(ctx.session_set("empty", ""))
  assert_true(ctx.session_has("user"))
  assert_true(ctx.session_has("empty"))
  assert_false(ctx.session_has("absent"))
  let keys = ctx.session_keys()
  assert_eq(keys.length(), 2)
  assert_true(keys.contains("user"))
  assert_true(keys.contains("empty"))
  assert_true(ctx.flash("queued"))
  assert_true(ctx.session_clear())
  assert_false(ctx.session_has("user"))
  assert_false(ctx.session_has("empty"))
  assert_eq(ctx.session_get("user"), "")
  assert_eq(ctx.session_keys().length(), 0)
  assert_true(ctx.session() is Some(_))
  assert_true(ctx.session().unwrap().flash_pending is None)
  assert_true(ctx.session_clear())
}

///|
test "session_clear persists an empty session and drops flash messages" {
  let store = @feather.SessionStore::new()
  let app = @feather.App::new()
    .use(@feather.middleware_session(store))
    .get("/seed", fn(ctx) {
      ignore(ctx.session_set("user", "alice"))
      ignore(ctx.session_set("cart", "1"))
      ctx.text(200, "seeded")
    })
    .get("/clear", fn(ctx) {
      assert_true(ctx.flash("queued"))
      assert_true(ctx.session_clear())
      assert_eq(ctx.session_keys().length(), 0)
      ctx.text(200, "cleared")
    })
    .get("/keys", fn(ctx) {
      ctx.text(200, ctx.session_keys().length().to_string())
    })
  let seeded = app.respond(bulk_session_request("/seed"))
  assert_eq(seeded.cookies.length(), 1)
  let id = seeded.cookies[0].value
  let cleared = app.respond(
    bulk_session_request("/clear", cookie="feather_session=" + id),
  )
  assert_eq(cleared.status, 200)
  assert_eq(cleared.cookies.length(), 1)
  assert_eq(cleared.cookies[0].value, id)
  match store.get(id) {
    Some(session) => {
      assert_true(session.data.is_empty())
      assert_eq(session.flash_pending, None)
    }
    None => fail("expected cleared session to remain in the store")
  }
  let inspected = app.respond(
    bulk_session_request("/keys", cookie="feather_session=" + id),
  )
  assert_eq(inspected.status, 200)
  assert_eq(inspected.body, "0")
  assert_eq(inspected.cookies.length(), 0)
}
