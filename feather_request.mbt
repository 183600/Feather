///|
pub fn Context::header(self : Context, key : String) -> String {
  match get_header_ignore_case(self.request.headers, key) {
    Some(value) => value
    None => ""
  }
}

///|
/// Look up request header `key`, returning `default` when the header is absent.
/// Matching is case-insensitive like `Context::header`. A header present with
/// an empty value is returned as-is instead of being replaced by `default`.
pub fn Context::header_default(
  self : Context,
  key : String,
  default : String,
) -> String {
  match get_header_ignore_case(self.request.headers, key) {
    Some(value) => value
    None => default
  }
}

///|
/// Whether the request carries `key`, matched case-insensitively. Unlike
/// `Context::header`, this distinguishes a header with an empty value from an
/// absent header.
pub fn Context::has_header(self : Context, key : String) -> Bool {
  get_header_ignore_case(self.request.headers, key) is Some(_)
}

///|
/// Parsed host names keyed by the trimmed `Host` header value.
let host_cache : Map[StringView, String] = Map([])

///|
/// Recency ticks for `host_cache`.
let host_cache_ages : Map[StringView, Int32] = Map([])

///|
/// The host name from the `Host` header, without the port.
pub fn Context::host(self : Context) -> String {
  let authority = trim_ascii_space(self.header("Host").view())
  if authority == "" {
    return ""
  }
  match host_cache.get(authority) {
    Some(cached) => {
      cache_touch(host_cache_ages, authority)
      return cached
    }
    None => ()
  }
  // Validate the authority before truncating it: otherwise a malformed value
  // such as `[::1]evil` or `example.com:bad` would turn into an apparently
  // valid host and could be trusted by callers that use the parsed value for
  // host-based decisions.
  let host = match host_authority_host(authority) {
    None => ""
    Some(_) =>
      if authority.unsafe_get(0) == ('[' : UInt16) {
        match authority.find("]") {
          Some(index) => authority[:index + 1].to_owned()
          None => ""
        }
      } else {
        match authority.find(":") {
          Some(index) => authority[:index].to_owned()
          None => authority.to_owned()
        }
      }
  }
  if authority.length() <= PARSE_CACHE_MAX_KEY {
    parse_cache_set(host_cache, host_cache_ages, authority, host)
  }
  host
}

///|
/// Unescape an RFC 7239 parameter value enclosed in double quotes. Values
/// that are not quoted are returned unchanged; anything after the closing
/// quote is ignored.
fn unquote_forwarded_value(raw : StringView) -> String {
  if raw.length() < 2 || raw.unsafe_get(0) != ('"' : UInt16) {
    return raw.to_owned()
  }
  let length = raw.length()
  let builder = StringBuilder(size_hint=length)
  let mut i = 1
  while i < length {
    let unit = raw.unsafe_get(i)
    if unit == ('\\' : UInt16) && i + 1 < length {
      builder.write_char(raw.unsafe_get(i + 1).to_int().unsafe_to_char())
      i = i + 2
    } else if unit == ('"' : UInt16) {
      break
    } else {
      builder.write_char(unit.to_int().unsafe_to_char())
      i = i + 1
    }
  }
  builder.to_string()
}

///|
/// Value of parameter `name` in the first element of an RFC 7239 `Forwarded`
/// header, for example `host` in `for=192.0.2.60;host="example.com:8443"`.
///
/// Parameter names are matched case-insensitively and quoted values are
/// unescaped. Later elements describe further proxies, so only the first
/// element is inspected. Returns `None` when the parameter is absent or
/// empty.
fn forwarded_first_param(header : StringView, name : StringView) -> String? {
  let length = header.length()
  let mut element_end = length
  let mut i = 0
  let mut in_quotes = false
  while i < length {
    let unit = header.unsafe_get(i)
    if in_quotes && unit == ('\\' : UInt16) && i + 1 < length {
      i = i + 2
      continue
    }
    if unit == ('"' : UInt16) {
      in_quotes = !in_quotes
    } else if unit == (',' : UInt16) && !in_quotes {
      element_end = i
      break
    }
    i = i + 1
  }
  forwarded_element_param(header[:element_end], name)
}

///|
/// Value of parameter `name` in a single element of an RFC 7239 `Forwarded`
/// header, including the empty string when the parameter is present but
/// carries no value.
///
/// Parameter names are matched case-insensitively and quoted values are
/// unescaped. Returns `None` only when the parameter is absent, which lets the
/// trusted-proxy path distinguish an addressless `for=` node from a header
/// that never mentions `for` at all.
fn forwarded_element_param_value(
  element : StringView,
  name : StringView,
) -> String? {
  let mut pos = 0
  while pos < element.length() {
    let mut end = pos
    let mut quoted = false
    while end < element.length() {
      let unit = element.unsafe_get(end)
      if quoted && unit == ('\\' : UInt16) && end + 1 < element.length() {
        end = end + 2
        continue
      }
      if unit == ('"' : UInt16) {
        quoted = !quoted
      } else if unit == (';' : UInt16) && !quoted {
        break
      }
      end = end + 1
    }
    let mut eq = pos
    while eq < end && element.unsafe_get(eq) != ('=' : UInt16) {
      eq = eq + 1
    }
    if eq < end {
      let key = trim_ascii_space(element[pos:eq])
      if key.equal_ignore_ascii_case(name) {
        let unquoted = unquote_forwarded_value(
          trim_ascii_space(element[eq + 1:end]),
        )
        let value = trim_ascii_space(unquoted.view())
        return Some(value.to_owned())
      }
    }
    pos = end + 1
  }
  None
}

///|
/// Value of parameter `name` in a single element of an RFC 7239 `Forwarded`
/// header, for example `host` in `for=192.0.2.60;host="example.com:8443"`.
///
/// Parameter names are matched case-insensitively and quoted values are
/// unescaped. Returns `None` when the parameter is absent or empty.
fn forwarded_element_param(element : StringView, name : StringView) -> String? {
  match forwarded_element_param_value(element, name) {
    Some(value) => if value.is_empty() { None } else { Some(value) }
    None => None
  }
}

///|
/// Normalize an RFC 7239 `for=` node identifier to a client address: an
/// optional port is dropped and IPv6 literals keep their brackets, matching
/// `Context::ip`. Obfuscated (`_...`), `unknown`, and malformed nodes carry no
/// address, so they report `None`.
fn normalize_forwarded_for(value : StringView) -> String? {
  if value.is_empty() ||
    value.equal_ignore_ascii_case("unknown".view()) ||
    value.unsafe_get(0) == ('_' : UInt16) {
    return None
  }
  if value.unsafe_get(0) == ('[' : UInt16) {
    // Reuse the authority validator so a malformed literal such as
    // `[::1]junk`, `[::1]:bad`, or `[not-an-ip]` cannot be truncated into a
    // trusted client address.
    return host_authority_host(value)
  }
  let length = value.length()
  let mut i = 0
  let mut colons = 0
  let mut last_colon = -1
  while i < length {
    if value.unsafe_get(i) == (':' : UInt16) {
      colons = colons + 1
      last_colon = i
    }
    i = i + 1
  }
  // A node identifier is an IPv4address, a bracketed IPv6address, `unknown`
  // or an obfuscated `_...` name. A single colon separates an IPv4 address
  // from its port; several colons mean a bare IPv6 address. Anything else
  // (a host name, an out-of-range octet, ...) is not an address and must stay
  // addressless so trusted-hop counting cannot report client-chosen text.
  if colons == 0 {
    if !valid_ipv4_literal(value) {
      return None
    }
    return Some(value.to_owned())
  }
  if colons == 1 {
    if last_colon <= 0 {
      return None
    }
    let host = value[:last_colon]
    // `unknown` is a node name, not an address, even when it carries a port.
    if host.equal_ignore_ascii_case("unknown".view()) {
      return None
    }
    if !valid_ipv4_literal(host) ||
      !valid_host_port(value[last_colon + 1:]) {
      return None
    }
    return Some(host.to_owned())
  }
  // Several colons without brackets are a bare IPv6 literal, so validate it
  // instead of trusting an arbitrary client-chosen string as an address.
  if !valid_bracketed_host(value) {
    return None
  }
  Some(value.to_owned())
}

///|
/// Whether `value` is a syntactically valid URI scheme (RFC 3986 §3.1).
/// Forwarded protocol values are client-controlled, so a malformed value must
/// not be spliced into `Context::full_url`.
fn valid_url_scheme(value : StringView) -> Bool {
  let length = value.length()
  if length == 0 {
    return false
  }
  let first = value.unsafe_get(0).to_int()
  if !((first >= 65 && first <= 90) || (first >= 97 && first <= 122)) {
    return false
  }
  let mut i = 1
  while i < length {
    if !is_uri_scheme_character(value.unsafe_get(i).to_int()) {
      return false
    }
    i = i + 1
  }
  true
}

///|
/// Whether `value` is a scheme a request to this HTTP server can actually
/// use. Forwarded protocol headers are client-controlled, so a syntactically
/// valid but unrelated scheme such as `javascript` or `file` must not be
/// spliced into an absolute URL by `Context::full_url`.
fn is_http_request_scheme(value : StringView) -> Bool {
  value.equal_ignore_ascii_case("http".view()) ||
  value.equal_ignore_ascii_case("https".view())
}

///|
/// Validate an authority (host plus optional port) before echoing a forwarded
/// value. The original spelling is preserved, including an explicit port.
fn valid_forwarded_authority(value : StringView) -> String? {
  let authority = trim_ascii_space(value)
  if authority.is_empty() {
    return None
  }
  match host_authority_host(authority) {
    Some(_) => Some(authority.to_owned())
    None => None
  }
}

///|
/// The URL scheme of the request, honoring the RFC 7239 `Forwarded` `proto=`
/// parameter first, then `X-Forwarded-Proto`, and defaulting to `"http"`.
/// Malformed forwarded values are ignored so `Context::full_url` cannot be
/// steered into another scheme.
pub fn Context::protocol(self : Context) -> String {
  let forwarded = self.header("Forwarded")
  if forwarded != "" {
    match forwarded_first_param(forwarded.view(), "proto".view()) {
      Some(value) =>
        if valid_url_scheme(value.view()) &&
          is_http_request_scheme(value.view()) {
          return value
        }
      None => ()
    }
  }
  let proto = trim_ascii_space(self.header("X-Forwarded-Proto").view())
  if proto != "" {
    let value = match proto.find(",") {
      Some(index) => trim_ascii_space(proto[:index])
      None => proto
    }
    if valid_url_scheme(value.view()) &&
      is_http_request_scheme(value.view()) {
      return value.to_owned()
    }
  }
  "http"
}

///|
/// Whether the request is considered to arrive over HTTPS.
pub fn Context::is_secure(self : Context) -> Bool {
  self.protocol().view().equal_ignore_ascii_case("https".view())
}

///|
/// The authority (host and optional port) to use in absolute URLs, honoring
/// the RFC 7239 `Forwarded` `host=` parameter first, then the first value of
/// `X-Forwarded-Host`, then the `Host` header. Returns `""` when none is
/// present. Use `Context::host` for the port-less host name.
pub fn Context::forwarded_authority(self : Context) -> String {
  let forwarded = self.header("Forwarded")
  if forwarded != "" {
    match forwarded_first_param(forwarded.view(), "host".view()) {
      Some(value) =>
        match valid_forwarded_authority(value.view()) {
          Some(authority) => return authority
          None => ()
        }
      None => ()
    }
  }
  let xfh = trim_ascii_space(self.header("X-Forwarded-Host").view())
  if xfh != "" {
    let first = match xfh.find(",") {
      Some(index) => trim_ascii_space(xfh[:index])
      None => xfh
    }
    match valid_forwarded_authority(first) {
      Some(authority) => return authority
      None => ()
    }
  }
  match valid_forwarded_authority(self.header("Host").view()) {
    Some(authority) => authority
    None => ""
  }
}

///|
/// The full URL of the request, for example `https://example.com/users/1?q=x`.
///
/// Honors `Forwarded`/`X-Forwarded-Proto` and
/// `Forwarded`/`X-Forwarded-Host` when building the URL, so links stay
/// correct behind a reverse proxy.
pub fn Context::full_url(self : Context) -> String {
  let raw_path = self.request.path
  let path = match raw_path.find("#") {
    Some(index) => raw_path[:index].to_owned()
    None => raw_path
  }
  // Asterisk-form names the whole server, not a URL path.
  if path == "*" {
    return path
  }
  let authority = self.forwarded_authority()
  if authority.is_empty() {
    return path
  }
  // With an authority the result is an absolute URL, whose path must be
  // absolute-path (and not concatenate onto the authority).
  let path = if path.is_empty() {
    "/"
  } else if path.has_prefix("/") {
    path
  } else {
    "/" + path
  }
  let scheme = self.protocol()
  let builder = StringBuilder(
    size_hint=scheme.length() + authority.length() + path.length() + 3,
  )
  builder.write_string(scheme)
  builder.write_string("://")
  builder.write_string(authority)
  builder.write_string(path)
  builder.to_string()
}

///|
/// Address of the client that opened the connection, without the ephemeral
/// port. When the request is served by `App::serve` this is the peer IP
/// recorded by the server; contexts built by hand report `"127.0.0.1"` unless
/// `remote_addr` was set in the state.
///
/// When the application declares trusted proxies with `App::trust_proxy`, the
/// address of the real client is reported instead: the forwarded chain is
/// walked `hops` steps back from the peer, so one trusted proxy reports the
/// address that proxy saw. A selected hop that recorded no address falls back
/// to the peer address. Without a trusted-proxy configuration the peer address
/// is reported, and `Context::forwarded_ip` remains the way to read the
/// forwarded headers directly.
pub fn Context::ip(self : Context) -> String {
  let peer = match self.state.get("remote_addr") {
    Some(value) => value
    None => "127.0.0.1"
  }
  let hops = match self.state.get(TRUST_PROXY_HOPS_KEY) {
    Some(value) =>
      match parse_int_value(value.view()) {
        Some(hops) => hops
        None => 0
      }
    None => 0
  }
  trusted_client_address(peer, forwarded_chain(self), hops)
}

///|
/// The client address, honoring the RFC 7239 `Forwarded` `for=` parameter
/// first, then the first value of `X-Forwarded-For`, then `X-Real-IP`, and
/// finally the peer address. An optional source port (and the brackets around
/// an IPv6 literal) is stripped, so the returned value is a bare address.
/// Obfuscated or unknown `for=` nodes are skipped.
pub fn Context::forwarded_ip(self : Context) -> String {
  let forwarded = self.header("Forwarded")
  if forwarded != "" {
    match forwarded_first_param(forwarded.view(), "for".view()) {
      Some(value) =>
        match normalize_forwarded_for(value.view()) {
          Some(ip) => return ip
          None => ()
        }
      None => ()
    }
  }
  let chain = self.header("X-Forwarded-For")
  if chain != "" {
    let first = match chain.find(",") {
      Some(index) => trim_ascii_space(chain[:index])
      None => trim_ascii_space(chain.view())
    }
    if !first.is_empty() {
      return normalize_legacy_forwarded_address(first)
    }
  }
  let real_ip = trim_ascii_space(self.header("X-Real-IP").view())
  if !real_ip.is_empty() {
    return normalize_legacy_forwarded_address(real_ip)
  }
  self.ip()
}

