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
