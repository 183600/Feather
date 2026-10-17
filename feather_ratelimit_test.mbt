///|
test "rate limiter allows up to the limit then rejects" {
  let limiter = @feather.RateLimiter::new(max=2, window=60_000L)
  assert_eq(limiter.max(), 2)
  assert_eq(limiter.window(), 60_000L)
  assert_eq(limiter.remaining("client"), 2)
  assert_true(limiter.allow("client"))
  assert_eq(limiter.remaining("client"), 1)
  assert_true(limiter.allow("client"))
  assert_eq(limiter.remaining("client"), 0)
  assert_false(limiter.allow("client"))
  assert_eq(limiter.retry_after("client") > 0L, true)
}

///|
test "rate limiter isolates keys" {
  let limiter = @feather.RateLimiter::new(max=1, window=60_000L)
  assert_true(limiter.allow("alice"))
  assert_false(limiter.allow("alice"))
  assert_true(limiter.allow("bob"))
  assert_eq(limiter.count(), 2)
}

///|
test "rate limiter clamps invalid configuration" {
  let limiter = @feather.RateLimiter::new(max=0, window=0L)
  assert_eq(limiter.max(), 1)
  assert_eq(limiter.window(), 1L)
  assert_eq(limiter.retry_after("unknown"), 0L)
  assert_eq(limiter.remaining("unknown"), 1)
}

///|
async test "rate limiter resets after the window" {
  let limiter = @feather.RateLimiter::new(max=1, window=50L)
  assert_true(limiter.allow("client"))
  assert_false(limiter.allow("client"))
  assert_true(limiter.retry_after("client") > 0L)
  @async.sleep(60)
  assert_eq(limiter.retry_after("client"), 0L)
  assert_true(limiter.allow("client"))
  assert_false(limiter.allow("client"))
}

///|
async test "rate limiter sweeps stale buckets" {
  let limiter = @feather.RateLimiter::new(max=1, window=20L)
  ignore(limiter.allow("a"))
  ignore(limiter.allow("b"))
  assert_eq(limiter.count(), 2)
  @async.sleep(30)
  limiter.sweep()
  assert_eq(limiter.count(), 0)
}

///|
test "rate limit middleware throttles per key" {
  let limiter = @feather.RateLimiter::new(max=1, window=60_000L)
  let app = @feather.App::new()
    .use(
      @feather.middleware_rate_limit(limiter, key=fn(ctx) {
        ctx.header("X-Api-Key")
      }),
    )
    .get("/api", fn(ctx) { ctx.text(200, "ok") })
  let alice = Map([("X-Api-Key", "alice")])
  let first = app.respond({
    method: "GET",
    path: "/api",
    headers: alice,
    body: "",
  })
  assert_eq(first.status, 200)
  assert_eq(first.body, "ok")
  assert_eq(first.headers.get("X-RateLimit-Limit"), Some("1"))
  assert_eq(first.headers.get("X-RateLimit-Remaining"), Some("0"))
  let second = app.respond({
    method: "GET",
    path: "/api",
    headers: alice,
    body: "",
  })
  assert_eq(second.status, 429)
  assert_eq(second.body, "429 Too Many Requests")
  assert_eq(second.headers.get("Retry-After"), Some("60"))
  let bob = app.respond({
    method: "GET",
    path: "/api",
    headers: Map([("X-Api-Key", "bob")]),
    body: "",
  })
  assert_eq(bob.status, 200)
  assert_eq(limiter.count(), 2)
}

///|
test "rate limit middleware defaults to the client address" {
  let limiter = @feather.RateLimiter::new(max=1, window=60_000L)
  let handler = @feather.apply_middleware(
    [@feather.middleware_rate_limit(limiter)],
    fn(ctx) { ctx.text(200, "ok") },
  )
  let first = @feather.create_context()
  first.state.set("remote_addr", "10.0.0.1")
  handler(first)
  assert_eq(first.response.status, 200)
  let second = @feather.create_context()
  second.state.set("remote_addr", "10.0.0.1")
  handler(second)
  assert_eq(second.response.status, 429)
  let other = @feather.create_context()
  other.state.set("remote_addr", "10.0.0.2")
  handler(other)
  assert_eq(other.response.status, 200)
}
