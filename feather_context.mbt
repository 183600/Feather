///|
/// Context state key holding a request body that is not valid UTF-8,
/// base64-encoded. Text handlers keep reading `Request::body`; binary
/// consumers read the untouched bytes through `Context::body_bytes`.
const RAW_BODY_STATE_KEY : String = "__feather_raw_body"

///|
/// Preserve the raw bytes of a request body that UTF-8 could not represent.
///
/// `Request::body` keeps the lossy text, because `@utf8.encode` refuses lone
/// surrogates and would panic if such a body were echoed into a response; the
/// untouched bytes ride along here instead.
fn attach_raw_body(ctx : Context, raw : Bytes?) -> Unit {
  match raw {
    Some(bytes) =>
      if bytes.length() > 0 {
        ctx.state.set(RAW_BODY_STATE_KEY, base64_encode(bytes))
      }
    None => ()
  }
}

///|
/// The request body as bytes, exactly as it arrived.
///
/// A body that is valid UTF-8 round-trips through `Request::body`; a body
/// that is not (image uploads, protobuf, arbitrary binary) comes back byte
/// for byte. Its length is already bounded by `App::max_body_size`.
pub fn Context::body_bytes(self : Context) -> Bytes {
  match self.state.get(RAW_BODY_STATE_KEY) {
    Some(encoded) =>
      match base64_decode(encoded) {
        Some(bytes) => bytes
        None => encode_utf8_lossy(self.request.body.view())
      }
    None => encode_utf8_lossy(self.request.body.view())
  }
}

///|
pub fn Context::json_body(self : Context) -> Json raise HttpError {
  // RFC 8259 requires UTF-8. Decode the exact request bytes rather than the
  // lossy `Request::body` text so invalid byte sequences are rejected instead
  // of quietly becoming U+FFFD and changing the document.
  let bytes = self.body_bytes()
  let text = @utf8.decode(bytes) catch {
    @utf8.Malformed(_) => raise HttpError(400, "invalid JSON body")
  }
  // RFC 8259 allows parsers to ignore a leading UTF-8 BOM, which otherwise
  // arrives as U+FEFF and makes an otherwise valid document fail to parse.
  let body = if text.has_prefix("\u{FEFF}") {
    text[1:].to_owned()
  } else {
    text
  }
  @json.parse(body) catch {
    _ => raise HttpError(400, "invalid JSON body")
  }
}

///|
pub fn[T : @json.FromJson] Context::json_as(
  self : Context,
) -> T raise HttpError {
  @json.from_json(self.json_body()) catch {
    _ => raise HttpError(400, "invalid JSON body")
  }
}

///|
pub fn Context::set(self : Context, key : String, value : String) -> Unit {
  self.state.set(key, value)
}

///|
pub fn Context::get(self : Context, key : String) -> String {
  match self.state.get(key) {
    Some(value) => value
    None => ""
  }
}

///|
/// Whether request state contains `key`, including keys seeded from application
/// state. Unlike `Context::get`, this distinguishes a missing key from one
/// stored with an empty string value.
pub fn Context::has_state(self : Context, key : String) -> Bool {
  self.state.contains(key)
}

///|
/// Remove `key` from request state. Returns whether the key was present.
/// Removing a key seeded from application state only affects this request.
pub fn Context::remove_state(self : Context, key : String) -> Bool {
  match self.state.remove_and_get(key) {
    Some(_) => true
    None => false
  }
}

///|
/// Parameter names mapped to their `param:`-prefixed state keys.
let param_key_cache : Map[String, String] = Map([])

///|
/// Recency ticks for `param_key_cache`.
let param_key_cache_ages : Map[String, Int32] = Map([])

///|
fn param_state_key(name : String) -> String {
  match param_key_cache.get(name) {
    Some(key) => {
      cache_touch(param_key_cache_ages, name)
      key
    }
    None => {
      let key = PARAM_PREFIX + name
      parse_cache_set(param_key_cache, param_key_cache_ages, name, key)
      key
    }
  }
}

///|
pub fn Context::param(self : Context, name : String) -> String {
  if self.state.is_empty() {
    return ""
  }
  match self.state.get(param_state_key(name)) {
    Some(value) => value
    None => ""
  }
}

///|
/// Look up the route parameter `name`, returning `default` when the route did
/// not capture it. Route matching never produces an empty segment, so a
/// parameter that matched has a non-empty value and the fallback is only used
/// for parameters the route does not define.
pub fn Context::param_default(
  self : Context,
  name : String,
  default : String,
) -> String {
  if self.state.is_empty() {
    return default
  }
  match self.state.get(param_state_key(name)) {
    Some(value) => value
    None => default
  }
}

///|
/// Like `Context::param`, but percent-decodes the captured segment.
///
/// Route matching keeps the raw text (so `%2F` cannot act as another path
/// separator), which means `Context::param` returns whatever the client
/// typed. Use this accessor for slugs and ids that should be decoded before
/// display or lookup; `+` is kept as-is because it has no special meaning in a
/// path segment.
pub fn Context::param_decoded(self : Context, name : String) -> String {
  let raw = self.param(name)
  if raw == "" {
    return ""
  }
  decode_url_path(raw.view())
}

///|
pub fn Context::params(self : Context) -> Map[String, String] {
  let result : Map[String, String] = Map([], capacity=4)
  let prefix_length = PARAM_PREFIX.length()
  for key, value in self.state {
    if key.has_prefix(PARAM_PREFIX) {
      result.set(key[prefix_length:].to_owned(), value)
    }
  }
  result
}

///|
/// Whether the matched route captured a parameter named `name`, including a
/// wildcard capture. Unlike `Context::param`, this distinguishes an absent
/// parameter from one whose captured text is empty (a wildcard can match the
/// empty remainder).
pub fn Context::has_param(self : Context, name : String) -> Bool {
  name != "" && self.state.contains(PARAM_PREFIX + name)
}

///|
pub fn Context::status(self : Context, code : Int32) -> Unit {
  self.response.status = code
}

///|
pub fn Context::set_header(
  self : Context,
  key : String,
  value : String,
) -> Unit {
  set_header_ignore_case(self.response.headers, key, value)
}

///|
/// Read a response header, matched case-insensitively. Returns `""` when the
/// header is absent. Useful in middleware that inspects or rewrites headers
/// after calling through to the handler.
pub fn Context::response_header(self : Context, key : String) -> String {
  match get_header_ignore_case(self.response.headers, key) {
    Some(value) => value
    None => ""
  }
}

///|
/// Whether the response already carries `key`, matched case-insensitively.
/// Unlike `Context::response_header`, this distinguishes a header with an empty
/// value from an absent header.
pub fn Context::has_response_header(self : Context, key : String) -> Bool {
  get_header_ignore_case(self.response.headers, key) is Some(_)
}

///|
/// Remove every response header whose name matches `key` case-insensitively
/// and report whether one was present.
pub fn Context::remove_response_header(
  self : Context,
  key : String,
) -> Bool {
  let removed = remove_header_ignore_case(self.response.headers, key)
  // `set_cookie` records a pending cookie in addition to the raw header, and
  // the server sends that array as the authoritative `Set-Cookie` lines.
  // Removing the header must therefore drop those pending cookies too.
  if key.view().equal_ignore_ascii_case("Set-Cookie".view()) &&
    !self.response.cookies.is_empty() {
    self.response.cookies.clear()
    true
  } else {
    removed
  }
}

///|
/// Append `value` to the comma-separated response header `key`, matching the
/// name case-insensitively. When the header is absent it is created; when it
/// is present the new value is joined with `", "`. An empty `value` leaves an
/// existing field untouched (creating an empty field only when the header was
/// absent), so callers can append an optional value unconditionally.
///
/// This is the right helper for list-valued fields such as `Vary`, `Link` or
/// `Warning`. Do not use it for `Set-Cookie`: cookies must stay separate
/// header lines, so use `Context::add_cookie` / `Context::set_cookie` instead.
pub fn Context::append_header(
  self : Context,
  key : String,
  value : String,
) -> Unit {
  if sanitize_response_header_name(key) == "" {
    return
  }
  match get_header_ignore_case(self.response.headers, key) {
    Some(existing) =>
      if existing == "" {
        set_header_ignore_case(self.response.headers, key, value)
      } else if value != "" {
        set_header_ignore_case(
          self.response.headers,
          key,
          existing + ", " + value,
        )
      }
    None => set_header_ignore_case(self.response.headers, key, value)
  }
}

///|
/// Set the response header `key` to `value` only when no spelling of that
/// header is present, and report whether it was set. A header that exists with
/// an empty value still counts as present, so middleware can establish a
/// default without overwriting a handler's deliberate empty value.
pub fn Context::set_header_if_absent(
  self : Context,
  key : String,
  value : String,
) -> Bool {
  if sanitize_response_header_name(key) == "" {
    return false
  }
  if get_header_ignore_case(self.response.headers, key) is Some(_) {
    false
  } else {
    set_header_ignore_case(self.response.headers, key, value)
    true
  }
}

///|
fn Context::set_cache_control_scope(
  self : Context,
  scope : String,
  max_age : Int32,
  immutable : Bool,
) -> Unit {
  let seconds = if max_age > 0 { max_age } else { 0 }
  let value = if immutable {
    "\{scope}, max-age=\{seconds}, immutable"
  } else {
    "\{scope}, max-age=\{seconds}"
  }
  set_header_ignore_case(self.response.headers, "Cache-Control", value)
}

///|
/// Allow shared caches to store the response for `max_age` seconds
/// (`Cache-Control: public, max-age=N`). Negative lifetimes are clamped to
/// zero; pass `immutable=true` to advertise that the representation at this
/// URL never changes while it is fresh.
pub fn Context::cache_public(
  self : Context,
  max_age : Int32,
  immutable~ : Bool = false,
) -> Unit {
  self.set_cache_control_scope("public", max_age, immutable)
}

///|
/// Allow only the end user's private cache to store the response for
/// `max_age` seconds (`Cache-Control: private, max-age=N`). Negative
/// lifetimes are clamped to zero; `immutable` behaves as for
/// `Context::cache_public`.
pub fn Context::cache_private(
  self : Context,
  max_age : Int32,
  immutable~ : Bool = false,
) -> Unit {
  self.set_cache_control_scope("private", max_age, immutable)
}

///|
/// Mark the response as not storable by any cache
/// (`Cache-Control: no-store`).
pub fn Context::no_store(self : Context) -> Unit {
  set_header_ignore_case(self.response.headers, "Cache-Control", "no-store")
}

///|
/// Require caches to revalidate the response before reusing it
/// (`Cache-Control: no-cache`).
pub fn Context::no_cache(self : Context) -> Unit {
  set_header_ignore_case(self.response.headers, "Cache-Control", "no-cache")
}

///|
/// Replace the response's `Cache-Control` field with arbitrary directives.
///
/// This is the escape hatch for policies the typed helpers do not model, such
/// as `public, max-age=60, s-maxage=300, stale-while-revalidate=30`. Control
/// characters are stripped so a caller-supplied value cannot forge another
/// response header. Passing an empty value removes the field.
pub fn Context::cache_control(
  self : Context,
  directives : String,
) -> Unit {
  let cleaned = strip_control_characters(directives)
  let value = trim_ascii_space(cleaned.view()).to_owned()
  if value.is_empty() {
    ignore(remove_header_ignore_case(self.response.headers, "Cache-Control"))
  } else {
    set_header_ignore_case(self.response.headers, "Cache-Control", value)
  }
}

///|
/// Middleware that installs a default `Cache-Control` policy for the responses
/// it wraps.
///
/// The policy is applied after the handler returns, so a handler's own
/// `Cache-Control` value is kept by default. Pass `overwrite=true` to make the
/// middleware authoritative and replace any value the handler set. Because the
/// header is written after the handler, an error escaping the chain is not
/// decorated; install a recovery middleware outside this one when error
/// responses should also carry the policy. The value goes through
/// `Context::cache_control`, so control characters are stripped and an empty
/// value removes the field.
pub fn middleware_cache_control(
  directives : String,
  overwrite~ : Bool = false,
) -> Middleware {
  let cleaned = strip_control_characters(directives)
  let value = trim_ascii_space(cleaned.view()).to_owned()
  fn(next) {
    fn(ctx) raise {
      next(ctx)
      if overwrite || !ctx.has_response_header("Cache-Control") {
        ctx.cache_control(value)
      }
    }
  }
}

///|
/// Middleware that forbids storing the responses it wraps
/// (`Cache-Control: no-store`), without clobbering a more specific value set by
/// the handler. Handy for authenticated pages and API tokens.
pub fn middleware_no_store() -> Middleware {
  middleware_cache_control("no-store")
}

///|
/// Middleware that requires caches to revalidate the responses it wraps
/// (`Cache-Control: no-cache`), without clobbering a value set by the handler.
pub fn middleware_no_cache() -> Middleware {
  middleware_cache_control("no-cache")
}

///|
/// Middleware that lets shared caches store the responses it wraps for
/// `max_age` seconds, mirroring `Context::cache_public`. Negative lifetimes are
/// clamped to zero and `immutable=true` adds the `immutable` directive. A
/// handler's own `Cache-Control` value still wins.
pub fn middleware_cache_public(
  max_age : Int32,
  immutable~ : Bool = false,
) -> Middleware {
  let seconds = if max_age > 0 { max_age } else { 0 }
  let value = if immutable {
    "public, max-age=\{seconds}, immutable"
  } else {
    "public, max-age=\{seconds}"
  }
  middleware_cache_control(value)
}

///|
/// Middleware that lets only the end user's cache store the responses it wraps
/// for `max_age` seconds, mirroring `Context::cache_private`. Negative lifetimes
/// are clamped to zero and `immutable=true` adds the `immutable` directive. A
/// handler's own `Cache-Control` value still wins.
pub fn middleware_cache_private(
  max_age : Int32,
  immutable~ : Bool = false,
) -> Middleware {
  let seconds = if max_age > 0 { max_age } else { 0 }
  let value = if immutable {
    "private, max-age=\{seconds}, immutable"
  } else {
    "private, max-age=\{seconds}"
  }
  middleware_cache_control(value)
}

///|
pub fn Context::text(self : Context, status : Int32, body : String) -> Unit {
  self.file = None
  self.response.status = status
  clear_replaced_body_headers(self.response.headers)
  set_header_ignore_case(
    self.response.headers,
    "Content-Type",
    "text/plain; charset=utf-8",
  )
  self.response.data = None
  self.response.body = body
}

///|
pub fn Context::bytes(
  self : Context,
  status : Int32,
  data : Bytes,
  content_type~ : String = "application/octet-stream",
) -> Unit {
  self.file = None
  self.response.status = status
  clear_replaced_body_headers(self.response.headers)
  set_header_ignore_case(self.response.headers, "Content-Type", content_type)
  self.response.body = ""
  self.response.data = Some(data)
}

///|
pub fn Context::html(self : Context, status : Int32, body : String) -> Unit {
  self.file = None
  self.response.status = status
  clear_replaced_body_headers(self.response.headers)
  set_header_ignore_case(
    self.response.headers,
    "Content-Type",
    "text/html; charset=utf-8",
  )
  self.response.data = None
  self.response.body = body
}

///|
pub fn json_object(data : Map[String, String]) -> Json {
  let object : Map[String, Json] = Map([], capacity=data.length())
  data.each(fn(key, value) { object.set(key, Json::string(value)) })
  Json::object(object)
}

///|
/// Whether a UTF-16 code unit needs a JSON escape (`"`, `\`, or a control
/// character). Matches `@json`'s default string encoding.
#inline
fn json_needs_escape_code(code : UInt16) -> Bool {
  code == '"' || code == '\\' || code < ' '
}

///|
/// Write `value` as a JSON string body (without quotes), escaping exactly like
/// `@json.Json::string(value).stringify()` does by default.
fn json_write_escaped(buf : StringBuilder, value : String) -> Unit {
  let length = value.length()
  let mut run_start = 0
  let mut i = 0
  while i < length {
    let code = value.unsafe_get(i)
    if json_needs_escape_code(code) {
      if run_start < i {
        buf.write_view(value.exact_view(start=run_start, end=i))
      }
      match code {
        '"' => buf.write_string("\\\"")
        '\\' => buf.write_string("\\\\")
        '\n' => buf.write_string("\\n")
        '\r' => buf.write_string("\\r")
        '\b' => buf.write_string("\\b")
        '\t' => buf.write_string("\\t")
        0x0C => buf.write_string("\\f")
        _ => {
          buf.write_string("\\u00")
          buf.write_string(code.to_byte().to_hex())
        }
      }
      run_start = i + 1
    }
    i = i + 1
  }
  if run_start < length {
    buf.write_view(value.exact_view(start=run_start))
  }
}

///|
/// Serialize a flat string map as a JSON object. Keys keep the map's iteration
/// order.
fn json_object_text(data : Map[String, String]) -> String {
  if data.is_empty() {
    return "{}"
  }
  let buf = StringBuilder(size_hint=32)
  buf.write_char('{')
  let mut first = true
  data.each(fn(key, value) {
    if !first {
      buf.write_char(',')
    }
    first = false
    buf.write_char('"')
    json_write_escaped(buf, key)
    buf.write_string("\":\"")
    json_write_escaped(buf, value)
    buf.write_char('"')
  })
  buf.write_char('}')
  buf.to_string()
}

///|
pub fn Context::json_value(self : Context, status : Int32, data : Json) -> Unit {
  self.file = None
  self.response.status = status
  clear_replaced_body_headers(self.response.headers)
  set_header_ignore_case(
    self.response.headers,
    "Content-Type",
    "application/json; charset=utf-8",
  )
  self.response.data = None
  self.response.body = match data {
    Json::Object(members) if members.is_empty() => "{}"
    Json::Array(items) if items.is_empty() => "[]"
    _ => data.stringify()
  }
}

///|
pub fn Context::json(
  self : Context,
  status : Int32,
  data : Map[String, String],
) -> Unit {
  self.file = None
  self.response.status = status
  clear_replaced_body_headers(self.response.headers)
  set_header_ignore_case(
    self.response.headers,
    "Content-Type",
    "application/json; charset=utf-8",
  )
  self.response.data = None
  self.response.body = json_object_text(data)
}

///|
pub fn[T : @json.ToJson] Context::json_of(
  self : Context,
  status : Int32,
  value : T,
) -> Unit {
  self.json_value(status, @json.to_json(value))
}

///|
/// Keep only an origin-form path from a candidate redirect target.
///
/// A leading `//` would be parsed as a protocol-relative URL by browsers, and
/// a backslash is treated as a slash by some of them, so both are rejected
/// rather than rewritten. Fragments are dropped because they identify a place
/// in the returned document, not part of the request to replay.
fn safe_local_redirect_path(candidate : StringView) -> String? {
  if candidate.is_empty() ||
    candidate.unsafe_get(0) != ('/' : UInt16) ||
    candidate.has_prefix("//") ||
    candidate.has_prefix("/\\") ||
    candidate.contains("\\") {
    return None
  }
  let end = match candidate.find("#") {
    Some(index) => index
    None => candidate.length()
  }
  if end == 0 {
    return None
  }
  // Browsers and intermediaries may percent-decode a path before following
  // it. A target such as `/%2f%2fhost` would then become a protocol-relative
  // URL, and `/%5chost` a backslash spelling of it, so apply the same checks
  // to the decoded path rather than only to the raw request target.
  let path = candidate[:end]
  let path_end = match path.find("?") {
    Some(index) => index
    None => path.length()
  }
  let decoded_path = decode_url_path(path[:path_end])
  let decoded_view = decoded_path.view()
  if decoded_view.has_prefix("//") || decoded_view.contains("\\") {
    return None
  }
  let mut i = 0
  while i < decoded_view.length() {
    let code = decoded_view.unsafe_get(i).to_int()
    if code < 0x20 || code == 0x7F {
      return None
    }
    i = i + 1
  }
  Some(path.to_owned())
}

///|
/// Turn a `Referer` into a local redirect target, or `None` when it does not
/// name this host or cannot be parsed safely.
///
/// The result is always an origin-form path on the current host, even when the
/// referer was an absolute URL. That is what keeps `Context::redirect_back`
/// from becoming an open redirect: another origin is rejected, and a matching
/// origin contributes only its path and query.
fn local_referer_target(referer : String, authority : String) -> String? {
  let raw = trim_ascii_space(referer.view()).to_owned()
  if raw.is_empty() {
    return None
  }
  let clean = strip_control_characters(raw)
  if clean != raw {
    return None
  }
  let view = clean.view()
  if view.has_prefix("/") {
    return safe_local_redirect_path(view)
  }
  let scheme_length = if starts_with_ignore_ascii_case(
    view,
    "http://".view(),
  ) {
    7
  } else if starts_with_ignore_ascii_case(view, "https://".view()) {
    8
  } else {
    return None
  }
  let rest = view[scheme_length:]
  let mut end = 0
  while end < rest.length() {
    let code = rest.unsafe_get(end)
    if code == ('/' : UInt16) ||
      code == ('?' : UInt16) ||
      code == ('#' : UInt16) {
      break
    }
    end = end + 1
  }
  let host_part = rest[:end]
  if host_part.is_empty() {
    return None
  }
  let expected = match host_authority_host(authority.view()) {
    Some(host) => host
    None => return None
  }
  let actual = match host_authority_host(host_part) {
    Some(host) => host
    None => return None
  }
  if !expected.view().equal_ignore_ascii_case(actual.view()) {
    return None
  }
  let tail = rest[end:]
  if tail.is_empty() {
    return Some("/")
  }
  let first = tail.unsafe_get(0)
  if first == ('#' : UInt16) {
    // A fragment-only referer points into the current document, not at a
    // different path to return to.
    return Some("/")
  }
  if first == ('?' : UInt16) {
    let candidate = "/" + tail.to_owned()
    return safe_local_redirect_path(candidate.view())
  }
  safe_local_redirect_path(tail)
}

///|
/// Redirect back to the page named by the request's `Referer`.
///
/// The default is `303 See Other`, the right status after a form submission.
/// Only a local target is used: an absolute referer is reduced to its path and
/// query, and a referer naming another host, using a non-HTTP scheme, carrying
/// control characters, or posing as a protocol-relative URL is ignored in
/// favour of `fallback`. This keeps the helper safe against open-redirect
/// abuse when the `Referer` header is attacker-controlled.
pub fn Context::redirect_back(
  self : Context,
  status~ : Int32 = 303,
  fallback~ : String = "/",
) -> Unit {
  let target = match local_referer_target(
    self.header("Referer"),
    self.forwarded_authority(),
  ) {
    Some(target) => target
    None => if fallback == "" { "/" } else { fallback }
  }
  self.redirect(status, target)
}

///|
pub fn Context::redirect(
  self : Context,
  status : Int32,
  location : String,
) -> Unit {
  self.file = None
  self.response.status = status
  clear_replaced_body_headers(self.response.headers)
  clear_replaced_representation_headers(self.response.headers)
  // A redirect has no body, so a representation type prepared for an earlier
  // response must not leak into it.
  ignore(remove_header_ignore_case(self.response.headers, "Content-Type"))
  set_header_ignore_case(
    self.response.headers,
    "Location",
    strip_control_characters(location),
  )
  self.response.data = None
  self.response.body = ""
}

///|
pub fn Context::no_content(self : Context) -> Unit {
  self.file = None
  self.response.status = 204
  self.response.body = ""
  self.response.data = None
  ignore(remove_header_ignore_case(self.response.headers, "Content-Type"))
  clear_replaced_body_headers(self.response.headers)
  clear_replaced_representation_headers(self.response.headers)
}

///|
pub fn Context::get_method(self : Context) -> String {
  self.request.method
}

///|
pub fn Context::get_path(self : Context) -> String {
  self.request.path
}

///|
/// The path component of the request target, without the query string or a
/// fragment. The spelling is preserved (including percent escapes), so a
/// signature or access-log line can use it exactly as the client sent it.
///
/// `Context::get_path` returns the whole request target; use this helper when
/// only the routing path is wanted.
pub fn Context::pathname(self : Context) -> String {
  clean_path_view(self.request.path).to_owned()
}

///|
/// The raw query string of the request target, without the leading `?` or a
/// trailing fragment.
///
/// Unlike `Context::queries` / `Context::query_values`, this preserves the
/// original order, duplicate keys and percent-encoding. It is the right input
/// for signature verification and for forwarding a request unchanged. Returns
/// `""` when the target carries no query.
pub fn Context::query_string(self : Context) -> String {
  match path_query_index(self.request.path) {
    Some(index) => query_source_view(self.request.path, index).to_owned()
    None => ""
  }
}

///|
/// The registered pattern of the route that matched the request, with `:param`
/// and `*wildcard` segments kept in place (for example `/users/:id`). Returns
/// `""` when no ordinary route matched, including fallback and static-file
/// responses.
///
/// This is the stable route identity middlewares should use for logging and
/// metrics; `Context::get_path`, by contrast, is the concrete request target.
pub fn Context::route_pattern(self : Context) -> String {
  match self.state.get(ROUTE_PATTERN_STATE_KEY) {
    Some(value) => value
    None => ""
  }
}

///|
/// The method under which the matched route was registered. Like
/// `Context::route_pattern`, this is empty when no ordinary route matched.
/// `HEAD` requests served by a `GET` route report `"GET"`, because that is the
/// route's registered method.
pub fn Context::route_method(self : Context) -> String {
  match self.state.get(ROUTE_METHOD_STATE_KEY) {
    Some(value) => value
    None => ""
  }
}

///|
/// The name under which the matched route was registered with
/// `App::route_named`, `RouteGroup::route_named` or `Router::add_named_route`.
/// Returns `""` when the route is unnamed or when no ordinary route matched.
///
/// This is the companion of `Context::route_pattern` / `Context::route_method`
/// for metrics grouped by named route, and it follows the same `HEAD`-to-`GET`
/// fallback as `Context::route_method`.
pub fn Context::route_name(self : Context) -> String {
  match self.state.get(ROUTE_NAME_STATE_KEY) {
    Some(value) => value
    None => ""
  }
}

