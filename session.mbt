///|
/// One server-side session: an opaque id plus string data that persists across
/// requests until the session expires or is destroyed.
///
/// Sessions are attached to a request by `middleware_session`; handlers should
/// treat them through the `Context::session_*` helpers, which keep the
/// `modified` / `destroyed` bookkeeping consistent.
pub(all) struct Session {
  mut id : String
  data : Map[String, String]
  mut expires_at : Int64
  mut modified : Bool
  mut destroyed : Bool
  mut regenerate : Bool
  mut flash_pending : Map[String, Array[String]]?
  mut flash_pending_bytes : Int32
  mut json_cache : Map[String, (String, Json)]?
}

///|
/// Default session lifetime: 24 hours.
pub const DEFAULT_SESSION_TTL : Int64 = 86_400_000L

///|
/// Expiry timestamp for a session created now with `ttl`, clamped so an
/// extreme (but positive) lifetime cannot overflow into the past.
fn session_expiry(now : Int64, ttl : Int64) -> Int64 {
  if ttl > 0L && now > 9223372036854775807L - ttl {
    9223372036854775807L
  } else {
    now + ttl
  }
}

///|
/// How often expired sessions are swept when the store is written to.
const SESSION_SWEEP_INTERVAL : Int64 = 60_000L

///|
/// Hard upper bound on retained sessions. When the store is full and no
/// session has expired yet, an arbitrary session is dropped so
/// unauthenticated traffic cannot grow the store without bound within a TTL
/// window.
const SESSION_STORE_MAX_SESSIONS : Int32 = 10_000

///|
/// In-memory session storage for a single server process.
///
/// New session ids come from a ChaCha8 generator seeded with platform entropy
/// when the host provides it. Expired sessions are dropped when they are read
/// and, at most once a minute, whenever the store is written to; the store is
/// also capped at `SESSION_STORE_MAX_SESSIONS` entries. Call
/// `SessionStore::sweep` to collect expired sessions eagerly.
pub struct SessionStore {
  sessions : Map[String, Session]
  rng : @random.Rand
  ttl : Int64
  mut last_sweep : Int64
}

///|
/// Counter mixed into `time_seed` so generators created within the same
/// millisecond still diverge.
let seed_counter : Ref[Int64] = Ref(0L)

///|
/// Build a 32-byte seed from the current time when no platform entropy is
/// available.
fn time_seed() -> Bytes {
  let out = FixedArray::make(32, b'\x00')
  seed_counter.val = seed_counter.val + 1L
  let mut state = @async.now() + seed_counter.val * 6364136223846793005L
  for i = 0; i < 4; i = i + 1 {
    state = state * 6364136223846793005L + 1442695040888963407L
    let value = state
    for j = 0; j < 8; j = j + 1 {
      out[i * 8 + j] = ((value >> (j * 8)) & 255L).to_int().to_byte()
    }
  }
  out.unsafe_reinterpret_as_bytes()
}

///|
/// ChaCha8 generator seeded from platform entropy when the host provides it.
fn platform_rand() -> @random.Rand {
  match @env.rand(32) {
    Some(seed) => @random.Rand::chacha8(seed~)
    None => @random.Rand::chacha8(seed=time_seed())
  }
}

///|
/// Generator for ids of sessions first written lazily, outside the store's own
/// generator.
let session_id_rng : @random.Rand = platform_rand()

///|
/// Hex digits used by `session_random_id`.
let session_hex_digits : Bytes = b"0123456789abcdef"

///|
/// Render a random 32-character hex id from `rng`.
fn session_random_id(rng : @random.Rand) -> String {
  let out = FixedArray::make(32, b'0')
  for i = 0; i < 2; i = i + 1 {
    let value = rng.uint64()
    for j = 0; j < 16; j = j + 1 {
      let nibble = ((value >> ((15 - j) * 4)) & 15UL).to_int()
      out[i * 16 + j] = session_hex_digits[nibble]
    }
  }
  @utf8.decode_lossy(out.unsafe_reinterpret_as_bytes())
}

///|
/// Create an empty store whose sessions live for `ttl` milliseconds.
pub fn SessionStore::new(ttl~ : Int64 = DEFAULT_SESSION_TTL) -> SessionStore {
  {
    sessions: Map([]),
    rng: platform_rand(),
    ttl: if ttl <= 0L {
      DEFAULT_SESSION_TTL
    } else {
      ttl
    },
    last_sweep: 0L,
  }
}

///|
/// Session lifetime in milliseconds.
pub fn SessionStore::ttl(self : SessionStore) -> Int64 {
  self.ttl
}

///|
fn SessionStore::generate_id(self : SessionStore) -> String {
  session_random_id(self.rng)
}

///|
/// Create a fresh, unsaved session with a random id and empty data.
pub fn SessionStore::create(self : SessionStore) -> Session {
  {
    id: self.generate_id(),
    data: Map([]),
    expires_at: session_expiry(@async.now(), self.ttl),
    modified: false,
    destroyed: false,
    regenerate: false,
    flash_pending: None,
    flash_pending_bytes: 0,
    json_cache: None,
  }
}

///|
/// Create a detached session. Its id and store slot are assigned when the
/// request first writes to the session.
fn session_detached(ttl : Int64) -> Session {
  {
    id: "",
    data: Map([]),
    expires_at: session_expiry(@async.now(), ttl),
    modified: false,
    destroyed: false,
    regenerate: false,
    flash_pending: None,
    flash_pending_bytes: 0,
    json_cache: None,
  }
}

///|
/// State key under which `middleware_session` records the store TTL for a
/// request whose anonymous session has not been materialized yet.
const SESSION_LAZY_KEY : String = "__feather_session_ttl"

///|
/// State key under which the session middleware records its TTL for
/// `Context::session_touch`, including requests that already carry a session.
const SESSION_TTL_STATE_KEY : String = "__feather_session_ttl_ms"

///|
/// State key marking a request whose incoming session cookie named no live
/// session. The middleware clears that stale cookie even when the handler
/// never touches the session, so the browser stops sending an id the store has
/// already dropped.
const SESSION_STALE_COOKIE_KEY : String = "__feather_session_stale"

///|
/// Parse the TTL text recorded under `SESSION_LAZY_KEY`, falling back to the
/// default lifetime for malformed values.
fn session_ttl_from_text(text : String) -> Int64 {
  let mut value = 0L
  for i = 0; i < text.length(); i = i + 1 {
    let code = text[i].to_int()
    if code < 48 || code > 57 {
      return DEFAULT_SESSION_TTL
    }
    let digit = (code - 48).to_int64()
    if value > (9223372036854775807L - digit) / 10L {
      // The recorded lifetime is finite but too large for Int64. Clamp it
      // instead of wrapping negative and silently falling back to a short
      // default lifetime for the lazy session.
      return 9223372036854775807L
    }
    value = value * 10L + digit
  }
  if value <= 0L {
    DEFAULT_SESSION_TTL
  } else {
    value
  }
}

///|
/// The request's session. A detached session is materialized on first access;
/// requests that never touch session data keep `session` as `None`.
fn Context::session_materialized(self : Context) -> Session? {
  match self.session {
    Some(session) => Some(session)
    None =>
      match self.state.get(SESSION_LAZY_KEY) {
        Some(ttl_text) => {
          let session = session_detached(session_ttl_from_text(ttl_text))
          self.session = Some(session)
          Some(session)
        }
        None => None
      }
  }
}

///|
/// Give a detached session its random id.
fn session_ensure_id(session : Session) -> Unit {
  if session.id == "" {
    session.id = session_random_id(session_id_rng)
  }
}

///|
/// Look up a live session by id, dropping it when it has expired.
pub fn SessionStore::get(self : SessionStore, id : String) -> Session? {
  match self.sessions.get(id) {
    Some(session) =>
      if session.destroyed || session.expires_at <= @async.now() {
        ignore(self.sessions.remove(id))
        None
      } else {
        Some(session)
      }
    None => None
  }
}

///|
/// Store a session without changing its expiry. Used by `middleware_session`,
/// which must keep a fixed lifetime unless `rolling` or `session_touch` asked
/// for a refresh.
fn SessionStore::store(self : SessionStore, session : Session) -> Unit {
  let now = @async.now()
  // A destroyed session must not be written back. `get` and `sweep` both treat
  // it as gone, so reinserting it would only keep a dead entry in the store
  // (and an explicit save must not resurrect it).
  if session.destroyed {
    ignore(self.sessions.remove(session.id))
    return
  }
  // A session that expired while the handler was running must not be written
  // back as if it were live: the next lookup would discard it, and the client
  // would keep a cookie for data that is already gone.
  if session.expires_at <= now {
    ignore(self.sessions.remove(session.id))
    return
  }
  if !self.sessions.contains(session.id) {
    if self.sessions.length() >= SESSION_STORE_MAX_SESSIONS {
      // The throttle may have skipped the sweep even though expired sessions
      // are present, so collect them before dropping an arbitrary live one.
      self.sweep()
    } else {
      self.maybe_sweep(now)
    }
    if self.sessions.length() >= SESSION_STORE_MAX_SESSIONS {
      self.evict_one()
    }
  }
  self.sessions.set(session.id, session)
}

///|
/// Store a session, refreshing its expiry to `ttl` from now.
///
/// This is the explicit "write and renew" entry point. The session middleware
/// does not call it for ordinary writes, so a session keeps the fixed lifetime
/// it was created with unless `rolling=true` or `Context::session_touch()`
/// asks for a refresh.
pub fn SessionStore::save(self : SessionStore, session : Session) -> Unit {
  session.expires_at = session_expiry(@async.now(), self.ttl)
  self.store(session)
}

///|
/// Drop one arbitrary session, keeping the store under its cap when nothing has
/// expired yet.
fn SessionStore::evict_one(self : SessionStore) -> Unit {
  match self.sessions.keys().next() {
    Some(id) => ignore(self.sessions.remove(id))
    None => ()
  }
}

///|
/// Forget a session by id.
pub fn SessionStore::destroy(self : SessionStore, id : String) -> Unit {
  ignore(self.sessions.remove(id))
}

///|
/// Number of live (and not yet swept) sessions in the store.
pub fn SessionStore::count(self : SessionStore) -> Int32 {
  self.sessions.length()
}

///|
/// Drop every session.
pub fn SessionStore::clear(self : SessionStore) -> Unit {
  self.sessions.clear()
}

///|
/// Drop every expired or destroyed session eagerly.
pub fn SessionStore::sweep(self : SessionStore) -> Unit {
  if self.sessions.is_empty() {
    self.last_sweep = @async.now()
    return
  }
  let now = @async.now()
  self.last_sweep = now
  self.sessions.retain(fn(_id, session) {
    !session.destroyed && session.expires_at > now
  })
}

///|
fn SessionStore::maybe_sweep(self : SessionStore, now : Int64) -> Unit {
  if self.last_sweep == 0L || now - self.last_sweep >= SESSION_SWEEP_INTERVAL {
    self.sweep()
  }
}

///|
/// The session attached to this request by `middleware_session`, if any.
/// Sessions that were not materialized yet are created on first access.
pub fn Context::session(self : Context) -> Session? {
  self.session_materialized()
}

///|
/// Id of the session attached to this request, if any. Detached sessions are
/// given their random id on first access and saved like any other first write,
/// so the id returned here stays stable across requests that carry its cookie.
///
/// Returns `None` when the session was destroyed. It will not be persisted, so
/// minting an id for it would hand the caller a value that can never be used by
/// a later request.
pub fn Context::session_id(self : Context) -> String? {
  match self.session_materialized() {
    Some(session) =>
      if session.destroyed {
        None
      } else {
        let assigned = session.id == ""
        session_ensure_id(session)
        if assigned {
          // Asking for the id materializes the session: without saving it the
          // client would receive no cookie and a different id on every request.
          session.modified = true
        }
        Some(session.id)
      }
    None => None
  }
}

///|
/// Extend the attached session's lifetime to a full store TTL from now and
/// mark it for persistence. Returns `false` when no session is attached (for
/// example when `middleware_session` is not installed).
///
/// This is the sliding-expiration counterpart of `middleware_session`'s
/// default fixed lifetime: call it from handlers that should keep an active
/// user signed in, or enable `rolling=true` on the middleware to refresh every
/// request automatically.
pub fn Context::session_touch(self : Context) -> Bool {
  match self.session_materialized() {
    Some(session) => {
      if session.destroyed {
        return false
      }
      let ttl = match self.state.get(SESSION_TTL_STATE_KEY) {
        Some(text) => session_ttl_from_text(text)
        None => DEFAULT_SESSION_TTL
      }
      session.expires_at = session_expiry(@async.now(), ttl)
      session.modified = true
      true
    }
    None => false
  }
}

///|
/// Read a value from the session. Returns `""` when there is no session or the
/// key is absent.
pub fn Context::session_get(self : Context, key : String) -> String {
  match self.session_materialized() {
    Some(session) =>
      match session.data.get(key) {
        Some(value) => value
        None => ""
      }
    None => ""
  }
}

///|
/// Read a value from the session, returning `default` when there is no session
/// or the key is absent. Unlike `Context::session_get`, a stored empty string
/// is returned as-is instead of being replaced by `default`.
pub fn Context::session_get_default(
  self : Context,
  key : String,
  default : String,
) -> String {
  match self.session_materialized() {
    Some(session) =>
      match session.data.get(key) {
        Some(value) => value
        None => default
      }
    None => default
  }
}

///|
/// Whether the session contains `key`. Returns `false` when there is no
/// session or the key is absent, so it distinguishes a missing key from one
/// stored with an empty string value.
pub fn Context::session_has(self : Context, key : String) -> Bool {
  match self.session_materialized() {
    Some(session) => session.data.contains(key)
    None => false
  }
}

///|
/// Every key currently stored in the session, in an unspecified order.
/// Returns an empty array when there is no session.
pub fn Context::session_keys(self : Context) -> Array[String] {
  let keys : Array[String] = []
  match self.session_materialized() {
    Some(session) =>
      for key in session.data.keys() {
        keys.push(key)
      }
    None => ()
  }
  keys
}

///|
/// Write a value into the session, marking it for saving after the handler
/// returns. Returns `false` when the request has no session, for example when
/// `middleware_session` is not installed, or when the session was destroyed.
pub fn Context::session_set(
  self : Context,
  key : String,
  value : String,
) -> Bool {
  match self.session_materialized() {
    Some(session) => {
      // The middleware clears a destroyed session at persist time, so a write
      // must not claim to have been saved when it will be discarded.
      if session.destroyed {
        return false
      }
      session.data.set(key, value)
      session.modified = true
      true
    }
    None => false
  }
}

///|
/// Write a JSON value into the session, serialized as text. This is a thin
/// wrapper over `Context::session_set` for structured state such as a user
/// record; read it back with `Context::session_get_json`.
pub fn Context::session_set_json(
  self : Context,
  key : String,
  value : Json,
) -> Bool {
  let text = value.stringify()
  let stored = self.session_set(key, text)
  if stored {
    match self.session {
      Some(session) => {
        let cache = match session.json_cache {
          Some(cache) => cache
          None => {
            let cache : Map[String, (String, Json)] = Map([])
            session.json_cache = Some(cache)
            cache
          }
        }
        cache.set(key, (text, value))
      }
      None => ()
    }
  }
  stored
}

///|
/// Read a JSON value previously stored with `Context::session_set_json`.
/// Returns `None` when there is no session, the key is absent, or the stored
/// text is not valid JSON.
pub fn Context::session_get_json(self : Context, key : String) -> Json? {
  match self.session_materialized() {
    Some(session) =>
      match session.data.get(key) {
        Some(text) =>
          match session.json_cache {
            Some(cache) =>
              match cache.get(key) {
                Some((cached_text, value)) =>
                  if cached_text == text {
                    Some(value)
                  } else {
                    session_parse_json_into_cache(session, key, text)
                  }
                None => session_parse_json_into_cache(session, key, text)
              }
            None => session_parse_json_into_cache(session, key, text)
          }
        None => None
      }
    None => None
  }
}

///|
/// Parse `text` and remember the result under `key`.
fn session_parse_json_into_cache(
  session : Session,
  key : String,
  text : String,
) -> Json? {
  let parsed : Json = @json.parse(text) catch { _ => return None }
  let cache = match session.json_cache {
    Some(cache) => cache
    None => {
      let cache : Map[String, (String, Json)] = Map([])
      session.json_cache = Some(cache)
      cache
    }
  }
  cache.set(key, (text, parsed))
  Some(parsed)
}

///|
/// Remove a key from the session. Returns whether the key was present and the
/// change can still be saved; a destroyed session refuses further changes.
pub fn Context::session_remove(self : Context, key : String) -> Bool {
  match self.session_materialized() {
    Some(session) =>
      if session.destroyed {
        false
      } else {
        // Flash additions live in a request-local pending snapshot until
        // persist. Removing the stored key (or only queued messages for a
        // category that was not stored yet) must discard the pending snapshot
        // too, otherwise `flush_flash` would write it back and resurrect the
        // key.
        let flash_stored = if key.has_prefix(FLASH_PREFIX) {
          session.flash_stored_bytes(key)
        } else {
          0
        }
        let mut removed = match session.data.remove_and_get(key) {
          Some(_) => true
          None => false
        }
        if key.has_prefix(FLASH_PREFIX) {
          let category = key[FLASH_PREFIX.length():].to_owned()
          match session.flash_pending {
            Some(pending) =>
              match pending.remove_and_get(category) {
                Some(messages) => {
                  let added = flash_message_bytes(messages) - flash_stored
                  let remaining = session.flash_pending_bytes - added
                  session.flash_pending_bytes = if remaining < 0 {
                    0
                  } else {
                    remaining
                  }
                  removed = true
                }
                None => ()
              }
            None => ()
          }
        }
        if removed {
          match session.json_cache {
            Some(cache) => ignore(cache.remove(key))
            None => ()
          }
          session.modified = true
          true
        } else {
          false
        }
      }
    None => false
  }
}

///|
/// Remove every value from the session, including stored and queued flash
/// messages, while keeping the session itself alive. The empty session is
/// saved after the handler returns. Returns `false` when the request has no
/// session or the session was destroyed.
pub fn Context::session_clear(self : Context) -> Bool {
  match self.session_materialized() {
    Some(session) =>
      if session.destroyed {
        false
      } else {
        session.data.clear()
        session.flash_pending = None
        session.flash_pending_bytes = 0
        match session.json_cache {
          Some(cache) => cache.clear()
          None => ()
        }
        session.modified = true
        true
      }
    None => false
  }
}

///|
/// Destroy the session: it is removed from the store and the session cookie is
/// cleared when the response is sent. Returns `false` when the request has no
/// session.
pub fn Context::session_destroy(self : Context) -> Bool {
  match self.session_materialized() {
    Some(session) => {
      session.destroyed = true
      session.modified = true
      true
    }
    None => false
  }
}

///|
/// Request a fresh session id for this request while keeping its data. When the
/// request carried a live session, the middleware saves the data under a new
/// random id, removes the old id from the store and sends the new cookie.
/// Requests without an existing session already start from a fresh random id,
/// so no rotation is needed. Call this after a privilege change such as a
/// successful login to prevent session fixation.
///
/// Rotating the id also discards the default CSRF token (`_csrf`) so a token
/// learned before the privilege change cannot be replayed afterwards. When
/// using a custom token key, clear it explicitly with `Context::csrf_rotate`.
/// Returns `false` when the request has no session.
pub fn Context::session_regenerate(self : Context) -> Bool {
  match self.session_materialized() {
    Some(session) => {
      if session.destroyed {
        return false
      }
      ignore(session.csrf_clear(CSRF_TOKEN_KEY))
      session.regenerate = true
      // Rotation is an explicit privilege-change operation, so it also renews
      // the lifetime rather than carrying the old deadline to the new id.
      let ttl = match self.state.get(SESSION_TTL_STATE_KEY) {
        Some(text) => session_ttl_from_text(text)
        None => DEFAULT_SESSION_TTL
      }
      session.expires_at = session_expiry(@async.now(), ttl)
      session.modified = true
      true
    }
    None => false
  }
}

///|
/// Middleware that loads the session named by the session cookie, attaches it
/// to `Context::session`, and saves changes after the handler returns.
///
/// A cookie is only sent when the handler writes to the session, so read-only
/// requests stay cookie-free. Destroyed sessions clear the cookie and are
/// removed from the store. Pass `domain` to scope the cookie to a parent
/// domain, for example when several subdomains share one session. Sessions are
/// keyed by an unguessable random id, but the id itself is not signed; deploy
/// behind HTTPS and treat the store as server-local state.
priv struct SessionCookieConfig {
  name : String
  path : String
  domain : String?
  same_site : String
  http_only : Bool
  secure : Bool
  partitioned : Bool
  max_age : Int64?
}

///|
/// Send the session cookie for `id` with the middleware's cookie attributes.
fn session_send_cookie(
  ctx : Context,
  config : SessionCookieConfig,
  id : String,
  max_age : Int64?,
) -> Unit {
  ctx.set_cookie(
    config.name,
    id,
    path=config.path,
    max_age?,
    domain?=config.domain,
    same_site=config.same_site,
    http_only=config.http_only,
    secure=config.secure,
    partitioned=config.partitioned,
  )
}

///|
/// The `Max-Age` a re-sent session cookie should advertise.
///
/// A fixed-lifetime session keeps its original server deadline even when its
/// data changes, so the browser cookie must not be given a fresh full
/// lifetime on every write. Round the remaining milliseconds up, matching the
/// initial cookie, and never exceed the configured lifetime.
fn session_remaining_max_age(
  config : SessionCookieConfig,
  session : Session,
  now : Int64,
) -> Int64? {
  let full = match config.max_age {
    Some(value) => value
    None => return None
  }
  let remaining = session.expires_at - now
  if remaining <= 0L {
    return Some(0L)
  }
  let millis = remaining % 1000L
  let seconds = remaining / 1000L + (if millis == 0L { 0L } else { 1L })
  Some(if seconds < full { seconds } else { full })
}

///|
/// Save, rotate or destroy the request's session and send or clear its cookie.
fn session_persist(
  ctx : Context,
  store : SessionStore,
  config : SessionCookieConfig,
  had_cookie : Bool,
  is_new : Bool,
) -> Unit {
  let stale_cookie = ctx.state.contains(SESSION_STALE_COOKIE_KEY)
  match ctx.session {
    None =>
      // A cookie that named no live session is expired even when the handler
      // never materialized a session, so it does not keep being sent.
      if stale_cookie {
        session_send_cookie(ctx, config, "", Some(0L))
      }
    Some(session) =>
      if session.destroyed {
        store.destroy(session.id)
        if had_cookie {
          session_send_cookie(ctx, config, "", Some(0L))
        }
      } else {
        session.flush_flash()
        if session.id == "" && session.modified {
          session_ensure_id(session)
        }
        let rotated : String? = if session.regenerate && !is_new {
          let old_id = session.id
          session.id = store.generate_id()
          store.destroy(old_id)
          Some(session.id)
        } else {
          None
        }
        session.regenerate = false
        if session.modified || rotated is Some(_) {
          // Keep the existing deadline for an ordinary write: a fixed-lifetime
          // session must not slide just because its data changed. If that
          // deadline passed during the request, discard the write and expire
          // the client cookie instead of advertising a fresh lifetime for a
          // session the store will drop on its next lookup.
          let now = @async.now()
          if session.expires_at <= now {
            store.destroy(session.id)
            if had_cookie {
              session_send_cookie(ctx, config, "", Some(0L))
            }
          } else {
            store.store(session)
            session_send_cookie(
              ctx,
              config,
              session.id,
              session_remaining_max_age(config, session, now),
            )
          }
        } else if stale_cookie {
          // The handler only read the session (or did not touch it), so no
          // replacement cookie was written: still expire the stale one.
          session_send_cookie(ctx, config, "", Some(0L))
        }
      }
  }
}

///|
pub fn middleware_session(
  store : SessionStore,
  cookie~ : String = "feather_session",
  path~ : String = "/",
  domain? : String,
  same_site~ : String = "Lax",
  http_only~ : Bool = true,
  secure~ : Bool = false,
  partitioned~ : Bool = false,
  rolling~ : Bool = false,
) -> Middleware {
  let ttl = store.ttl()
  let whole_seconds = ttl / 1000L
  // Round up: a browser cookie must not expire before the server-side session,
  // so a 1999 ms TTL advertises Max-Age=2 rather than truncating to 1.
  let cookie_seconds = if ttl % 1000L == 0L {
    whole_seconds
  } else {
    whole_seconds + 1L
  }
  let config : SessionCookieConfig = {
    name: cookie,
    path,
    domain,
    same_site,
    http_only,
    secure,
    partitioned,
    max_age: if ttl >= 1000L { Some(cookie_seconds) } else { None },
  }
  let lazy_ttl_text = store.ttl().to_string()
  fn(next) {
    fn(ctx) raise {
      let cookie_id = ctx.cookie(config.name)
      let existing = match cookie_id {
        Some(id) => store.get(id)
        None => None
      }
      let is_new = existing is None
      let had_cookie = cookie_id is Some(_)
      ctx.state.set(SESSION_TTL_STATE_KEY, lazy_ttl_text)
      match existing {
        Some(session) => {
          session.modified = false
          if rolling {
            // Sliding expiration: every request that carries a live session
            // extends it and re-sends the cookie, so an active client does not
            // get logged out at the original creation deadline.
            session.expires_at = session_expiry(@async.now(), ttl)
            session.modified = true
          }
          ctx.session = Some(session)
        }
        None => {
          if had_cookie {
            ctx.state.set(SESSION_STALE_COOKIE_KEY, "1")
          }
          ctx.state.set(SESSION_LAZY_KEY, lazy_ttl_text)
        }
      }
      errdefer session_persist(ctx, store, config, had_cookie, is_new)
      next(ctx)
      session_persist(ctx, store, config, had_cookie, is_new)
    }
  }
}
