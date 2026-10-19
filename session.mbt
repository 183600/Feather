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
  mut flash_pending_bytes : Int
  json_cache : Map[String, (String, Json)]
}

///|
/// Default session lifetime: 24 hours.
pub const DEFAULT_SESSION_TTL : Int64 = 86_400_000L

///|
/// How often expired sessions are swept when the store is written to.
const SESSION_SWEEP_INTERVAL : Int64 = 60_000L

///|
/// Hard upper bound on retained sessions. When the store is full and no
/// session has expired yet, an arbitrary session is dropped so
/// unauthenticated traffic cannot grow the store without bound within a TTL
/// window.
const SESSION_STORE_MAX_SESSIONS : Int = 10_000

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
      out[i * 8 + j] = (((value >> (j * 8)) & 255L).to_int()).to_byte()
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
/// Render a random 32-character hex id from `rng`.
fn session_random_id(rng : @random.Rand) -> String {
  let out = FixedArray::make(32, b'0')
  for i = 0; i < 2; i = i + 1 {
    let value = rng.uint64()
    for j = 0; j < 16; j = j + 1 {
      let nibble = ((value >> ((15 - j) * 4)) & 15UL).to_int()
      out[i * 16 + j] = (if nibble < 10 {
        b'0'.to_int() + nibble
      } else {
        b'a'.to_int() + nibble - 10
      }).to_byte()
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
    ttl: if ttl <= 0L { DEFAULT_SESSION_TTL } else { ttl },
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
    data: Map([], capacity=4),
    expires_at: @async.now() + self.ttl,
    modified: false,
    destroyed: false,
    regenerate: false,
    flash_pending: None,
    flash_pending_bytes: 0,
    json_cache: Map([]),
  }
}

///|
/// Create a detached session. Its id and store slot are assigned when the
/// request first writes to the session.
fn session_detached(ttl : Int64) -> Session {
  {
    id: "",
    data: Map([]),
    expires_at: @async.now() + ttl,
    modified: false,
    destroyed: false,
    regenerate: false,
    flash_pending: None,
    flash_pending_bytes: 0,
    json_cache: Map([]),
  }
}

///|
/// State key under which `middleware_session` records the store TTL for a
/// request whose anonymous session has not been materialized yet.
const SESSION_LAZY_KEY : String = "__feather_session_ttl"

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
    value = value * 10L + (code - 48).to_int64()
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
/// Store a session, refreshing its expiry to `ttl` from now.
pub fn SessionStore::save(self : SessionStore, session : Session) -> Unit {
  session.expires_at = @async.now() + self.ttl
  if !self.sessions.contains(session.id) {
    self.maybe_sweep()
    if self.sessions.length() >= SESSION_STORE_MAX_SESSIONS {
      self.evict_one()
    }
  }
  self.sessions.set(session.id, session)
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
pub fn SessionStore::count(self : SessionStore) -> Int {
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
fn SessionStore::maybe_sweep(self : SessionStore) -> Unit {
  let now = @async.now()
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
/// given their random id on first access.
pub fn Context::session_id(self : Context) -> String? {
  match self.session_materialized() {
    Some(session) => {
      session_ensure_id(session)
      Some(session.id)
    }
    None => None
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
/// Write a value into the session, marking it for saving after the handler
/// returns. Returns `false` when the request has no session, for example when
/// `middleware_session` is not installed.
pub fn Context::session_set(
  self : Context,
  key : String,
  value : String,
) -> Bool {
  match self.session_materialized() {
    Some(session) => {
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
      Some(session) => session.json_cache.set(key, (text, value))
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
          match session.json_cache.get(key) {
            Some((cached_text, value)) =>
              if cached_text == text {
                Some(value)
              } else {
                session_parse_json_into_cache(session, key, text)
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
  let parsed : Json = @json.parse(text) catch {
    _ => return None
  }
  session.json_cache.set(key, (text, parsed))
  Some(parsed)
}

///|
/// Remove a key from the session. Returns whether the key was present.
pub fn Context::session_remove(self : Context, key : String) -> Bool {
  match self.session_materialized() {
    Some(session) =>
      match session.data.remove_and_get(key) {
        Some(_) => {
          ignore(session.json_cache.remove(key))
          session.modified = true
          true
        }
        None => false
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
/// successful login to prevent session fixation. Returns `false` when the
/// request has no session.
pub fn Context::session_regenerate(self : Context) -> Bool {
  match self.session_materialized() {
    Some(session) => {
      session.regenerate = true
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
/// removed from the store. Sessions are keyed by an unguessable random id, but
/// the id itself is not signed; deploy behind HTTPS and treat the store as
/// server-local state.
priv struct SessionCookieConfig {
  name : String
  path : String
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
    same_site=config.same_site,
    http_only=config.http_only,
    secure=config.secure,
    partitioned=config.partitioned,
  )
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
  match ctx.session {
    None => ()
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
          store.save(session)
          session_send_cookie(ctx, config, session.id, config.max_age)
        }
      }
  }
}

///|
pub fn middleware_session(
  store : SessionStore,
  cookie~ : String = "feather_session",
  path~ : String = "/",
  same_site~ : String = "Lax",
  http_only~ : Bool = true,
  secure~ : Bool = false,
  partitioned~ : Bool = false,
) -> Middleware {
  let config : SessionCookieConfig = {
    name: cookie,
    path,
    same_site,
    http_only,
    secure,
    partitioned,
    max_age: if store.ttl() >= 1000L {
      Some(store.ttl() / 1000L)
    } else {
      None
    },
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
      match existing {
        Some(session) => {
          session.modified = false
          ctx.session = Some(session)
        }
        None => ctx.state.set(SESSION_LAZY_KEY, lazy_ttl_text)
      }
      errdefer session_persist(ctx, store, config, had_cookie, is_new)
      next(ctx)
      session_persist(ctx, store, config, had_cookie, is_new)
    }
  }
}
