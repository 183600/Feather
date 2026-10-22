///|
fn destroyed_helper_request() -> @feather.Request {
  { method: "GET", path: "/destroy", headers: Map([]), body: "", }
}

///|
test "destroyed sessions refuse remove clear and csrf rotation" {
  let store = @feather.SessionStore::new()
  let app = @feather.App::new()
    .use(@feather.middleware_session(store))
    .get("/destroy", fn(ctx) {
      ignore(ctx.session_set("key", "value"))
      ignore(ctx.csrf_token())
      assert_true(ctx.session_destroy())
      let removed = ctx.session_remove("key")
      let cleared = ctx.session_clear()
      let rotated = ctx.csrf_rotate()
      ctx.text(
        200,
        removed.to_string() +
        "|" +
        cleared.to_string() +
        "|" +
        rotated.to_string(),
      )
    })
  let response = app.respond(destroyed_helper_request())
  assert_eq(response.status, 200)
  assert_eq(response.body, "false|false|false")
  assert_eq(store.count(), 0)
}

///|
test "destroyed sessions refuse to drain queued flash messages" {
  let store = @feather.SessionStore::new()
  let app = @feather.App::new()
    .use(@feather.middleware_session(store))
    .get("/destroy", fn(ctx) {
      assert_true(ctx.flash("queued"))
      assert_true(ctx.session_destroy())
      let taken = ctx.flash_take()
      let all = ctx.flash_take_all()
      ctx.text(
        200,
        taken.length().to_string() + "|" + all.length().to_string(),
      )
    })
  let response = app.respond(destroyed_helper_request())
  assert_eq(response.status, 200)
  assert_eq(response.body, "0|0")
  assert_eq(store.count(), 0)
}

///|
test "destroyed sessions do not expose or mint a session id" {
  let store = @feather.SessionStore::new()
  let app = @feather.App::new()
    .use(@feather.middleware_session(store))
    .get("/destroy", fn(ctx) {
      let old_id = ctx.session_id()
      assert_true(ctx.session_destroy())
      assert_eq(ctx.session_id(), None)
      assert_eq(ctx.session().unwrap().id, old_id.unwrap())
      ctx.text(200, old_id.unwrap())
    })
  let first = app.respond(destroyed_helper_request())
  assert_eq(first.status, 200)
  assert_eq(first.cookies.length(), 0)
  assert_eq(store.count(), 0)

  let session = store.create()
  store.save(session)
  let existing = @feather.App::new()
    .use(@feather.middleware_session(store))
    .get("/destroy", fn(ctx) {
      assert_true(ctx.session_destroy())
      assert_eq(ctx.session_id(), None)
      ctx.text(200, "bye")
    })
  let response = existing.respond({
    method: "GET",
    path: "/destroy",
    headers: Map([("Cookie", "feather_session=" + session.id)]),
    body: "",
  })
  assert_eq(response.status, 200)
  assert_eq(response.cookies.length(), 1)
  assert_eq(response.cookies[0].value, "")
  assert_eq(store.count(), 0)
}
