///|
fn destroyed_session_request(cookie : String) -> @feather.Request {
  {
    method: "GET",
    path: "/destroy",
    headers: if cookie == "" {
      Map([])
    } else {
      Map([("Cookie", cookie)])
    },
    body: "",
  }
}

///|
test "destroyed sessions refuse flash csrf touch and regeneration" {
  let store = @feather.SessionStore::new()
  let app = @feather.App::new()
    .use(@feather.middleware_session(store))
    .get("/destroy", fn(ctx) {
      ignore(ctx.session_set("user", "alice"))
      assert_true(ctx.session_destroy())
      let flash_ok = ctx.flash("lost")
      let token_empty = ctx.csrf_token() == ""
      let touched = ctx.session_touch()
      let regenerated = ctx.session_regenerate()
      ctx.text(
        200,
        flash_ok.to_string() +
        "|" +
        token_empty.to_string() +
        "|" +
        touched.to_string() +
        "|" +
        regenerated.to_string(),
      )
    })
  let response = app.respond(destroyed_session_request(""))
  assert_eq(response.status, 200)
  assert_eq(response.body, "false|true|false|false")
  assert_eq(store.count(), 0)
}

///|
test "destroyed existing sessions still clear their cookie" {
  let store = @feather.SessionStore::new()
  let app = @feather.App::new()
    .use(@feather.middleware_session(store))
    .get("/destroy", fn(ctx) {
      assert_true(ctx.session_destroy())
      assert_false(ctx.flash("lost"))
      assert_eq(ctx.csrf_token(), "")
      ctx.text(200, "bye")
    })
  let session = store.create()
  store.save(session)
  let response = app.respond(
    destroyed_session_request("feather_session=" + session.id),
  )
  assert_eq(response.status, 200)
  assert_eq(response.cookies.length(), 1)
  assert_eq(response.cookies[0].value, "")
  assert_eq(response.cookies[0].max_age, Some(0L))
}
