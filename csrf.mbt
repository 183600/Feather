///|
/// Per-session token used to protect state-changing requests against
/// cross-site request forgery.
const CSRF_TOKEN_KEY : String = "_csrf"

///|
/// Length of a CSRF token in characters (two 64-bit values in hex).
const CSRF_TOKEN_LENGTH : Int32 = 32

///|
/// Shared generator for CSRF tokens, seeded from platform entropy (falling
/// back to a clock-derived seed where entropy is unavailable).
let csrf_rng : @random.Rand = platform_rand()

///|
/// Generate a fresh random CSRF token: 32 lowercase hex characters.
fn csrf_generate_token() -> String {
  let out = FixedArray::make(CSRF_TOKEN_LENGTH, b'0')
  for i = 0; i < 2; i = i + 1 {
    let value = csrf_rng.uint64()
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
/// Compare two tokens without an early exit on the first differing character,
/// so the comparison does not leak how much of a guess was correct.
fn csrf_constant_time_equal(a : StringView, b : StringView) -> Bool {
  if a.length() != b.length() {
    return false
  }
  let mut diff = 0
  for i = 0; i < a.length(); i = i + 1 {
    diff = diff | (a.unsafe_get(i) ^ b.unsafe_get(i)).to_int()
  }
  diff == 0
}

///|
/// Drop the synchronizer token stored under `key`, marking the session as
/// changed when a token was present.
fn Session::csrf_clear(self : Session, key : String) -> Bool {
  match self.data.remove_and_get(key) {
    Some(_) => {
      self.modified = true
      true
    }
    None => false
  }
}

///|
/// Discard the CSRF token bound to this request's session so the next
/// `Context::csrf_token` call mints a fresh one.
///
/// `Context::session_regenerate` performs this rotation automatically for the
/// default token key. Call this helper directly when using a custom `key` (or
/// when a privilege change happens without rotating the session id). Returns
/// whether a token was actually removed; a destroyed session refuses the
/// change because it will not be persisted.
pub fn Context::csrf_rotate(
  self : Context,
  key~ : String = CSRF_TOKEN_KEY,
) -> Bool {
  match self.session() {
    Some(session) =>
      if session.destroyed {
        false
      } else {
        session.csrf_clear(key)
      }
    None => false
  }
}

///|
/// The CSRF token bound to this request's session, generating and saving one
/// when the session has none yet. Returns `""` when no session is attached,
/// for example when `middleware_session` is not installed.
///
/// Embed the returned token in forms as the field expected by
/// `middleware_csrf` (default `_csrf`) or send it back in the header
/// (default `X-CSRF-Token`).
pub fn Context::csrf_token(
  self : Context,
  key~ : String = CSRF_TOKEN_KEY,
) -> String {
  match self.session() {
    Some(session) =>
      if session.destroyed {
        // The session is removed when the response is sent, so a token minted
        // now could never be validated by a later request.
        ""
      } else {
        match session.data.get(key) {
          Some(token) => token
          None => {
            let token = csrf_generate_token()
            session.data.set(key, token)
            session.modified = true
            token
          }
        }
      }
    None => ""
  }
}

///|
/// Middleware that rejects state-changing requests which fail to prove they
/// come from a page served by this application, using a synchronizer token
/// stored in the session.
///
/// Install it after `middleware_session` so requests have a session. Safe
/// methods (`GET`, `HEAD`, `OPTIONS`, `TRACE`) pass through untouched; handlers
/// for those methods can render `Context::csrf_token()` into forms. Unsafe
/// methods (`POST`, `PUT`, `PATCH`, `DELETE`, ...) must send the same token in
/// the `header` (default `X-CSRF-Token`), in a
/// `application/x-www-form-urlencoded` field, or in a multipart field, named by
/// `field` (default `_csrf`); otherwise the request is answered with
/// `403 Forbidden` before reaching the handler. Requests without a session and
/// requests whose session has no token yet are rejected too.
///
/// Pass `safe_methods` to replace the default exemption list, for example
/// `safe_methods=[]` protects every method or an extra verb can be exempted
/// without weakening the standard safe methods. Method names are matched
/// case-insensitively.
pub fn middleware_csrf(
  field~ : String = CSRF_TOKEN_KEY,
  header~ : String = "X-CSRF-Token",
  key~ : String = CSRF_TOKEN_KEY,
  safe_methods? : Array[String],
) -> Middleware {
  let field_name = field
  let header_name = header
  let token_key = key
  let safe : Map[String, Bool]? = match safe_methods {
    Some(methods) => {
      let table : Map[String, Bool] = Map([], capacity=methods.length())
      for verb in methods {
        table.set(normalize_method(verb), true)
      }
      Some(table)
    }
    None => None
  }
  fn(next) {
    fn(ctx) raise {
      let meth = normalize_method(ctx.get_method())
      let is_safe = match safe {
        Some(table) => table.contains(meth)
        None =>
          meth == "GET" || meth == "HEAD" || meth == "OPTIONS" || meth == "TRACE"
      }
      if is_safe {
        next(ctx)
        return
      }
      let expected = match ctx.session() {
        Some(session) =>
          match session.data.get(token_key) {
            Some(token) => token
            None => ""
          }
        None => ""
      }
      let mut provided = trim_ascii_space(ctx.header(header_name).view())
      if provided == "" {
        provided = trim_ascii_space(ctx.form(field_name).view())
      }
      if provided == "" {
        provided = trim_ascii_space(ctx.multipart_value(field_name).view())
      }
      if expected != "" &&
        provided != "" &&
        csrf_constant_time_equal(provided, expected.view()) {
        next(ctx)
      } else {
        clear_replaced_body_headers(ctx.response.headers)
        clear_replaced_representation_headers(ctx.response.headers)
        ctx.text(403, "403 Forbidden")
      }
    }
  }
}

///|
/// Request-state key holding the raw token verified or minted by
/// `middleware_csrf_cookie`.
const CSRF_COOKIE_TOKEN_STATE_KEY : String = "__feather_csrf_cookie_token"

///|
/// The token managed by `middleware_csrf_cookie` for the current request.
///
/// Safe requests get a token even when the client did not send one, so a form
/// or script can embed it. Unsafe requests report `""` when the token cookie is
/// missing or invalid. Returns `""` when the middleware is not installed.
pub fn Context::csrf_cookie_token(self : Context) -> String {
  match self.state.get(CSRF_COOKIE_TOKEN_STATE_KEY) {
    Some(token) => token
    None => ""
  }
}

///|
/// Sessionless CSRF protection using a signed double-submit cookie.
///
/// Unlike `middleware_csrf`, this variant does not need
/// `middleware_session`: a random token is stored in a cookie whose value is
/// HMAC-signed with `secret`, and unsafe requests must echo the token in the
/// `header` (default `X-CSRF-Token`), an urlencoded `field`, or a multipart
/// field (default `_csrf`). Safe methods receive or refresh the cookie and can
/// read the token with `Context::csrf_cookie_token`.
///
/// The signature is what makes the double-submit pattern trustworthy: a
/// sibling subdomain or an attacker-controlled cookie cannot forge a token
/// without the secret. Keep `secret` private and high-entropy. `http_only`
/// defaults to `false` because browser scripts that submit JSON requests need
/// to read the cookie; use the header-based flow with `http_only=true` when
/// only server-rendered forms need the token.
pub fn middleware_csrf_cookie(
  secret : String,
  cookie~ : String = "feather_csrf",
  field~ : String = CSRF_TOKEN_KEY,
  header~ : String = "X-CSRF-Token",
  path~ : String = "/",
  same_site~ : String = "Lax",
  http_only~ : Bool = false,
  secure~ : Bool = false,
  partitioned~ : Bool = false,
  max_age? : Int64,
  safe_methods? : Array[String],
) -> Middleware {
  let cookie_name = cookie
  let field_name = field
  let header_name = header
  let cookie_path = path
  let cookie_same_site = same_site
  let safe : Map[String, Bool]? = match safe_methods {
    Some(methods) => {
      let table : Map[String, Bool] = Map([], capacity=methods.length())
      for verb in methods {
        table.set(normalize_method(verb), true)
      }
      Some(table)
    }
    None => None
  }
  fn(next) {
    fn(ctx) raise {
      let meth = normalize_method(ctx.get_method())
      let is_safe = match safe {
        Some(table) => table.contains(meth)
        None =>
          meth == "GET" || meth == "HEAD" || meth == "OPTIONS" || meth == "TRACE"
      }
      let existing = match ctx.signed_cookie(cookie_name, secret) {
        Some(token) => if token == "" { None } else { Some(token) }
        None => None
      }
      let token = match existing {
        Some(token) => {
          ctx.state.set(CSRF_COOKIE_TOKEN_STATE_KEY, token)
          token
        }
        None =>
          // Unsafe requests must present an already-issued token. Minting a
          // replacement here would only send a cookie to a request that is
          // about to be rejected.
          if !is_safe {
            ""
          } else {
            let token = csrf_generate_token()
            ctx.set_signed_cookie(
              cookie_name,
              token,
              secret,
              path=cookie_path,
              max_age?,
              same_site=cookie_same_site,
              http_only~,
              secure~,
              partitioned~,
            )
            ctx.state.set(CSRF_COOKIE_TOKEN_STATE_KEY, token)
            token
          }
      }
      if is_safe {
        next(ctx)
        return
      }
      let mut provided = trim_ascii_space(ctx.header(header_name).view())
      if provided == "" {
        provided = trim_ascii_space(ctx.form(field_name).view())
      }
      if provided == "" {
        provided = trim_ascii_space(ctx.multipart_value(field_name).view())
      }
      if token != "" &&
        provided != "" &&
        csrf_constant_time_equal(provided, token.view()) {
        next(ctx)
      } else {
        clear_replaced_body_headers(ctx.response.headers)
        clear_replaced_representation_headers(ctx.response.headers)
        ctx.text(403, "403 Forbidden")
      }
    }
  }
}
