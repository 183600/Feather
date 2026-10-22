///|
test "saving a destroyed session does not resurrect it" {
  let store = @feather.SessionStore::new()
  let session = store.create()
  store.save(session)
  assert_eq(store.count(), 1)
  session.destroyed = true
  store.save(session)
  assert_eq(store.count(), 0)
  assert_true(store.get(session.id) is None)
}
