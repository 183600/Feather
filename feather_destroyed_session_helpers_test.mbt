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
