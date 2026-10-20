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
/// Hard upper bound on retained buckets. When the map is full and nothing has
/// expired yet, an arbitrary bucket is dropped so attacker chosen keys cannot
/// grow the limiter without bound.
const RATE_LIMIT_MAX_BUCKETS : Int = 4096

///|
/// A bounded in-memory fixed-window rate limiter.
///
/// Each key gets a window of `window` milliseconds that allows at most `max`
/// requests; once the window elapses the counter resets. Buckets for keys that
/// have been idle for a full window are swept periodically, and the map is
/// capped at `RATE_LIMIT_MAX_BUCKETS` entries so long-running servers do not
/// grow without bound. All state is per process, which is the right default
/// for a single server; share a store through another mechanism when running
/// several instances.
pub struct RateLimiter {
  max : Int
  window : Int64
  buckets : Map[String, RateBucket]
  mut last_sweep : Int64
  mut last_key : String
  mut last_bucket : RateBucket?
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
    last_key: "",
    last_bucket: None,
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
/// window, together with the remaining allowance.
fn RateLimiter::allow_with_remaining(
  self : RateLimiter,
  key : String,
) -> (Bool, Int) {
  let now = @async.now()
  let bucket = match self.last_bucket {
    Some(bucket) if self.last_key == key => Some(bucket)
    _ =>
      match self.buckets.get(key) {
        Some(bucket) => {
          self.last_key = key
          self.last_bucket = Some(bucket)
          Some(bucket)
        }
        None => None
      }
  }
  match bucket {
    Some(bucket) =>
      if now - bucket.start >= self.window {
        bucket.start = now
        bucket.count = 1
        (true, self.max - 1)
      } else if bucket.count < self.max {
        bucket.count = bucket.count + 1
        (true, self.max - bucket.count)
      } else {
        (false, 0)
      }
    None => {
      self.maybe_sweep(now)
      if self.buckets.length() >= RATE_LIMIT_MAX_BUCKETS {
        self.evict_one()
      }
      let bucket = { start: now, count: 1 }
      self.buckets.set(key, bucket)
      self.last_key = key
      self.last_bucket = Some(bucket)
      (true, self.max - 1)
    }
  }
}

///|
/// Record a request for `key` and report whether it fits in the current
/// window. The first request for a key always fits.
pub fn RateLimiter::allow(self : RateLimiter, key : String) -> Bool {
  let (allowed, _) = self.allow_with_remaining(key)
  allowed
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
/// Forget `key`'s window so its next request starts from a full allowance.
/// Returns whether a bucket existed. Useful when a client identifies itself
/// (for example after a successful login) and should not inherit throttling
/// earned before that.
pub fn RateLimiter::reset(self : RateLimiter, key : String) -> Bool {
  let existed = self.buckets.contains(key)
  self.buckets.remove(key)
  if self.last_key == key {
    self.last_key = ""
    self.last_bucket = None
  }
  existed
}

///|
/// Drop every bucket whose window has fully elapsed.
pub fn RateLimiter::sweep(self : RateLimiter) -> Unit {
  if self.buckets.is_empty() {
    self.last_sweep = @async.now()
    return
  }
  let now = @async.now()
  self.last_sweep = now
  self.buckets.retain(fn(_key, bucket) {
    now - bucket.start < self.window
  })
  self.last_key = ""
  self.last_bucket = None
}

///|
/// Drop one arbitrary bucket, keeping the limiter under `RATE_LIMIT_MAX_BUCKETS`
/// when no bucket has expired yet. The map is a bounded cache of windows.
fn RateLimiter::evict_one(self : RateLimiter) -> Unit {
  match self.buckets.keys().next() {
    Some(key) => {
      ignore(self.buckets.remove(key))
      if self.last_key == key {
        self.last_key = ""
        self.last_bucket = None
      }
    }
    None => ()
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
/// requests over the limit are answered with `429 Too Many Requests`, a
/// `Retry-After` header (whole seconds, rounded up) and the remaining count,
/// without reaching the handler. Every response carries `X-RateLimit-Limit`
/// and `X-RateLimit-Remaining` headers. Pass `key` to throttle by something
/// else, such as a session id or an API token.
pub fn middleware_rate_limit(
  limiter : RateLimiter,
  key~ : (Context) -> String = fn(ctx) { ctx.ip() },
) -> Middleware {
  let max_string = limiter.max().to_string()
  fn(next) {
    fn(ctx) raise {
      let bucket_key = key(ctx)
      let (allowed, remaining) = limiter.allow_with_remaining(bucket_key)
      if allowed {
        ctx.set_header("X-RateLimit-Limit", max_string)
        ctx.set_header("X-RateLimit-Remaining", remaining.to_string())
        next(ctx)
      } else {
        let millis = limiter.retry_after(bucket_key)
        let seconds = millis / 1000L + (if millis % 1000L == 0L { 0L } else { 1L })
        ctx.set_header("Retry-After", seconds.to_string())
        ctx.set_header("X-RateLimit-Limit", max_string)
        ctx.set_header("X-RateLimit-Remaining", "0")
        ctx.text(429, "429 Too Many Requests")
      }
    }
  }
}
