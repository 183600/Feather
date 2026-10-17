///|
/// Per-key fixed-window counters for a `RateLimiter`.
struct RateBucket {
  mut start : Int64
  mut count : Int
}

///|
/// How often stale buckets are collected when new keys appear.
const RATE_LIMIT_SWEEP_INTERVAL : Int64 = 60_000L

///|
/// A bounded in-memory fixed-window rate limiter.
///
/// Each key gets a window of `window` milliseconds that allows at most `max`
/// requests; once the window elapses the counter resets. Buckets for keys that
/// have been idle for a full window are swept periodically so long-running
/// servers do not grow without bound. All state is per process, which is the
/// right default for a single server; share a store through another mechanism
/// when running several instances.
pub struct RateLimiter {
  max : Int
  window : Int64
  buckets : Map[String, RateBucket]
  mut last_sweep : Int64
}

///|
/// Create a limiter allowing `max` requests per `window` milliseconds for each
/// key.
pub fn RateLimiter::new(
  max~ : Int,
  window~ : Int64 = 60_000L,
) -> RateLimiter {
  {
    max: if max < 1 { 1 } else { max },
    window: if window < 1L { 1L } else { window },
    buckets: Map([]),
    last_sweep: 0L,
  }
}

///|
/// The per-key request allowance.
pub fn RateLimiter::max(self : RateLimiter) -> Int {
  self.max
}

///|
/// The window length in milliseconds.
pub fn RateLimiter::window(self : RateLimiter) -> Int64 {
  self.window
}

///|
/// Record a request for `key` and report whether it fits in the current
/// window. The first request for a key always fits.
pub fn RateLimiter::allow(self : RateLimiter, key : String) -> Bool {
  let now = @async.now()
  match self.buckets.get(key) {
    Some(bucket) =>
      if now - bucket.start >= self.window {
        bucket.start = now
        bucket.count = 1
        true
      } else if bucket.count < self.max {
        bucket.count = bucket.count + 1
        true
      } else {
        false
      }
    None => {
      self.maybe_sweep(now)
      self.buckets.set(key, { start: now, count: 1 })
      true
    }
  }
}

///|
/// Requests still allowed for `key` in the current window. Reports the full
/// allowance when the key has no live window.
pub fn RateLimiter::remaining(self : RateLimiter, key : String) -> Int {
  match self.buckets.get(key) {
    Some(bucket) =>
      if @async.now() - bucket.start >= self.window {
        self.max
      } else if bucket.count >= self.max {
        0
      } else {
        self.max - bucket.count
      }
    None => self.max
  }
}

///|
/// Milliseconds until `key` may send requests again; `0L` when a request would
/// be allowed right now.
pub fn RateLimiter::retry_after(self : RateLimiter, key : String) -> Int64 {
  match self.buckets.get(key) {
    Some(bucket) =>
      if bucket.count < self.max {
        0L
      } else {
        let elapsed = @async.now() - bucket.start
        if elapsed >= self.window {
          0L
        } else {
          self.window - elapsed
        }
      }
    None => 0L
  }
}

///|
/// Number of keys with a bucket in the limiter.
pub fn RateLimiter::count(self : RateLimiter) -> Int {
  self.buckets.length()
}

///|
/// Drop every bucket whose window has fully elapsed.
pub fn RateLimiter::sweep(self : RateLimiter) -> Unit {
  let now = @async.now()
  self.last_sweep = now
  let stale : Array[String] = []
  for key, bucket in self.buckets {
    if now - bucket.start >= self.window {
      stale.push(key)
    }
  }
  for key in stale {
    ignore(self.buckets.remove(key))
  }
}

///|
fn RateLimiter::maybe_sweep(self : RateLimiter, now : Int64) -> Unit {
  if self.last_sweep == 0L || now - self.last_sweep >= RATE_LIMIT_SWEEP_INTERVAL {
    self.sweep()
  }
}

///|
/// Middleware that throttles requests per key, by default per client IP.
///
/// Each key may make `RateLimiter::new`'s allowance of requests per window;
/// requests over the limit are answered with `429 Too Many Requests` and a
/// `Retry-After` header (whole seconds, rounded up) without reaching the
/// handler. Accepted responses carry `X-RateLimit-Limit` and
/// `X-RateLimit-Remaining` headers. Pass `key` to throttle by something else,
/// such as a session id or an API token.
pub fn middleware_rate_limit(
  limiter : RateLimiter,
  key~ : (Context) -> String = fn(ctx) { ctx.ip() },
) -> Middleware {
  fn(next) {
    fn(ctx) raise {
      let bucket_key = key(ctx)
      if limiter.allow(bucket_key) {
        ctx.set_header("X-RateLimit-Limit", limiter.max().to_string())
        ctx.set_header(
          "X-RateLimit-Remaining",
          limiter.remaining(bucket_key).to_string(),
        )
        next(ctx)
      } else {
        let millis = limiter.retry_after(bucket_key)
        let seconds = millis / 1000L + (if millis % 1000L == 0L { 0L } else { 1L })
        ctx.set_header("Retry-After", seconds.to_string())
        ctx.text(429, "429 Too Many Requests")
      }
    }
  }
}
