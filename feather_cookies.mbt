///|
/// The parsed `Cookie` header, keyed by name. Callers receive their own copy,
/// so mutating the result cannot disturb a later request that carries the same
/// header and hits the parse cache.
pub fn Context::cookies(self : Context) -> Map[String, String] {
  let header = self.header("Cookie")
  if header == "" {
    return Map([])
  }
  cookie_map_lookup(header).copy()
}

///|
/// All cookies, keyed by name, with every repeated value preserved in header
/// order. Unlike `Context::cookies`, which keeps the first value of a repeated
/// cookie, this lets a caller enumerate all values.
///
/// Both the map and its arrays are fresh copies, so mutating the result cannot
/// disturb a later request that carries the same header.
pub fn Context::cookies_all(
  self : Context,
) -> Map[String, Array[String]] {
  let header = self.header("Cookie")
  if header == "" {
    return Map([])
  }
  copy_values_map(cookie_multi_lookup(header))
}

///|
/// Every value of cookie `name`, in header order. Returns an empty array when
/// the header is absent, the name is invalid, or the cookie is not present.
/// The result is a fresh array, so mutating it cannot disturb a later request.
pub fn Context::cookie_values(
  self : Context,
  name : String,
) -> Array[String] {
  if name == "" {
    return []
  }
  let lookup = sanitize_cookie_token(name, true)
  if lookup == "" {
    return []
  }
  let header = self.header("Cookie")
  if header == "" {
    return []
  }
  match cookie_multi_lookup(header).get(lookup) {
    Some(values) => values.copy()
    None => []
  }
}

///|
/// Whether the `Cookie` header carries `name`. Unlike `Context::cookie`, this
/// distinguishes an absent cookie from one that is present with an empty value
/// (`name=`).
pub fn Context::has_cookie(self : Context, name : String) -> Bool {
  if name == "" {
    return false
  }
  let lookup = sanitize_cookie_token(name, true)
  if lookup == "" {
    return false
  }
  let header = self.header("Cookie")
  if header == "" {
    return false
  }
  cookie_map_lookup(header).contains(lookup)
}

///|
pub fn Context::cookie(self : Context, name : String) -> String? {
  if name == "" {
    return None
  }
  // `set_cookie` stores the sanitized name, so look up the same spelling to
  // keep the write and read sides symmetric.
  let lookup = sanitize_cookie_token(name, true)
  if lookup == "" {
    return None
  }
  let header = self.header("Cookie")
  if header == "" {
    return None
  }
  match last_cookie_header.val {
    Some(cached_header) =>
      if physical_equal(cached_header, header) {
        match last_cookie_map.val {
          Some(cached_map) => return cached_map.get(lookup)
          None => ()
        }
      }
    None => ()
  }
  match cookies_cache.get(header) {
    Some(cached) => {
      cache_touch(cookies_cache_ages, header)
      last_cookie_header.val = Some(header)
      last_cookie_map.val = Some(cached)
      cached.get(lookup)
    }
    None => {
      let parsed = parse_cookie_map(header.view())
      if header.length() <= PARSE_CACHE_MAX_KEY {
        parse_cache_set(cookies_cache, cookies_cache_ages, header, parsed)
      }
      last_cookie_header.val = Some(header)
      last_cookie_map.val = Some(parsed)
      parsed.get(lookup)
    }
  }
}

///|
/// Drop unpaired UTF-16 surrogates, keeping valid surrogate pairs intact. Such
/// lone code units cannot be encoded as UTF-8 and would otherwise abort when a
/// header or cookie is written.
fn drop_lone_surrogates(value : String) -> String {
  let view = value.view()
  let length = view.length()
  let mut i = 0
  let mut needs_clean = false
  while i < length {
    let unit = view.unsafe_get(i)
    if unit.is_leading_surrogate() {
      if i + 1 < length && view.unsafe_get(i + 1).is_trailing_surrogate() {
        i = i + 2
        continue
      }
      needs_clean = true
      break
    } else if unit.is_trailing_surrogate() {
      needs_clean = true
      break
    }
    i = i + 1
  }
  if !needs_clean {
    return value
  }
  let builder = StringBuilder(size_hint=length)
  let mut index = 0
  while index < length {
    let unit = view.unsafe_get(index)
    if unit.is_leading_surrogate() {
      if index + 1 < length &&
        view.unsafe_get(index + 1).is_trailing_surrogate() {
        builder.write_char(unit.to_int().unsafe_to_char())
        builder.write_char(
          view.unsafe_get(index + 1).to_int().unsafe_to_char(),
        )
        index = index + 2
      } else {
        index = index + 1
      }
    } else if unit.is_trailing_surrogate() {
      index = index + 1
    } else {
      builder.write_char(unit.to_int().unsafe_to_char())
      index = index + 1
    }
  }
  builder.to_string()
}

///|
fn strip_control_characters(value : String) -> String {
  let value = drop_lone_surrogates(value)
  let view = value.view()
  let length = view.length()
  let mut i = 0
  let mut needs_clean = false
  while i < length {
    let code = view.unsafe_get(i).to_int()
    if code < 0x20 || code == 0x7F {
      needs_clean = true
      break
    }
    i = i + 1
  }
  if !needs_clean {
    return value
  }
  let builder = StringBuilder(size_hint=length)
  let mut index = 0
  while index < length {
    let code = view.unsafe_get(index).to_int()
    if code >= 0x20 && code != 0x7F {
      builder.write_char(code.unsafe_to_char())
    }
    index = index + 1
  }
  builder.to_string()
}

///|
/// Whether `unit` is an RFC 6265 cookie-name character.
///
/// A cookie name is an HTTP `token`: visible ASCII except for the `separators`
/// set from RFC 2616, which includes whitespace, `=`, `;`, `,`, quotes,
/// slashes, brackets and braces. Dropping anything else keeps a caller-supplied
/// name from producing an invalid or ambiguous `Set-Cookie` field.
fn is_cookie_name_character(unit : UInt16) -> Bool {
  let code = unit.to_int()
  if code < 0x21 || code > 0x7E {
    return false
  }
  !(unit == ('(' : UInt16) ||
    unit == (')' : UInt16) ||
    unit == ('<' : UInt16) ||
    unit == ('>' : UInt16) ||
    unit == ('@' : UInt16) ||
    unit == (',' : UInt16) ||
    unit == (';' : UInt16) ||
    unit == (':' : UInt16) ||
    unit == ('\\' : UInt16) ||
    unit == ('"' : UInt16) ||
    unit == ('/' : UInt16) ||
    unit == ('[' : UInt16) ||
    unit == (']' : UInt16) ||
    unit == ('?' : UInt16) ||
    unit == ('=' : UInt16) ||
    unit == ('{' : UInt16) ||
    unit == ('}' : UInt16))
}

///|
/// Whether `unit` is an RFC 6265 cookie-value character.
///
/// `cookie-octet` excludes whitespace, control characters, `"`, `,`, `;` and
/// `\`. `=` and other ASCII punctuation are valid inside a value, which keeps
/// base64 padding intact. Spaces and non-ASCII text are retained to preserve
/// the existing cookie-value behaviour; they cannot forge another header line
/// once control characters are removed.
fn is_cookie_value_character(unit : UInt16) -> Bool {
  let code = unit.to_int()
  code >= 0x20 &&
  code != 0x7F &&
  unit != (',' : UInt16) &&
  unit != (';' : UInt16) &&
  unit != ('"' : UInt16) &&
  unit != ('\\' : UInt16)
}

///|
/// Whether `unit` may not appear in a cookie name or value.
///
/// `name_mode` selects the stricter HTTP token grammar for cookie names; the
/// value path only rejects characters that break the `cookie-octet` grammar.
fn is_cookie_character_unsafe(unit : UInt16, name_mode : Bool) -> Bool {
  if name_mode {
    !is_cookie_name_character(unit)
  } else {
    !is_cookie_value_character(unit)
  }
}

///|
/// Drop characters that are invalid or dangerous in a cookie name/value.
fn sanitize_cookie_token(value : String, name_mode : Bool) -> String {
  let value = drop_lone_surrogates(value)
  let view = value.view()
  let length = view.length()
  let mut i = 0
  let mut needs_clean = false
  while i < length {
    if is_cookie_character_unsafe(view.unsafe_get(i), name_mode) {
      needs_clean = true
      break
    }
    i = i + 1
  }
  if !needs_clean {
    return value
  }
  let builder = StringBuilder(size_hint=length)
  let mut index = 0
  while index < length {
    let unit = view.unsafe_get(index)
    if !is_cookie_character_unsafe(unit, name_mode) {
      builder.write_char(unit.to_int().unsafe_to_char())
    }
    index = index + 1
  }
  builder.to_string()
}

///|
/// Drop characters that would break a cookie attribute value, such as the
/// `;` that separates the attributes in a `Set-Cookie` header.
fn sanitize_cookie_attribute(value : String) -> String {
  let value = drop_lone_surrogates(value)
  let view = value.view()
  let length = view.length()
  let mut i = 0
  let mut needs_clean = false
  while i < length {
    let unit = view.unsafe_get(i)
    let code = unit.to_int()
    if code < 0x20 ||
      code == 0x7F ||
      unit == (';' : UInt16) ||
      unit == (',' : UInt16) {
      needs_clean = true
      break
    }
    i = i + 1
  }
  if !needs_clean {
    return value
  }
  let builder = StringBuilder(size_hint=length)
  let mut index = 0
  while index < length {
    let unit = view.unsafe_get(index)
    let code = unit.to_int()
    if !(code < 0x20 ||
      code == 0x7F ||
      unit == (';' : UInt16) ||
      unit == (',' : UInt16)) {
      builder.write_char(code.unsafe_to_char())
    }
    index = index + 1
  }
  builder.to_string()
}

///|
/// Restrict a cookie `Domain` attribute to the characters that can appear in
/// a host name or an IP literal.
fn sanitize_cookie_domain(value : String) -> String {
  let view = value.view()
  let length = view.length()
  let builder = StringBuilder(size_hint=length)
  let mut i = 0
  while i < length {
    let unit = view.unsafe_get(i)
    let code = unit.to_int()
    let keep = (code >= 'a' && code <= 'z') ||
      (code >= 'A' && code <= 'Z') ||
      (code >= '0' && code <= '9') ||
      unit == ('.' : UInt16) ||
      unit == ('-' : UInt16) ||
      unit == ('_' : UInt16) ||
      unit == (':' : UInt16) ||
      unit == ('[' : UInt16) ||
      unit == (']' : UInt16)
    if keep {
      builder.write_char(code.unsafe_to_char())
    }
    i = i + 1
  }
  builder.to_string()
}

///|
/// Canonical spelling of a valid `SameSite` attribute value, or `None` when
/// the value is not one of the three tokens browsers understand.
fn canonical_same_site(value : String) -> String? {
  let trimmed = trim_ascii_space(value.view())
  if trimmed.equal_ignore_ascii_case("strict".view()) {
    Some("Strict")
  } else if trimmed.equal_ignore_ascii_case("lax".view()) {
    Some("Lax")
  } else if trimmed.equal_ignore_ascii_case("none".view()) {
    Some("None")
  } else {
    None
  }
}

///|
/// Build a cookie with every name, value and attribute sanitized, so caller
/// input cannot forge additional `Set-Cookie` attributes or header bytes.
fn build_cookie(
  name : String,
  value : String,
  path? : String,
  max_age? : Int64,
  expires? : Int64,
  domain? : String,
  same_site? : String,
  http_only : Bool,
  secure : Bool,
  partitioned : Bool,
) -> @http.Cookie {
  let clean_path = match path {
    Some(value) => Some(sanitize_cookie_attribute(value))
    None => None
  }
  let expires_raw = match expires {
    Some(seconds) => Some(format_http_date(seconds))
    None => None
  }
  // RFC 6265 `delta-seconds` is non-negative. A negative caller value still
  // means "expire now", so render it as the canonical zero rather than an
  // invalid negative `Max-Age`.
  let clean_max_age = match max_age {
    Some(seconds) => Some(if seconds < 0L { 0L } else { seconds })
    None => None
  }
  let clean_domain = match domain {
    Some(value) => {
      let cleaned = sanitize_cookie_domain(value)
      if cleaned == "" {
        None
      } else {
        Some(cleaned)
      }
    }
    None => None
  }
  let extensions : Array[String] = []
  match same_site {
    Some(value) =>
      match canonical_same_site(value) {
        Some(token) => extensions.push("SameSite=" + token)
        None => ()
      }
    None => ()
  }
  if partitioned {
    extensions.push("Partitioned")
  }
  @http.Cookie(
    sanitize_cookie_token(name, true),
    sanitize_cookie_token(value, false),
    path?=clean_path,
    expires_raw?,
    max_age?=clean_max_age,
    domain?=clean_domain,
    http_only~,
    secure~,
    extensions~,
  )
}

///|
pub fn Context::add_cookie(
  self : Context,
  name : String,
  value : String,
  path? : String,
  max_age? : Int64,
  expires? : Int64,
  domain? : String,
  same_site? : String,
  http_only~ : Bool = false,
  secure~ : Bool = false,
  partitioned~ : Bool = false,
) -> Unit {
  let cookie = build_cookie(
    name,
    value,
    path?,
    max_age?,
    expires?,
    domain?,
    same_site?,
    http_only,
    secure,
    partitioned,
  )
  if cookie.name == "" {
    return
  }
  self.response.cookies.push(cookie)
}

///|
fn render_cookie(cookie : @http.Cookie) -> String {
  let builder = StringBuilder(
    size_hint=(cookie.name.length() + cookie.value.length() + 64) * 2,
  )
  builder.write_string(cookie.name)
  builder.write_char('=')
  builder.write_string(cookie.value)
  match cookie.path {
    Some(path) => {
      builder.write_string("; Path=")
      builder.write_string(path)
    }
    None => ()
  }
  match cookie.expires_raw {
    Some(expires) => {
      builder.write_string("; Expires=")
      builder.write_string(expires)
    }
    None => ()
  }
  match cookie.max_age {
    Some(max_age) => {
      builder.write_string("; Max-Age=")
      builder.write_string(max_age.to_string())
    }
    None => ()
  }
  match cookie.domain {
    Some(domain) => {
      builder.write_string("; Domain=")
      builder.write_string(domain)
    }
    None => ()
  }
  if cookie.http_only {
    builder.write_string("; HttpOnly")
  }
  if cookie.secure {
    builder.write_string("; Secure")
  }
  for extension in cookie.extensions {
    builder.write_string("; ")
    builder.write_string(extension)
  }
  builder.to_string()
}

///|
pub fn Context::set_cookie(
  self : Context,
  name : String,
  value : String,
  path? : String,
  max_age? : Int64,
  expires? : Int64,
  domain? : String,
  same_site? : String,
  http_only~ : Bool = false,
  secure~ : Bool = false,
  partitioned~ : Bool = false,
) -> Unit {
  let cookie = build_cookie(
    name,
    value,
    path?,
    max_age?,
    expires?,
    domain?,
    same_site?,
    http_only,
    secure,
    partitioned,
  )
  if cookie.name == "" {
    return
  }
  set_header_ignore_case(
    self.response.headers,
    "Set-Cookie",
    render_cookie(cookie),
  )
  self.response.cookies.push(cookie)
}

///|
pub fn Context::clear_cookie(
  self : Context,
  name : String,
  path? : String,
  domain? : String,
  same_site? : String,
  http_only~ : Bool = false,
  secure~ : Bool = false,
  partitioned~ : Bool = false,
) -> Unit {
  // Deletion keeps the attributes that are part of a cookie's storage key,
  // most notably `Partitioned` for CHIPS cookies, so the browser removes the
  // same cookie that was set earlier.
  self.set_cookie(
    name,
    "",
    path?,
    max_age=0L,
    domain?,
    same_site?,
    http_only~,
    secure~,
    partitioned~,
  )
}

