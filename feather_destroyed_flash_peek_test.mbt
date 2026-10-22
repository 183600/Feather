///|
test "flash_peek of a destroyed session reports no surviving messages" {
  let store = @feather.SessionStore::new()
  let ctx = @feather.create_context()
  ctx.session = Some(store.create())
  assert_true(ctx.flash("queued"))
  assert_true(ctx.session_destroy())
  assert_eq(ctx.flash_peek(), [])
  assert_eq(ctx.flash_peek(category="missing"), [])
}
