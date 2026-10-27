///|
/// Middleware that rejects request bodies larger than `max_bytes` with
/// `413 Payload Too Large` before the handler runs.
///
/// The server already refuses bodies above `App::max_body_size` while they are
/// read; this middleware adds a per-route or per-group limit that can be
/// smaller, and also applies on the offline `App::respond` path, which does
/// not enforce the application-wide limit. Sizes are measured in bytes, so a
/// limit counts the encoded length of text bodies. Negative limits are clamped
/// to zero, rejecting every non-empty body.
pub fn middleware_body_limit(max_bytes : Int32) -> Middleware {
  let limit = if max_bytes < 0 { 0 } else { max_bytes }
  fn(next) {
    fn(ctx) raise {
      if ctx.body_bytes().length() > limit {
        clear_replaced_body_headers(ctx.response.headers)
        clear_replaced_representation_headers(ctx.response.headers)
        ctx.text(413, "413 Payload Too Large")
      } else {
        next(ctx)
      }
    }
  }
}

///|
/// Middleware that turns errors escaping the handler chain into responses:
/// `HttpError` / `HttpErrorPayload` become their status and JSON body,
/// `HttpProblem` becomes its RFC 7807 problem-details body, while any other
/// error becomes a `500` (and is reported through `log` when one is given,
/// since the client only sees a generic body).
pub fn middleware_recover(log? : (String) -> Unit) -> Middleware {
  fn(next) {
    fn(ctx) {
      next(ctx) catch {
        HttpError(status, message) => error_response(ctx, status, message)
        HttpErrorPayload(status, message, payload) =>
          error_response_with_payload(ctx, status, message, payload)
        HttpProblem(status, type_name, title, detail, instance) =>
          problem_response(ctx, status, type_name, title, detail, instance)
        err => {
          let detail = "\{err}"
          match log {
            Some(log) =>
              log("\{ctx.request.method} \{ctx.request.path} failed: \{detail}")
            None => ()
          }
          internal_error(ctx, detail)
        }
      }
    }
  }
}

///|
pub fn middleware_error_handler() -> Middleware {
  fn(next) {
    fn(ctx) {
      next(ctx) catch {
        HttpError(status, message) => error_response(ctx, status, message)
        HttpErrorPayload(status, message, payload) =>
          error_response_with_payload(ctx, status, message, payload)
        HttpProblem(status, type_name, title, detail, instance) =>
          problem_response(ctx, status, type_name, title, detail, instance)
        err => error_response(ctx, 500, "\{err}")
      }
    }
  }
}

///|
fn logger_record(
  log : (String) -> Unit,
  ctx : Context,
  started : Int64,
  with_duration : Bool,
) -> Unit {
  let buf = StringBuilder(size_hint=if with_duration { 64 } else { 32 })
  buf.write_char('[')
  buf.write_object(ctx.response.status)
  buf.write_string("] ")
  buf.write_string(ctx.request.method)
  buf.write_char(' ')
  buf.write_string(ctx.request.path)
  if with_duration {
    let elapsed = @async.now() - started
    buf.write_string(" (")
    buf.write_object(elapsed)
    buf.write_string("ms)")
  }
  log(buf.to_string())
}

///|
/// Middleware that logs one line per request after the response is known.
///
/// The default line is `[status] METHOD request-target`; pass
/// `with_duration=true` to append the elapsed milliseconds. `skip` is evaluated
/// before the handler, so it can silence health checks or static noise based on
/// the request, including state established by earlier middleware. Skipped
/// requests still run normally; only the log line is omitted.
pub fn middleware_logger(
  log~ : (String) -> Unit = println,
  with_duration~ : Bool = false,
  skip? : (Context) -> Bool,
) -> Middleware {
  fn(next) {
    fn(ctx) raise {
      match skip {
        Some(skip) =>
          if skip(ctx) {
            next(ctx)
            return
          }
        None => ()
      }
      let started = if with_duration { @async.now() } else { 0L }
      next(ctx) catch {
        HttpError(status, message) => {
          ctx.response.status = status
          logger_record(log, ctx, started, with_duration)
          raise HttpError(status, message)
        }
        HttpErrorPayload(status, message, payload) => {
          ctx.response.status = status
          logger_record(log, ctx, started, with_duration)
          raise HttpErrorPayload(status, message, payload)
        }
        HttpProblem(status, type_name, title, detail, instance) => {
          ctx.response.status = status
          logger_record(log, ctx, started, with_duration)
          raise HttpProblem(status, type_name, title, detail, instance)
        }
        err => {
          ctx.response.status = 500
          logger_record(log, ctx, started, with_duration)
          raise err
        }
      }
      // Static files are written after the middleware chain returns, so their
      // real status (200/206/304/404/...) is not known yet. Defer the record
      // until request cleanup, after `handle_static` has filled it in.
      if ctx.state.get(STATIC_CHAIN_PASS_KEY) is Some(_) {
        ctx.defer_cleanup(fn() {
          logger_record(log, ctx, started, with_duration)
        })
      } else {
        logger_record(log, ctx, started, with_duration)
      }
    }
  }
}

///|
/// Normalize a request id: trim surrounding whitespace, remove control
/// characters, and reject a value longer than `max_length` (`0` means no
/// limit). Rejecting rather than truncating avoids splitting a surrogate pair
/// or silently changing an id that upstream services may correlate.
fn normalize_request_id(value : String, max_length : Int32) -> String {
  let clean = trim_ascii_space(
    strip_control_characters(value).view(),
  ).to_owned()
  if max_length > 0 && clean.length() > max_length {
    ""
  } else {
    clean
  }
}

///|
/// Middleware that assigns a request id, reusing an incoming `header` value when
/// present and otherwise generating a process-local `feather-<n>` value.
///
/// The id is stored in request state (read it with `Context::request_id`) and
/// echoed in the response under the same header name. Control characters are
/// stripped from a client-supplied id, so it cannot inject another header or
/// smuggle bytes into logs.
///
/// Pass `generate` to mint ids in another format (a UUID, ULID or a value from
/// a tracing library). The generated value is sanitized like an incoming one;
/// an empty or over-long result falls back to the built-in `feather-<n>`
/// counter. `max_length` caps accepted and generated ids, which bounds the
/// state and response header an untrusted client can force; `0` disables the
/// cap.
///
/// `trust_incoming` defaults to `true`, which is useful behind a gateway that
/// already assigns ids. Set it to `false` on a public endpoint so a client
/// cannot choose the id that appears in logs and tracing systems; a generated
/// id is used instead.
pub fn middleware_request_id(
  header~ : String = "X-Request-Id",
  generate? : () -> String,
  max_length~ : Int32 = 0,
  trust_incoming~ : Bool = true,
) -> Middleware {
  let counter = Ref(0)
  let limit = if max_length < 0 { 0 } else { max_length }
  fn(next) {
    fn(ctx) raise {
      // An incoming id is client-controlled, so control characters must not
      // reach the response header or the request state even on the offline
      // facade, which does not pass through the server's header sanitizer.
      // Public endpoints can set `trust_incoming=false` so a client cannot
      // choose the id that appears in logs and correlation systems.
      let incoming = if trust_incoming {
        normalize_request_id(ctx.header(header), limit)
      } else {
        ""
      }
      let id = if incoming != "" {
        incoming
      } else {
        let candidate = match get_header_ignore_case(ctx.response.headers, header) {
          Some(value) => normalize_request_id(value, limit)
          None => ""
        }
        let candidate = if candidate != "" {
          candidate
        } else {
          match generate {
            Some(generate) => normalize_request_id(generate(), limit)
            None => ""
          }
        }
        if candidate != "" {
          candidate
        } else {
          counter.val = counter.val + 1
          "feather-" + counter.val.to_string()
        }
      }
      set_header_ignore_case(ctx.response.headers, header, id)
      ctx.state.set("request_id", id)
      next(ctx)
    }
  }
}

///|
/// Whether a comma-separated header list such as `Vary` contains `token` as a
/// complete entry, compared case-insensitively. Checking element boundaries
/// keeps `Accept` from matching an existing `Accept-Encoding` entry. A `*`
/// entry covers every token (RFC 9110 §12.5.5), so it counts as a match.
fn header_list_has_token(list : StringView, token : StringView) -> Bool {
  let length = list.length()
  let mut start = 0
  let mut i = 0
  while i <= length {
    if i == length || list.unsafe_get(i) == (',' : UInt16) {
      let entry = trim_ascii_space(list[start:i])
      if entry == ("*" : StringView) || entry.equal_ignore_ascii_case(token) {
        return true
      }
      start = i + 1
    }
    i = i + 1
  }
  false
}

///|
/// Whether a `Cache-Control` field value contains `directive` as a complete
/// directive, compared case-insensitively. A directive may carry arguments
/// after `=`; quoted argument values may contain commas.
fn cache_control_has_directive(
  value : StringView,
  directive : StringView,
) -> Bool {
  let length = value.length()
  let directive_length = directive.length()
  let mut start = 0
  let mut i = 0
  let mut in_quotes = false
  while i <= length {
    let at_end = i == length
    if at_end || (value.unsafe_get(i) == (',' : UInt16) && !in_quotes) {
      let entry = trim_ascii_space(value[start:i])
      if entry.length() >= directive_length &&
        entry[:directive_length].equal_ignore_ascii_case(directive) &&
        (
          entry.length() == directive_length ||
          entry.unsafe_get(directive_length) == ('=' : UInt16)
        ) {
        return true
      }
      start = i + 1
    } else if in_quotes && value.unsafe_get(i) == ('\\' : UInt16) {
      // RFC 9110 §5.6.4 lets a quoted-string escape any character with a
      // backslash; the escaped character (often a quote or a comma) must not
      // affect the quote balance or the directive split.
      i = i + 1
    } else if value.unsafe_get(i) == ('"' : UInt16) {
      in_quotes = !in_quotes
    }
    i = i + 1
  }
  false
}

///|
/// Append the field names in `value` to the response's `Vary` header unless
/// they are already listed.
///
/// `value` may name more than one field, separated by commas. Each field is
/// matched case-insensitively against the existing list, so passing
/// `"Origin, Accept-Encoding"` in pieces does not create duplicate entries.
pub fn Context::vary(self : Context, value : String) -> Unit {
  // `Vary` is a list of field names, so split the caller's value into complete
  // entries. Empty entries (for example a trailing comma) are ignored.
  let names : Array[String] = []
  for part in value.view().split(",") {
    let name = trim_ascii_space(part)
    if !name.is_empty() {
      names.push(name.to_owned())
    }
  }
  if names.is_empty() {
    return
  }
  // RFC 9110 §12.5.5 defines `*` as the entire field value, so a wildcard
  // replaces whatever was already listed instead of being appended to it.
  for name in names {
    if name.view().equal_ignore_ascii_case("*".view()) {
      set_header_ignore_case(self.response.headers, "Vary", "*")
      return
    }
  }
  let existing = match get_header_ignore_case(self.response.headers, "Vary") {
    Some(existing) => existing
    None => ""
  }
  let additions : Array[String] = []
  for name in names {
    if !header_list_has_token(existing.view(), name.view()) &&
      !header_list_has_token(additions.join(", ").view(), name.view()) {
      additions.push(name)
    }
  }
  if additions.length() == 0 {
    return
  }
  if trim_ascii_space(existing.view()).is_empty() {
    set_header_ignore_case(self.response.headers, "Vary", additions.join(", "))
  } else {
    set_header_ignore_case(
      self.response.headers,
      "Vary",
      existing + ", " + additions.join(", "),
    )
  }
}

///|
/// Set an optional hardening header, leaving the response untouched when the
/// caller did not configure a value.
fn set_optional_hardening_header(
  headers : Map[String, String],
  name : String,
  value : String?,
) -> Unit {
  match value {
    Some(value) => set_header_ignore_case(headers, name, value)
    None => ()
  }
}

///|
/// Middleware that adds hardening headers to every response: `nosniff`,
/// clickjacking protection and a referrer policy by default.
///
/// Pass `hsts` to also advertise `Strict-Transport-Security` (only meaningful
/// over HTTPS), `content_security_policy` to lock down which resources the
/// browser may load, or the corresponding `*_report_only` /
/// `permissions_policy` / `cross_origin_*` options for the modern policy
/// headers. Optional values are only emitted when supplied, so a minimal
/// installation keeps the same response headers as before.
pub fn middleware_secure_headers(
  content_type_options~ : String = "nosniff",
  frame_options~ : String = "DENY",
  referrer_policy~ : String = "no-referrer",
  hsts? : String,
  content_security_policy? : String,
  content_security_policy_report_only? : String,
  permissions_policy? : String,
  cross_origin_opener_policy? : String,
  cross_origin_embedder_policy? : String,
  cross_origin_resource_policy? : String,
) -> Middleware {
  fn(next) {
    fn(ctx) raise {
      let headers = ctx.response.headers
      set_header_ignore_case(
        headers,
        "X-Content-Type-Options",
        content_type_options,
      )
      set_header_ignore_case(headers, "X-Frame-Options", frame_options)
      set_header_ignore_case(headers, "Referrer-Policy", referrer_policy)
      set_optional_hardening_header(
        headers,
        "Strict-Transport-Security",
        hsts,
      )
      set_optional_hardening_header(
        headers,
        "Content-Security-Policy",
        content_security_policy,
      )
      set_optional_hardening_header(
        headers,
        "Content-Security-Policy-Report-Only",
        content_security_policy_report_only,
      )
      set_optional_hardening_header(
        headers,
        "Permissions-Policy",
        permissions_policy,
      )
      set_optional_hardening_header(
        headers,
        "Cross-Origin-Opener-Policy",
        cross_origin_opener_policy,
      )
      set_optional_hardening_header(
        headers,
        "Cross-Origin-Embedder-Policy",
        cross_origin_embedder_policy,
      )
      set_optional_hardening_header(
        headers,
        "Cross-Origin-Resource-Policy",
        cross_origin_resource_policy,
      )
      next(ctx)
    }
  }
}

///|
/// Middleware that redirects requests that did not arrive over HTTPS.
///
/// Useful behind a TLS-terminating proxy that sets `X-Forwarded-Proto`
/// (honored by `Context::is_secure`): requests marked `http` are answered with
/// a redirect to the same URL under `https`, preserving the method, the host
/// from the `Host` header (or `host` when given) and the query string.
/// `permanent` selects `308 Permanent Redirect`; pass `permanent=false` for a
/// `307 Temporary Redirect` while testing. Requests without a usable `Host`
/// are passed through untouched so no broken `Location` is produced.
pub fn middleware_https_redirect(
  permanent~ : Bool = true,
  host? : String,
) -> Middleware {
  let status : Int32 = if permanent { 308 } else { 307 }
  let fixed_host = host
  fn(next) {
    fn(ctx) raise {
      if ctx.is_secure() {
        next(ctx)
        return
      }
      let raw_authority = match fixed_host {
        Some(value) => value
        None => trim_ascii_space(ctx.header("Host").view()).to_owned()
      }
      // A control character in the authority would forge extra header lines in
      // the `Location` field. An authority that is not a bare host (optionally
      // with a port) would splice extra path, userinfo or scheme characters
      // into the URL, so both cases pass the request through like a missing
      // host instead of emitting a misleading redirect.
      let cleaned = strip_control_characters(raw_authority)
      let authority = trim_ascii_space(cleaned.view()).to_owned()
      if cleaned != raw_authority ||
        authority == "" ||
        host_authority_host(authority.view()) is None {
        next(ctx)
        return
      }
      // The asterisk-form target names the server rather than a URL path, so
      // there is no location to redirect it to.
      if ctx.request.path == "*" {
        next(ctx)
        return
      }
      let path = strip_control_characters(ctx.request.path)
      // Keep the location origin-relative even for hand-built contexts whose
      // request target did not start with a slash.
      let path = if path.has_prefix("/") { path } else { "/" + path }
      ctx.redirect(status, "https://" + authority + path)
    }
  }
}

///|
/// Whether `code` is a character allowed in a host name. Underscores are
/// accepted too because they occur in real deployments even though DNS host
/// labels should not use them.
fn is_host_name_character(code : Int32) -> Bool {
  (code >= 48 && code <= 57) ||
  (code >= 65 && code <= 90) ||
  (code >= 97 && code <= 122) ||
  code == 45 ||
  code == 46 ||
  code == 95
}

///|
/// Value of one hexadecimal digit, or `-1` for any other character.
fn hex_digit_value(unit : UInt16) -> Int32 {
  let code = unit.to_int()
  if code >= 48 && code <= 57 {
    code - 48
  } else if code >= 65 && code <= 70 {
    code - 65 + 10
  } else if code >= 97 && code <= 102 {
    code - 97 + 10
  } else {
    -1
  }
}

///|
/// Whether `view` is a dotted-decimal IPv4 address with four octets in range.
fn valid_ipv4_literal(view : StringView) -> Bool {
  let parts : Array[StringView] = []
  for part in view.split(".") {
    parts.push(part)
  }
  if parts.length() != 4 {
    return false
  }
  for part in parts {
    let length = part.length()
    if length == 0 || length > 3 {
      return false
    }
    if length > 1 && part.unsafe_get(0) == ('0' : UInt16) {
      return false
    }
    let mut value = 0
    let mut i = 0
    while i < length {
      let digit = part.unsafe_get(i).to_int() - 48
      if digit < 0 || digit > 9 {
        return false
      }
      value = value * 10 + digit
      i = i + 1
    }
    if value > 255 {
      return false
    }
  }
  true
}

///|
/// Count the 16-bit groups in one side of an IPv6 address. The optional dotted
/// tail is only valid at the end of the whole address and contributes two
/// groups instead of one.
fn ipv6_group_count(
  view : StringView,
  allow_ipv4_tail : Bool,
) -> Int32? {
  if view.is_empty() {
    return Some(0)
  }
  let parts : Array[StringView] = []
  for part in view.split(":") {
    parts.push(part)
  }
  let last = parts.length() - 1
  let mut groups = 0
  let mut index = 0
  while index < parts.length() {
    let part = parts[index]
    if part.is_empty() {
      return None
    }
    if part.contains(".") {
      if !allow_ipv4_tail || index != last || !valid_ipv4_literal(part) {
        return None
      }
      groups = groups + 2
    } else {
      let length = part.length()
      if length > 4 {
        return None
      }
      let mut i = 0
      while i < length {
        if hex_digit_value(part.unsafe_get(i)) < 0 {
          return None
        }
        i = i + 1
      }
      groups = groups + 1
    }
    index = index + 1
  }
  Some(groups)
}

///|
/// Validate a bracketed IP literal: an IPv6 address with at most one `::`
/// compression (and an optional zone identifier), or an RFC 3986 IPvFuture
/// literal such as `[v1.foo]`.
fn valid_bracketed_host(view : StringView) -> Bool {
  let length = view.length()
  if length == 0 {
    return false
  }
  if view.unsafe_get(0) == ('v' : UInt16) ||
    view.unsafe_get(0) == ('V' : UInt16) {
    let dot = match view.find(".") {
      Some(index) => index
      None => return false
    }
    if dot <= 1 {
      return false
    }
    let mut i = 1
    while i < dot {
      if hex_digit_value(view.unsafe_get(i)) < 0 {
        return false
      }
      i = i + 1
    }
    i = dot + 1
    if i >= length {
      return false
    }
    while i < length {
      let code = view.unsafe_get(i).to_int()
      let allowed = is_host_name_character(code) ||
        code == 58 ||
        code == 33 ||
        (code >= 36 && code <= 38) ||
        code == 39 ||
        code == 40 ||
        code == 41 ||
        code == 42 ||
        code == 43 ||
        code == 44 ||
        code == 59 ||
        code == 61 ||
        code == 126
      if !allowed {
        return false
      }
      i = i + 1
    }
    return true
  }
  // A zone identifier follows `%` and is not part of the IPv6 address. In a
  // URI it is usually percent-encoded (`%25eth0`), so validate the zone text
  // as unreserved characters or complete `%HH` escapes instead of accepting
  // stray percent signs and separators.
  let address = match view.find("%") {
    Some(index) => {
      if index == 0 || index + 1 >= length {
        return false
      }
      let mut i = index + 1
      while i < length {
        let code = view.unsafe_get(i).to_int()
        if code == 37 {
          if i + 2 >= length ||
            hex_digit_value(view.unsafe_get(i + 1)) < 0 ||
            hex_digit_value(view.unsafe_get(i + 2)) < 0 {
            return false
          }
          i = i + 3
        } else if is_host_name_character(code) || code == 126 {
          i = i + 1
        } else {
          return false
        }
      }
      view[:index]
    }
    None => view
  }
  match address.find("::") {
    Some(index) => {
      let left = address[:index]
      let right = address[index + 2:]
      if right.find("::") is Some(_) {
        return false
      }
      let left_groups = match ipv6_group_count(left, false) {
        Some(groups) => groups
        None => return false
      }
      let right_groups = match ipv6_group_count(right, true) {
        Some(groups) => groups
        None => return false
      }
      // `::` represents at least one zero group.
      left_groups + right_groups <= 7
    }
    None =>
      match ipv6_group_count(address, true) {
        Some(groups) => groups == 8
        None => false
      }
  }
}

///|
/// Validate the part of an authority between the brackets (for an IP literal)
/// or the whole host name.
fn valid_host_name(view : StringView, bracketed : Bool) -> Bool {
  if bracketed {
    return valid_bracketed_host(view)
  }
  let length = view.length()
  if length == 0 {
    return false
  }
  let mut i = 0
  while i < length {
    let code = view.unsafe_get(i).to_int()
    if !is_host_name_character(code) {
      return false
    }
    i = i + 1
  }
  if view.unsafe_get(0) == ('.' : UInt16) {
    return false
  }
  // A trailing dot denotes the DNS root and is allowed, but every other label
  // must be non-empty: `example..com` and `example..` are malformed
  // authorities, not subdomains of `example.com`.
  let mut label_start = 0
  let mut index = 0
  while index <= length {
    if index == length ||
      view.unsafe_get(index) == ('.' : UInt16) {
      if index == label_start &&
        !(index == length && label_start > 0) {
        return false
      }
      label_start = index + 1
    }
    index = index + 1
  }
  true
}

///|
/// Whether `value` is a syntactically valid decimal TCP/UDP port. An empty
/// value or one above 65535 is rejected.
fn valid_host_port(value : StringView) -> Bool {
  let length = value.length()
  if length == 0 {
    return false
  }
  let mut port = 0
  let mut i = 0
  while i < length {
    let digit = value.unsafe_get(i).to_int() - 48
    if digit < 0 || digit > 9 {
      return false
    }
    port = port * 10 + digit
    if port > 65535 {
      return false
    }
    i = i + 1
  }
  true
}

///|
/// Parse a `Host` header (or a configured host) into its port-less name.
///
/// A bracketed IPv6 literal keeps its brackets; an optional numeric port is
/// validated and dropped. A malformed authority, embedded whitespace or
/// control character, unbracketed IPv6 literal, or an empty host yields
/// `None`. A single trailing dot, which denotes an absolute DNS name, is
/// removed so `example.com.` matches `example.com`.
fn host_authority_host(value : StringView) -> String? {
  let authority = trim_ascii_space(value)
  let length = authority.length()
  if length == 0 {
    return None
  }
  // Header values must not carry separators or control characters into the
  // parsed host: such values are malformed rather than matchable.
  let mut scan = 0
  while scan < length {
    let code = authority.unsafe_get(scan).to_int()
    if code <= 0x20 || code == 0x7F || code == 44 {
      return None
    }
    scan = scan + 1
  }
  if authority.unsafe_get(0) == ('[' : UInt16) {
    let close = match authority.find("]") {
      Some(index) => index
      None => return None
    }
    if close <= 1 || !valid_host_name(authority[1:close], true) {
      return None
    }
    let rest = authority[close + 1:]
    if rest.length() == 0 {
      return Some(authority[:close + 1].to_owned())
    }
    if rest.unsafe_get(0) != (':' : UInt16) ||
      !valid_host_port(rest[1:]) {
      return None
    }
    return Some(authority[:close + 1].to_owned())
  }
  let mut colons = 0
  let mut last_colon = -1
  let mut i = 0
  while i < length {
    if authority.unsafe_get(i) == (':' : UInt16) {
      colons = colons + 1
      last_colon = i
    }
    i = i + 1
  }
  let host = if colons == 0 {
    authority
  } else if colons == 1 {
    if last_colon <= 0 || !valid_host_port(authority[last_colon + 1:]) {
      return None
    }
    authority[:last_colon]
  } else {
    // More than one colon without brackets is a bare IPv6 literal, which is
    // not a valid HTTP authority.
    return None
  }
  if !valid_host_name(host, false) {
    return None
  }
  let text = host.to_owned()
  if text.length() > 1 && text.has_suffix(".") {
    Some(text[:text.length() - 1].to_owned())
  } else {
    Some(text)
  }
}

///|
/// Normalize one configured host pattern. `"*"` accepts any well-formed host;
/// `"*.example.com"` accepts that domain's subdomains; everything else is an
/// exact host name. A configured port is accepted and ignored.
fn normalize_host_pattern(value : String) -> String? {
  let trimmed = trim_ascii_space(value.view())
  if trimmed == "*" {
    return Some("*")
  }
  if trimmed.has_prefix("*.") {
    match host_authority_host(trimmed[2:]) {
      Some(host) => Some("*." + host)
      None => None
    }
  } else {
    host_authority_host(trimmed)
  }
}

///|
/// Case-insensitive `ends_with` for ASCII host names.
fn host_ends_with_ignore_ascii_case(
  value : StringView,
  suffix : StringView,
) -> Bool {
  if suffix.length() > value.length() {
    return false
  }
  let offset = value.length() - suffix.length()
  let mut i = 0
  while i < suffix.length() {
    let left = value.unsafe_get(offset + i).to_int()
    let right = suffix.unsafe_get(i).to_int()
    let lower_left = if left >= 65 && left <= 90 { left + 32 } else { left }
    let lower_right = if right >= 65 && right <= 90 {
      right + 32
    } else {
      right
    }
    if lower_left != lower_right {
      return false
    }
    i = i + 1
  }
  true
}

///|
/// Whether a validated request `host` matches a normalized configured
/// `pattern`.
fn host_matches_pattern(host : String, pattern : String) -> Bool {
  if pattern == "*" {
    return true
  }
  let pattern_view = pattern.view()
  if pattern_view.has_prefix("*.") {
    let suffix = pattern_view[1:]
    host.length() > suffix.length() &&
    host_ends_with_ignore_ascii_case(host.view(), suffix)
  } else {
    host.view().equal_ignore_ascii_case(pattern_view)
  }
}

///|
/// Middleware that rejects requests whose `Host` header is not in the
/// allowlist with `400 Bad Request`, before the handler runs.
///
/// Host names are matched case-insensitively after an optional port is
/// stripped, so `example.com`, `Example.COM:8080` and `example.com.` all match
/// the entry `"example.com"`. An entry starting with `*.` accepts any
/// subdomain of that domain (`*.example.com` matches `api.example.com` and
/// `a.b.example.com`, but not `example.com` itself), and `"*"` accepts any
/// well-formed authority. Malformed authorities, including embedded control
/// characters, unbracketed IPv6 literals and invalid ports, are rejected.
///
/// The `Host` header is used directly and forwarded-host headers are ignored,
/// so a client cannot bypass the check by setting `X-Forwarded-Host`. A
/// missing `Host` is rejected by default; pass `allow_missing=true` for
/// HTTP/1.0 clients or health checks that do not send one.
pub fn middleware_allowed_hosts(
  hosts : Array[String],
  allow_missing~ : Bool = false,
) -> Middleware {
  let patterns : Array[String] = []
  for host in hosts {
    match normalize_host_pattern(host) {
      Some(pattern) => patterns.push(pattern)
      None => ()
    }
  }
  fn(next) {
    fn(ctx) raise {
      let raw = ctx.header("Host")
      if trim_ascii_space(raw.view()).is_empty() {
        if allow_missing {
          next(ctx)
        } else {
          clear_replaced_representation_headers(ctx.response.headers)
          ctx.text(400, "400 Bad Request")
        }
        return
      }
      let accepted = match host_authority_host(raw.view()) {
        Some(host) => {
          let mut matched = false
          for pattern in patterns {
            if host_matches_pattern(host, pattern) {
              matched = true
            }
          }
          matched
        }
        None => false
      }
      if accepted {
        next(ctx)
      } else {
        clear_replaced_representation_headers(ctx.response.headers)
        ctx.text(400, "400 Bad Request")
      }
    }
  }
}

///|
/// Middleware that lets HTML forms perform non-`POST` methods.
///
/// Browsers can only submit `GET` and `POST` forms, so frameworks commonly
/// tunnel `PUT` / `PATCH` / `DELETE` through a `POST` carrying an override:
/// the `header` (default `X-HTTP-Method-Override`) or, when the body is
/// `application/x-www-form-urlencoded`, the `field` (default `_method`).
/// Only safe, well-known methods are accepted; anything else is ignored and
/// the request stays a `POST`. Install it before the router runs, i.e. as any
/// other `App::use` middleware.
pub fn middleware_method_override(
  field~ : String = "_method",
  header~ : String = "X-HTTP-Method-Override",
) -> Middleware {
  let field_name = field
  let header_name = header
  fn(next) {
    fn(ctx) raise {
      if ctx.get_method().view().equal_ignore_ascii_case("POST".view()) {
        let value = {
          let from_header = trim_ascii_space(ctx.header(header_name).view())
          if from_header.is_empty() {
            trim_ascii_space(ctx.form(field_name).view())
          } else {
            from_header
          }
        }
        if value.view().equal_ignore_ascii_case("PUT".view()) {
          ctx.request.method = "PUT"
        } else if value.view().equal_ignore_ascii_case("PATCH".view()) {
          ctx.request.method = "PATCH"
        } else if value.view().equal_ignore_ascii_case("DELETE".view()) {
          ctx.request.method = "DELETE"
        } else if value.view().equal_ignore_ascii_case("OPTIONS".view()) {
          ctx.request.method = "OPTIONS"
        }
      }
      next(ctx)
    }
  }
}

///|
priv enum CorsOriginPolicy {
  CorsOriginFixed(String)
  CorsOriginPredicate((String) -> Bool)
}

///|
/// Shared implementation of the fixed-origin and predicate CORS middleware.
fn cors_middleware(
  policy : CorsOriginPolicy,
  allow_methods : String,
  allow_headers : String,
  expose_headers : String,
  allow_credentials : Bool,
  max_age : Int32,
  allow_private_network : Bool,
) -> Middleware {
  fn(next) {
    fn(ctx) raise {
      let raw_origin = trim_ascii_space(ctx.header("Origin").view()).to_owned()
      // Origins are ASCII tokens without control characters. Reject a malformed
      // value instead of echoing it into a response header, where CR/LF could
      // forge additional fields.
      let origin = strip_control_characters(raw_origin)
      let origin = if origin == raw_origin { origin } else { "" }
      let is_options = ctx.get_method().view().equal_ignore_ascii_case(
        "OPTIONS".view(),
      )
      // A wildcard policy with credentials cannot keep the wildcard grant for
      // an Origin-bearing request; it echoes that Origin instead. The response
      // therefore depends on `Origin` even when the request has none, where it
      // falls back to `*`.
      let wildcard_credentials = if allow_credentials {
        match policy {
          CorsOriginFixed(value) => value == "*"
          CorsOriginPredicate(_) => false
        }
      } else {
        false
      }
      let (allowed_origin, dynamic_origin) = match policy {
        CorsOriginFixed(value) =>
          if value != "*" {
            (value, true)
          } else if wildcard_credentials {
            // A malformed Origin is discarded and answered like an anonymous
            // request. Only a valid Origin, or the absence of the field, can
            // change the representation that a shared cache must separate.
            (
              if origin != "" { origin } else { "*" },
              origin != "" || raw_origin == "",
            )
          } else {
            ("*", false)
          }
        CorsOriginPredicate(check) =>
          if origin != "" && check(origin) {
            (origin, true)
          } else {
            // Rejecting an origin is just as dependent on the request's
            // `Origin` as accepting one: the same URL can return a grant for
            // an allowed origin and none for this request.
            ("", true)
          }
      }
      if allowed_origin != "" {
        set_header_ignore_case(
          ctx.response.headers,
          "Access-Control-Allow-Origin",
          allowed_origin,
        )
      }
      if dynamic_origin {
        // The answer depends on the request's `Origin`, so shared caches must
        // keep origins apart.
        ctx.vary("Origin")
      }
      if allow_credentials &&
        allowed_origin != "" &&
        (origin != "" || !wildcard_credentials) {
        // `Access-Control-Allow-Origin: *` and credentials are an invalid
        // pair. A no-Origin request is not a CORS request, so omit the
        // credentials grant there while still keeping the wildcard for
        // non-credentialed clients.
        set_header_ignore_case(
          ctx.response.headers,
          "Access-Control-Allow-Credentials",
          "true",
        )
      }
      if is_options {
        // A real CORS preflight carries both `Origin` and
        // `Access-Control-Request-Method` and is answered here without running
        // the handler. Other OPTIONS requests (including explicit OPTIONS
        // routes) pass through to the router and are only decorated with the
        // CORS headers below.
        let preflight = origin != "" &&
          ctx.header("Access-Control-Request-Method") != ""
        if preflight {
          ctx.file = None
          ctx.response.status = 204
          ctx.response.data = None
          ctx.response.body = ""
          ignore(
            remove_header_ignore_case(ctx.response.headers, "Content-Type"),
          )
          ignore(
            remove_header_ignore_case(ctx.response.headers, "Content-Length"),
          )
          ignore(
            remove_header_ignore_case(ctx.response.headers, "Content-Encoding"),
          )
          ignore(
            remove_header_ignore_case(ctx.response.headers, "Content-Range"),
          )
          clear_replaced_representation_headers(ctx.response.headers)
          // A rejected origin must not receive any CORS grant. The credentials
          // header is set before the origin decision, so remove it here when
          // this preflight has no accepted origin.
          if allowed_origin == "" {
            ignore(
              remove_header_ignore_case(
                ctx.response.headers,
                "Access-Control-Allow-Credentials",
              ),
            )
          }
          // A denied preflight still depends on `Origin`: its 204 carries no
          // CORS grants, while an accepted one does. Add the key here when the
          // origin itself was not already recorded as dynamic.
          if dynamic_origin || allowed_origin == "" {
            ctx.vary("Origin")
          }
          // The preflight answer depends on the two request headers, so shared
          // caches must key on them as well (Fetch: Vary considerations).
          ctx.vary("Access-Control-Request-Method")
          ctx.vary("Access-Control-Request-Headers")
          if allow_private_network {
            // The grant is conditional on the browser's request header, so a
            // shared cache must not reuse this preflight for another request.
            ctx.vary("Access-Control-Request-Private-Network")
          }
        } else {
          next(ctx)
        }
        if allowed_origin != "" {
          set_header_ignore_case(
            ctx.response.headers,
            "Access-Control-Allow-Methods",
            allow_methods,
          )
          // With credentials the `*` wildcard is a literal header name, so a
          // preflight asking for anything else must see its own list echoed
          // back (Fetch: CORS-preflight fetch).
          let allowed_headers = if allow_headers == "*" && allow_credentials {
            match get_header_ignore_case(
              ctx.request.headers,
              "Access-Control-Request-Headers",
            ) {
              Some(requested) =>
                if requested == "" {
                  allow_headers
                } else {
                  strip_control_characters(requested)
                }
              None => allow_headers
            }
          } else {
            allow_headers
          }
          set_header_ignore_case(
            ctx.response.headers,
            "Access-Control-Allow-Headers",
            allowed_headers,
          )
          if max_age > 0 {
            set_header_ignore_case(
              ctx.response.headers,
              "Access-Control-Max-Age",
              max_age.to_string(),
            )
          }
          if preflight &&
            allow_private_network &&
            trim_ascii_space(
              ctx.header("Access-Control-Request-Private-Network").view(),
            ).equal_ignore_ascii_case("true".view()) {
            // Chrome's Private Network Access preflight asks the public origin
            // to opt in explicitly. Only an accepted origin gets the grant.
            set_header_ignore_case(
              ctx.response.headers,
              "Access-Control-Allow-Private-Network",
              "true",
            )
          }
        }
      } else {
        if expose_headers != "" && allowed_origin != "" {
          set_header_ignore_case(
            ctx.response.headers,
            "Access-Control-Expose-Headers",
            expose_headers,
          )
        }
        next(ctx)
      }
    }
  }
}

///|
/// Middleware that adds CORS response headers and answers preflight requests.
///
/// `allow_origin` is either `"*"` (the default) or a concrete origin to
/// advertise; when credentials are enabled the request's `Origin` is echoed
/// instead, because browsers reject a wildcard with credentials. Use
/// `middleware_cors_with` for a dynamic predicate or
/// `middleware_cors_allowlist` for a fixed set of accepted origins. Pass
/// `allow_private_network=true` to grant a browser's Private Network Access
/// preflight when it asks for it.
pub fn middleware_cors(
  allow_origin~ : String = "*",
  allow_methods~ : String = "GET, POST, PUT, PATCH, DELETE, HEAD, OPTIONS",
  allow_headers~ : String = "*",
  expose_headers~ : String = "",
  allow_credentials~ : Bool = false,
  max_age~ : Int32 = 0,
  allow_private_network~ : Bool = false,
) -> Middleware {
  cors_middleware(
    CorsOriginFixed(allow_origin),
    allow_methods,
    allow_headers,
    expose_headers,
    allow_credentials,
    max_age,
    allow_private_network,
  )
}

///|
/// CORS middleware whose accepted origin is decided per request.
///
/// The predicate receives the request's non-empty `Origin`; returning `true`
/// echoes that origin in `Access-Control-Allow-Origin` and adds `Vary:
/// Origin`. Requests with an origin the predicate rejects (and requests
/// without an `Origin`) are passed through without CORS headers. Preflight
/// requests are still answered with `204`, so a rejected origin never reaches
/// the handler.
pub fn middleware_cors_with(
  allow_origin~ : (String) -> Bool,
  allow_methods~ : String = "GET, POST, PUT, PATCH, DELETE, HEAD, OPTIONS",
  allow_headers~ : String = "*",
  expose_headers~ : String = "",
  allow_credentials~ : Bool = false,
  max_age~ : Int32 = 0,
  allow_private_network~ : Bool = false,
) -> Middleware {
  cors_middleware(
    CorsOriginPredicate(allow_origin),
    allow_methods,
    allow_headers,
    expose_headers,
    allow_credentials,
    max_age,
    allow_private_network,
  )
}

///|
/// CORS middleware that accepts only the listed origins.
///
/// Matching is exact and case-sensitive, which is the right default for the
/// serialized origins browsers send. An empty list rejects every origin while
/// still answering preflight requests.
pub fn middleware_cors_allowlist(
  origins : Array[String],
  allow_methods~ : String = "GET, POST, PUT, PATCH, DELETE, HEAD, OPTIONS",
  allow_headers~ : String = "*",
  expose_headers~ : String = "",
  allow_credentials~ : Bool = false,
  max_age~ : Int32 = 0,
  allow_private_network~ : Bool = false,
) -> Middleware {
  let accepted = origins.copy()
  middleware_cors_with(
    allow_origin=fn(origin) {
      let mut found = false
      for candidate in accepted {
        if candidate == origin {
          found = true
        }
      }
      found
    },
    allow_methods~,
    allow_headers~,
    expose_headers~,
    allow_credentials~,
    max_age~,
    allow_private_network~,
  )
}

///|
fn auth_challenge(scheme : String, realm : String) -> String {
  let clean = strip_control_characters(realm)
  let view = clean.view()
  let length = view.length()
  let builder = StringBuilder(size_hint=scheme.length() + length + 16)
  builder.write_string(scheme)
  builder.write_string(" realm=\"")
  let mut i = 0
  while i < length {
    let code = view.unsafe_get(i).to_int()
    if code == 34 || code == 92 {
      builder.write_char('\\')
    }
    builder.write_char(code.unsafe_to_char())
    i = i + 1
  }
  builder.write_char('"')
  builder.to_string()
}

///|
fn basic_auth_challenge(realm : String) -> String {
  auth_challenge("Basic", realm)
}

///|
fn bearer_auth_challenge(realm : String) -> String {
  auth_challenge("Bearer", realm)
}

///|
fn constant_time_equal(left : String, right : String) -> Bool {
  let left_view = left.view()
  let right_view = right.view()
  let left_length = left_view.length()
  let right_length = right_view.length()
  let mut difference = left_length ^ right_length
  let length = if left_length > right_length {
    left_length
  } else {
    right_length
  }
  for i = 0; i < length; i = i + 1 {
    let a = if i < left_length { left_view.unsafe_get(i) } else { 0 }
    let b = if i < right_length { right_view.unsafe_get(i) } else { 0 }
    difference = difference | (a ^ b).to_int()
  }
  difference == 0
}

///|
fn bearer_auth_middleware(
  check : (String) -> Bool,
  realm : String,
) -> Middleware {
  let challenge = bearer_auth_challenge(realm)
  fn(next) {
    fn(ctx) raise {
      let authorized = match ctx.bearer_token() {
        Some(token) => check(token)
        None => false
      }
      if authorized {
        next(ctx)
      } else {
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

///|
fn basic_auth_middleware(
  check : (String, String) -> Bool,
  realm : String,
) -> Middleware {
  let challenge = basic_auth_challenge(realm)
  fn(next) {
    fn(ctx) raise {
      let authorized = match ctx.basic_auth() {
        Some((username, password)) => check(username, password)
        None => false
      }
      if authorized {
        next(ctx)
      } else {
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

///|
/// Middleware that challenges requests with a bearer token and accepts any
/// configured opaque token. Tokens are compared with the same constant-time
/// helper used by basic authentication.
pub fn middleware_bearer_auth(
  tokens : Array[String],
  realm~ : String = "Restricted",
) -> Middleware {
  bearer_auth_middleware(
    fn(token) {
      let mut accepted = false
      for expected in tokens {
        if constant_time_equal(token, expected) {
          accepted = true
        }
      }
      accepted
    },
    realm,
  )
}

///|
/// Middleware that challenges requests with a bearer token and accepts tokens
/// approved by `check`.
pub fn middleware_bearer_auth_with(
  check : (String) -> Bool,
  realm~ : String = "Restricted",
) -> Middleware {
  bearer_auth_middleware(check, realm)
}

///|
/// Middleware that challenges requests with HTTP Basic authentication and
/// accepts credentials listed in `accounts`.
pub fn middleware_basic_auth(
  accounts : Map[String, String],
  realm~ : String = "Restricted",
) -> Middleware {
  basic_auth_middleware(
    fn(username, password) {
      match accounts.get(username) {
        Some(expected) => constant_time_equal(password, expected)
        None => false
      }
    },
    realm,
  )
}

///|
/// Middleware that challenges requests with HTTP Basic authentication and
/// accepts credentials approved by `check`.
pub fn middleware_basic_auth_with(
  check : (String, String) -> Bool,
  realm~ : String = "Restricted",
) -> Middleware {
  basic_auth_middleware(check, realm)
}

