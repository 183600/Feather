///|
/// Errors raised while verifying a JSON Web Token.
pub(all) suberror JwtError {
  /// The compact serialization is malformed, or a segment is not valid
  /// canonical base64url/UTF-8/JSON.
  JwtMalformed(String)
  /// The protected header names an algorithm other than `HS256`.
  JwtUnsupportedAlgorithm(String)
  /// The signature does not authenticate the header and payload.
  JwtInvalidSignature
  /// The `exp` claim is in the past (outside the configured leeway).
  JwtExpired
  /// The `nbf` claim is in the future (outside the configured leeway).
  JwtNotYetValid
  /// A registered claim is malformed or does not match the expected value.
  JwtInvalidClaim(String)
}

///|
/// A verified JWT, exposing the protected header and the claims payload.
///
/// Obtain one with `verify_jwt_hs256`, or read the claims installed by
/// `middleware_jwt_hs256` through `Context::jwt_claims` /
/// `Context::jwt_claim`.
pub(all) struct Jwt {
  header : Json
  claims : Json
}

///|
/// The protected header of a verified token.
pub fn Jwt::header(self : Jwt) -> Json {
  self.header
}

///|
/// All claims of a verified token. The value is an object, because
/// `verify_jwt_hs256` rejects tokens whose payload is not a JSON object.
pub fn Jwt::claims(self : Jwt) -> Json {
  self.claims
}

///|
/// Look up one claim in a verified token, or `None` when it is absent or the
/// payload is not an object.
pub fn Jwt::claim(self : Jwt, name : String) -> Json? {
  match self.claims {
    Json::Object(claims) => claims.get(name)
    _ => None
  }
}

///|
/// Look up a string-valued claim in a verified token.
pub fn Jwt::string_claim(self : Jwt, name : String) -> String? {
  match self.claim(name) {
    Some(Json::String(value)) => Some(value)
    _ => None
  }
}

///|
/// Look up a numeric claim in a verified token.
pub fn Jwt::number_claim(self : Jwt, name : String) -> Double? {
  match self.claim(name) {
    Some(Json::Number(value, ..)) => Some(value)
    _ => None
  }
}

///|
/// The `sub` claim of a verified token, or `""` when it is absent or not a
/// string.
pub fn Jwt::subject(self : Jwt) -> String {
  match self.string_claim("sub") {
    Some(subject) => subject
    None => ""
  }
}

///|
/// Request-state key holding the protected header installed by
/// `middleware_jwt_hs256`.
const JWT_HEADER_STATE_KEY : String = "__feather_jwt_header"

///|
/// Request-state key holding the claims installed by `middleware_jwt_hs256`.
const JWT_CLAIMS_STATE_KEY : String = "__feather_jwt_claims"

///|
/// Request-state key recording why JWT verification failed, for logging
/// middleware. The response itself stays generic.
const JWT_ERROR_STATE_KEY : String = "__feather_jwt_error"

///|
/// Decode one compact-serialization segment as canonical, unpadded base64url
/// and then strict UTF-8 JSON.
///
/// Canonical spelling matters because the signature covers the encoded text:
/// accepting an alternate spelling of the same bytes (padding, `+`/`/`
/// aliases, or non-zero trailing bits) would let one signed token be rewritten
/// into another accepted wire representation. RFC 7515 requires unpadded
/// base64url, so rejecting non-canonical segments is also the interoperable
/// choice.
fn jwt_json_segment(segment : StringView, what : String) -> Json raise JwtError {
  if segment.is_empty() {
    raise JwtMalformed("empty " + what)
  }
  let bytes = match base64url_decode_view(segment) {
    Some(bytes) => bytes
    None => raise JwtMalformed("invalid base64url in " + what)
  }
  if base64url_encode(bytes).view() != segment {
    raise JwtMalformed("non-canonical base64url in " + what)
  }
  let text = @utf8.decode(bytes) catch {
    @utf8.Malformed(_) => raise JwtMalformed(what + " is not valid UTF-8")
  }
  @json.parse(text) catch {
    _ => raise JwtMalformed(what + " is not valid JSON")
  }
}

///|
/// Split a compact JWS into its three segments.
///
/// Exactly two dots are allowed; a missing or extra separator is malformed
/// rather than a token whose signature could be reinterpreted.
fn jwt_compact_parts(token : StringView) -> (StringView, StringView, StringView) raise JwtError {
  let first = match token.find(".") {
    Some(index) => index
    None => raise JwtMalformed("JWT must have three segments")
  }
  let rest = token[first + 1:]
  let second = match rest.find(".") {
    Some(index) => index
    None => raise JwtMalformed("JWT must have three segments")
  }
  let signature = rest[second + 1:]
  if signature.find(".") is Some(_) {
    raise JwtMalformed("JWT must have three segments")
  }
  (token[:first], rest[:second], signature)
}

///|
/// Read a numeric JWT time claim in seconds since the Unix epoch.
fn jwt_time_claim(value : Json, name : String) -> Double raise JwtError {
  match value {
    Json::Number(seconds, ..) =>
      // JSON cannot spell NaN or infinities, but a hand-built `Json` can. A
      // non-finite NumericDate is unusable as a clock comparison.
      if seconds != seconds ||
        seconds > 1.0e18 ||
        seconds < -1.0e18 {
        raise JwtInvalidClaim(name + " is not a finite timestamp")
      } else {
        seconds
      }
    _ => raise JwtInvalidClaim(name + " must be a number")
  }
}

///|
/// Verify a compact HS256 JWT and return its header and claims.
///
/// The implementation deliberately accepts only the `HS256` algorithm named
/// in the protected header; in particular it rejects `"alg": "none"` and the
/// asymmetric algorithms, which require a different key type. The HMAC is
/// computed over the exact `header.payload` text, and the signature is
/// compared in constant time.
///
/// `exp` is required by default so a signed token cannot remain valid forever
/// by omitting the claim; pass `require_exp=false` when consuming tokens from a
/// system that uses another expiry mechanism. `nbf`, when present, is also
/// honored. `leeway` is the permitted clock skew in seconds (negative values
/// are treated as zero), and `now` overrides the current Unix time in seconds,
/// which is mainly useful in tests.
///
/// Pass `issuer` and/or `audience` to require the corresponding registered
/// claim. `aud` may be a single string or an array of strings, as RFC 7519
/// permits; the token is accepted when one entry names `audience`.
///
/// The secret is UTF-8 encoded as-is. Use a high-entropy secret (at least 32
/// random bytes for HS256) and keep it out of source control.
pub fn verify_jwt_hs256(
  token : String,
  secret : String,
  leeway~ : Int32 = 0,
  now? : Int64,
  require_exp~ : Bool = true,
  issuer? : String,
  audience? : String,
) -> Jwt raise JwtError {
  let (header_part, payload_part, signature_part) = jwt_compact_parts(
    token.view(),
  )
  let header_json = jwt_json_segment(header_part, "JWT header")
  let header = match header_json {
    Json::Object(header) => header
    _ => raise JwtMalformed("JWT header must be an object")
  }
  let algorithm = match header.get("alg") {
    Some(Json::String(value)) => value
    _ => raise JwtMalformed("JWT header must name an algorithm")
  }
  if algorithm != "HS256" {
    raise JwtUnsupportedAlgorithm(algorithm)
  }
  // Extensions listed in `crit` must be understood before the token may be
  // accepted; this verifier implements none, so any such token is rejected.
  if header.contains("crit") {
    raise JwtMalformed("unsupported critical JWT header")
  }
  let signature = match base64url_decode_view(signature_part) {
    Some(bytes) => bytes
    None => raise JwtMalformed("invalid base64url signature")
  }
  if base64url_encode(signature).view() != signature_part {
    raise JwtMalformed("non-canonical base64url signature")
  }
  // HS256 always produces exactly 32 bytes. Rejecting shorter/longer values
  // before the constant-time comparison keeps a truncated signature from
  // reaching the MAC check.
  if signature.length() != 32 {
    raise JwtInvalidSignature
  }
  let last_dot = header_part.length() + 1 + payload_part.length()
  let signing_input = encode_utf8_lossy(token.view()[:last_dot])
  let expected = hmac_sha256(secret_utf8(secret), signing_input)
  if !constant_time_bytes_equal(signature, expected) {
    raise JwtInvalidSignature
  }
  let claims_json = jwt_json_segment(payload_part, "JWT payload")
  let claims = match claims_json {
    Json::Object(claims) => claims
    _ => raise JwtMalformed("JWT payload must be an object")
  }
  let skew = if leeway < 0 { 0.0 } else { leeway.to_double() }
  let current = match now {
    Some(seconds) => seconds.to_double()
    None => (@async.now() / 1000L).to_double()
  }
  match claims.get("exp") {
    Some(value) => {
      let expires = jwt_time_claim(value, "exp")
      // Accept a token for `leeway` seconds past its expiry so small clock
      // differences between issuer and verifier do not reject fresh tokens.
      if current >= expires + skew {
        raise JwtExpired
      }
    }
    None =>
      if require_exp {
        raise JwtInvalidClaim("exp is required")
      }
  }
  match claims.get("nbf") {
    Some(value) => {
      let not_before = jwt_time_claim(value, "nbf")
      if current + skew < not_before {
        raise JwtNotYetValid
      }
    }
    None => ()
  }
  match issuer {
    Some(expected) =>
      match claims.get("iss") {
        Some(Json::String(actual)) =>
          if actual != expected {
            raise JwtInvalidClaim("issuer mismatch")
          }
        Some(_) => raise JwtInvalidClaim("iss must be a string")
        None => raise JwtInvalidClaim("iss is required")
      }
    None => ()
  }
  match audience {
    Some(expected) =>
      match claims.get("aud") {
        Some(Json::String(actual)) =>
          if actual != expected {
            raise JwtInvalidClaim("audience mismatch")
          }
        Some(Json::Array(entries)) => {
          let mut matched = false
          for entry in entries {
            match entry {
              Json::String(actual) => if actual == expected {
                matched = true
              }
              _ => raise JwtInvalidClaim("aud must be a string or array of strings")
            }
          }
          if !matched {
            raise JwtInvalidClaim("audience mismatch")
          }
        }
        Some(_) => raise JwtInvalidClaim("aud must be a string or array of strings")
        None => raise JwtInvalidClaim("aud is required")
      }
    None => ()
  }
  { header: header_json, claims: claims_json }
}

///|
/// The protected header installed by `middleware_jwt_hs256`, or `None` when
/// this request did not carry a verified token or the middleware is not
/// installed.
///
/// The header is an object containing at least `alg`; applications can read
/// parameters such as `kid` to select a key or record the token type.
pub fn Context::jwt_header(self : Context) -> Json? {
  self.json_state.get(JWT_HEADER_STATE_KEY)
}

///|
/// Look up one protected-header parameter installed by
/// `middleware_jwt_hs256`. Returns `None` for an absent parameter or a request
/// without a verified token.
pub fn Context::jwt_header_parameter(self : Context, name : String) -> Json? {
  match self.jwt_header() {
    Some(Json::Object(header)) => header.get(name)
    _ => None
  }
}

///|
/// The claims installed by `middleware_jwt_hs256`, or `None` when this request
/// did not carry a verified token or the middleware is not installed.
///
/// The payload is an object with the token's registered and private claims.
pub fn Context::jwt_claims(self : Context) -> Json? {
  self.json_state.get(JWT_CLAIMS_STATE_KEY)
}

///|
/// Look up one claim installed by `middleware_jwt_hs256`. Returns `None` for
/// an absent claim or a request without a verified token.
pub fn Context::jwt_claim(self : Context, name : String) -> Json? {
  match self.jwt_claims() {
    Some(Json::Object(claims)) => claims.get(name)
    _ => None
  }
}

///|
/// The `sub` claim installed by `middleware_jwt_hs256`, or `""` when it is
/// absent or the request was not authenticated with a JWT.
pub fn Context::jwt_subject(self : Context) -> String {
  match self.jwt_claim("sub") {
    Some(Json::String(subject)) => subject
    _ => ""
  }
}

///|
/// The reason a request was refused by `middleware_jwt_hs256`, expressed as a
/// stable category such as `"expired"`, `"invalid_signature"` or
/// `"malformed"`. Returns `""` when verification succeeded or the middleware
/// was not installed.
///
/// The HTTP response stays generic; this value is intended for logging and
/// metrics, and is available to middleware that wraps the JWT middleware.
pub fn Context::jwt_error(self : Context) -> String {
  match self.state.get(JWT_ERROR_STATE_KEY) {
    Some(reason) => reason
    None => ""
  }
}

///|
/// Stable log category for a verification failure. The client response is
/// intentionally generic, but middleware and tests can record why a token was
/// refused without formatting the error value.
fn jwt_error_code(error : JwtError) -> String {
  match error {
    JwtMalformed(_) => "malformed"
    JwtUnsupportedAlgorithm(_) => "unsupported_algorithm"
    JwtInvalidSignature => "invalid_signature"
    JwtExpired => "expired"
    JwtNotYetValid => "not_yet_valid"
    JwtInvalidClaim(_) => "invalid_claim"
  }
}

///|
/// Middleware that authenticates a bearer JWT signed with HS256.
///
/// The token is read from `Authorization: Bearer <token>` and verified with
/// `verify_jwt_hs256`; on success the claims are stored for
/// `Context::jwt_claims` / `Context::jwt_claim` / `Context::jwt_subject`, and
/// its protected header is available through `Context::jwt_header` /
/// `Context::jwt_header_parameter`. A missing, malformed, expired, not-yet-valid or
/// incorrectly signed token is answered with `401 Unauthorized` and a
/// `WWW-Authenticate: Bearer realm="..."` challenge before the handler runs,
/// including tokens that use an algorithm other than `HS256`.
///
/// `leeway` permits clock skew in seconds, `require_exp` (default `true`)
/// rejects tokens without an `exp` claim, and `realm` is echoed in the
/// challenge. Pass `issuer` and/or `audience` to require the registered claims
/// described by `verify_jwt_hs256`; a mismatch is refused like any other bad
/// token. Keep the secret private and use a high-entropy value; seeing this
/// middleware's source is not a substitute for seeing its configuration.
pub fn middleware_jwt_hs256(
  secret : String,
  realm~ : String = "Restricted",
  leeway~ : Int32 = 0,
  require_exp~ : Bool = true,
  issuer? : String,
  audience? : String,
) -> Middleware {
  let challenge = bearer_auth_challenge(realm)
  let skew = if leeway < 0 { 0 } else { leeway }
  fn(next) {
    fn(ctx) raise {
      let verified : Jwt? = match ctx.bearer_token() {
        Some(token) =>
          Some(
            verify_jwt_hs256(
              token,
              secret,
              leeway=skew,
              require_exp~,
              issuer?,
              audience?,
            ),
          ) catch {
            err => {
              // Keep the reason for logs without exposing it to the client.
              ctx.state.set(JWT_ERROR_STATE_KEY, jwt_error_code(err))
              None
            }
          }
        None => None
      }
      match verified {
        Some(jwt) => {
          ctx.json_state.set(JWT_HEADER_STATE_KEY, jwt.header)
          ctx.json_state.set(JWT_CLAIMS_STATE_KEY, jwt.claims)
          ignore(ctx.state.remove(JWT_ERROR_STATE_KEY))
          next(ctx)
        }
        None => {
          ignore(ctx.json_state.remove(JWT_HEADER_STATE_KEY))
          ignore(ctx.json_state.remove(JWT_CLAIMS_STATE_KEY))
          ctx.file = None
          ctx.response.status = 401
          clear_replaced_body_headers(ctx.response.headers)
          clear_replaced_representation_headers(ctx.response.headers)
          set_header_ignore_case(
            ctx.response.headers,
            "WWW-Authenticate",
            challenge,
          )
          set_header_ignore_case(
            ctx.response.headers,
            "Content-Type",
            "text/plain; charset=utf-8",
          )
          ctx.response.data = None
          ctx.response.body = "401 Unauthorized"
        }
      }
    }
  }
}
