///|
test "removing a flash key discards pending flash additions" {
  let ctx = Context::new({
    method: "GET",
    path: "/",
    headers: Map([]),
    body: "",
  })
  let store = SessionStore::new()
  let session = store.create()
  session.data.set(FLASH_PREFIX + "default", "[\"old\"]")
  ctx.session = Some(session)
  assert_true(ctx.flash("new"))
  assert_true(ctx.session_remove(FLASH_PREFIX + "default"))
  session.flush_flash()
  assert_eq(session.data.get(FLASH_PREFIX + "default"), None)
  assert_eq(session.flash_pending_bytes, 0)
}
