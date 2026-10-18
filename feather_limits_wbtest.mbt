///|
test "rate limiter caps the number of retained buckets" {
  let limiter = RateLimiter::new(max=1, window=60_000L)
  let total = RATE_LIMIT_MAX_BUCKETS + 50
  for i = 0; i < total; i = i + 1 {
    ignore(limiter.allow("key-" + i.to_string()))
  }
  assert_eq(limiter.count(), RATE_LIMIT_MAX_BUCKETS)
}

///|
test "session store caps the number of retained sessions" {
  let store = SessionStore::new()
  let total = SESSION_STORE_MAX_SESSIONS + 50
  for i = 0; i < total; i = i + 1 {
    store.save(store.create())
  }
  assert_eq(store.count(), SESSION_STORE_MAX_SESSIONS)
}
