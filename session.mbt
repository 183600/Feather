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
}

///|
/// Default session lifetime: 24 hours.
pub const DEFAULT_SESSION_TTL : Int64 = 86_400_000L

///|
/// How often expired sessions are swept when the store is written to.
const SESSION_SWEEP_INTERVAL : Int64 = 60_000L

///|
/// In-memory session storage for a single server process.
///
/// New session ids come from a ChaCha8 generator seeded with platform entropy
/// when the host provides it. Expired sessions are dropped when they are read
/// and, at most once a minute, whenever the store is written to; call
/// `SessionStore::sweep` to collect them eagerly.
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
  let out = FixedArray::make(32, b'0')
  for i = 0; i < 2; i = i + 1 {
    let value = self.rng.uint64()
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
/// Create a fresh, unsaved session with a random id and empty data.
pub fn SessionStore::create(self : SessionStore) -> Session {
  {
    id: self.generate_id(),
    data: Map([], capacity=4),
    expires_at: @async.now() + self.ttl,
    modified: false,
    destroyed: false,
    regenerate: false,
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
  self.maybe_sweep()
  self.sessions.set(session.id, session)
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
  let expired : Array[String] = []
  for id, session in self.sessions {
    if session.destroyed || session.expires_at <= now {
      expired.push(id)
    }
  }
  for id in expired {
    ignore(self.sessions.remove(id))
  }
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
pub fn Context::session(self : Context) -> Session? {
  self.session
}

///|
/// Id of the session attached to this request, if any.
pub fn Context::session_id(self : Context) -> String? {
  match self.session {
    Some(session) => Some(session.id)
    None => None
  }
}

///|
/// Read a value from the session. Returns `""` when there is no session or the
/// key is absent.
pub fn Context::session_get(self : Context, key : String) -> String {
  match self.session {
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
  match self.session {
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
  self.session_set(key, value.stringify())
}

///|
/// Read a JSON value previously stored with `Context::session_set_json`.
/// Returns `None` when there is no session, the key is absent, or the stored
/// text is not valid JSON.
pub fn Context::session_get_json(self : Context, key : String) -> Json? {
  match self.session {
    Some(session) =>
      match session.data.get(key) {
        Some(text) => {
          let parsed : Json = @json.parse(text) catch {
            _ => return None
          }
          Some(parsed)
        }
        None => None
      }
    None => None
  }
}

///|
/// Remove a key from the session. Returns whether the key was present.
pub fn Context::session_remove(self : Context, key : String) -> Bool {
  match self.session {
    Some(session) =>
      match session.data.remove_and_get(key) {
        Some(_) => {
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
  match self.session {
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
  match self.session {
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
pub fn middleware_session(
  store : SessionStore,
  cookie~ : String = "feather_session",
  path~ : String = "/",
  same_site~ : String = "Lax",
  http_only~ : Bool = true,
  secure~ : Bool = false,
) -> Middleware {
  let cookie_name = cookie
  let max_age : Int64? = if store.ttl() >= 1000L {
    Some(store.ttl() / 1000L)
  } else {
    None
  }
  fn(next) {
    fn(ctx) raise {
      let existing = match ctx.cookie(cookie_name) {
        Some(id) => store.get(id)
        None => None
      }
      let is_new = existing is None
      ctx.session = Some(
        match existing {
          Some(session) => session
          None => store.create()
        },
      )
      let send_cookie = fn(id : String) {
        ctx.set_cookie(
          cookie_name,
          id,
          path~,
          max_age?,
          same_site~,
          http_only~,
          secure~,
        )
      }
      let persist = fn() {
        match ctx.session {
          None => ()
          Some(session) =>
            if session.destroyed {
              store.destroy(session.id)
              if !is_new {
                ctx.set_cookie(
                  cookie_name,
                  "",
                  path~,
                  max_age=0L,
                  same_site~,
                  http_only~,
                  secure~,
                )
              }
            } else {
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
                let current = match ctx.cookie(cookie_name) {
                  Some(value) => value
                  None => ""
                }
                if rotated is Some(_) || is_new || current != session.id {
                  send_cookie(session.id)
                }
              }
            }
        }
      }
      errdefer persist()
      next(ctx)
      persist()
    }
  }
}
