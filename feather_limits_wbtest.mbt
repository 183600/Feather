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

///|
test "static lookup negative fifo is compacted" {
  let app = App::new().static_files("/assets", "/tmp/feather-static-wbtest")
  let total = STATIC_LOOKUP_CACHE_LIMIT * 3
  for i = 0; i < total; i = i + 1 {
    ignore(app.static_file_for("/assets/%2e%2e/escape-" + i.to_string()))
  }
  let queued = app.static_lookup_negative
  assert_true(queued.length() <= STATIC_LOOKUP_CACHE_LIMIT * 2)
  assert_true(app.static_lookup_negative_head <= queued.length())
}

///|
test "rate limiter sweeps expired buckets before evicting live ones" {
  let limiter = RateLimiter::new(max=1, window=60_000L)
  for i = 0; i < RATE_LIMIT_MAX_BUCKETS; i = i + 1 {
    ignore(limiter.allow("key-" + i.to_string()))
  }
  assert_eq(limiter.count(), RATE_LIMIT_MAX_BUCKETS)
  let live_key = "live-key"
  ignore(limiter.allow(live_key))
  for key, bucket in limiter.buckets {
    if key != live_key {
      bucket.start = 0L
    }
  }
  ignore(limiter.allow("fresh-key"))
  assert_eq(limiter.count(), 2)
  assert_eq(limiter.remaining(live_key), 0)
  assert_eq(limiter.remaining("fresh-key"), 0)
}
