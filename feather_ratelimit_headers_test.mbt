///|
test "rate limiter reports the time until the window resets" {
  let limiter = @feather.RateLimiter::new(max=2, window=60_000L)
  assert_eq(limiter.reset_after("client"), 0L)
  assert_true(limiter.allow("client"))
  let reset = limiter.reset_after("client")
  assert_true(reset > 0L)
  assert_true(reset <= 60_000L)
  // Reset time is independent of the remaining allowance.
  assert_true(limiter.allow("client"))
  assert_true(limiter.reset_after("client") > 0L)
}

///|
test "rate limit middleware sends standard and legacy headers" {
  let limiter = @feather.RateLimiter::new(max=2, window=60_000L)
  let app = @feather.App::new()
    .use(
      @feather.middleware_rate_limit(limiter, key=fn(ctx) {
        ctx.header("X-Api-Key")
      }),
    )
    .get("/api", fn(ctx) { ctx.text(200, "ok") })
  let headers = Map([("X-Api-Key", "alice")])
  let first = app.respond({
    method: "GET",
    path: "/api",
    headers,
    body: "",
  })
  assert_eq(first.status, 200)
  assert_eq(first.headers.get("RateLimit-Limit"), Some("2"))
  assert_eq(first.headers.get("RateLimit-Remaining"), Some("1"))
  assert_eq(first.headers.get("RateLimit-Reset"), Some("60"))
  assert_eq(first.headers.get("X-RateLimit-Limit"), Some("2"))
  assert_eq(first.headers.get("X-RateLimit-Remaining"), Some("1"))

  let second = app.respond({
    method: "GET",
    path: "/api",
    headers,
    body: "",
  })
  assert_eq(second.status, 200)
  assert_eq(second.headers.get("RateLimit-Remaining"), Some("0"))
  assert_eq(second.headers.get("RateLimit-Reset"), Some("60"))

  let third = app.respond({
    method: "GET",
    path: "/api",
    headers,
    body: "",
  })
  assert_eq(third.status, 429)
  assert_eq(third.headers.get("Retry-After"), Some("60"))
  assert_eq(third.headers.get("RateLimit-Limit"), Some("2"))
  assert_eq(third.headers.get("RateLimit-Remaining"), Some("0"))
  assert_eq(third.headers.get("RateLimit-Reset"), Some("60"))
  assert_eq(third.headers.get("X-RateLimit-Remaining"), Some("0"))
}
