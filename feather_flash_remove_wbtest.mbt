///|
test "removing a pending-only flash key discards queued messages" {
  let ctx = Context::new({
    method: "GET",
    path: "/",
    headers: Map([]),
    body: "",
  })
  let store = SessionStore::new()
  ctx.session = Some(store.create())
  assert_true(ctx.flash("queued"))
  // The category has not been written to `data` yet, but the queued message is
  // still part of this request and must not survive an explicit removal.
  assert_eq(ctx.session_get(FLASH_PREFIX + "default"), "")
  assert_true(ctx.session_remove(FLASH_PREFIX + "default"))
  assert_eq(ctx.flash_take(), [])
  let session = ctx.session.unwrap()
  assert_eq(session.flash_pending_bytes, 0)
  session.flush_flash()
  assert_eq(session.data.get(FLASH_PREFIX + "default"), None)
}

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
