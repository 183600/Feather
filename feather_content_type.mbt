///|
/// Most recently normalized `Content-Type` header value.
let last_content_type_header : Ref[String?] = Ref(None)

///|
let last_content_type_value : Ref[String] = Ref("")

///|
/// Normalized media types keyed by their raw `Content-Type` header value.
let content_type_cache : Map[String, String] = Map([])

///|
/// Recency ticks for `content_type_cache`.
let content_type_cache_ages : Map[String, Int32] = Map([])

///|
fn parsed_content_type(header : String) -> String {
  match last_content_type_header.val {
    Some(cached_header) =>
      if physical_equal(cached_header, header) {
        return last_content_type_value.val
      }
    None => ()
  }
  match content_type_cache.get(header) {
    Some(cached) => {
      cache_touch(content_type_cache_ages, header)
      last_content_type_header.val = Some(header)
      last_content_type_value.val = cached
      return cached
    }
    None => ()
  }
  let view = header.view()
  let end = match view.find(";") {
    Some(index) => index
    None => view.length()
  }
  let value = trim_ascii_space(view[:end])
  let result = if has_ascii_upper(value) {
    value.to_lower().to_owned()
  } else {
    value.to_owned()
  }
  if header.length() <= PARSE_CACHE_MAX_KEY {
    parse_cache_set(content_type_cache, content_type_cache_ages, header, result)
  }
  last_content_type_header.val = Some(header)
  last_content_type_value.val = result
  result
}

///|
/// The media type of the request body, lowercased and stripped of parameters:
/// `"application/json; charset=utf-8"` becomes `"application/json"`. Returns
/// `""` when the request has no `Content-Type`.
pub fn Context::content_type(self : Context) -> String {
  parsed_content_type(self.header("Content-Type"))
}

///|
/// Whether `value` is a non-empty HTTP token, and so can be written as a media
/// type parameter name or an unquoted parameter value.
fn is_content_type_token(value : StringView) -> Bool {
  if value.is_empty() {
    return false
  }
  for i = 0; i < value.length(); i = i + 1 {
    if !is_http_token_character(value.unsafe_get(i).to_int()) {
      return false
    }
  }
  true
}

///|
/// Format a media type parameter value, quoting it when it is not a bare token.
///
/// Quoted values escape `"` and `\` as required by RFC 7231 and drop control
/// characters, so a caller-controlled value cannot terminate the quoted string
/// or inject another header line.
fn content_type_parameter_value(value : String) -> String {
  if is_content_type_token(value.view()) {
    return value
  }
  let buf = StringBuilder(size_hint=value.length() + 2)
  buf.write_char('"')
  for i = 0; i < value.length(); i = i + 1 {
    let code = value.unsafe_get(i)
    let code_value = code.to_int()
    if code_value < 0x20 || code_value == 0x7F {
      continue
    }
    if code == '"' || code == '\\' {
      buf.write_char('\\')
    }
    buf.write_char(code.unsafe_to_char())
  }
  buf.write_char('"')
  buf.to_string()
}

///|
/// Trim surrounding whitespace and any trailing `;` separators from a media
/// type, so appending parameters cannot produce an empty or repeated separator.
fn normalize_content_type_media_type(media_type : String) -> String {
  let cleaned = strip_control_characters(
    trim_ascii_space(media_type.view()).to_owned(),
  )
  let view = cleaned.view()
  let mut end = view.length()
  while end > 0 {
    let code = view.unsafe_get(end - 1)
    if code == (';' : UInt16) ||
      code == (' ' : UInt16) ||
      code == ('\t' : UInt16) {
      end = end - 1
    } else {
      break
    }
  }
  view[:end].to_owned()
}

///|
/// Set the response media type and append any parameters.
///
/// The media type is trimmed and any trailing `;` removed; each parameter with
/// a valid HTTP token name is appended in array order. Values that are not bare
/// tokens (including the empty string) are quoted and escaped. Invalid
/// parameter names are skipped, and control characters are removed from all
/// parts, so untrusted values cannot forge header content.
///
/// This only sets the header; the body helpers (`text`, `html`, `json`,
/// `bytes`, ...) set their own `Content-Type`. Call this after the body helper
/// when a custom representation type is wanted, or pass `content_type` to
/// `Context::bytes`.
pub fn Context::set_content_type(
  self : Context,
  media_type : String,
  parameters~ : Array[(String, String)] = [],
) -> Unit {
  let normalized = normalize_content_type_media_type(media_type)
  if normalized == "" {
    return
  }
  let buf = StringBuilder(
    size_hint=normalized.length() + parameters.length() * 16,
  )
  buf.write_string(normalized)
  for entry in parameters {
    let (name, value) = entry
    let trimmed_name = trim_ascii_space(name.view())
    if !is_content_type_token(trimmed_name) {
      continue
    }
    buf.write_string("; ")
    buf.write_view(trimmed_name)
    buf.write_char('=')
    buf.write_string(content_type_parameter_value(value))
  }
  set_header_ignore_case(
    self.response.headers,
    "Content-Type",
    buf.to_string(),
  )
}

///|
/// Whether the request body is JSON, including `+json` structured suffixes
/// such as `application/problem+json`.
pub fn Context::is_json(self : Context) -> Bool {
  let media_type = self.content_type()
  media_type == "application/json" || media_type.has_suffix("+json")
}

///|
/// Whether the request body is `application/x-www-form-urlencoded`.
pub fn Context::is_form(self : Context) -> Bool {
  self.content_type() == "application/x-www-form-urlencoded"
}

///|
/// A parameter of the request's `Content-Type`, such as `charset` or
/// `multipart/form-data`'s `boundary`. Parameter names are matched
/// case-insensitively, quoted values are unescaped, and only a whole parameter
/// name matches, so `xcharset` does not answer a lookup for `charset`.
///
/// Returns `None` when the request has no `Content-Type`, the parameter is
/// missing, or the parameter has no `=`. When a parameter occurs more than
/// once, the first occurrence wins.
pub fn Context::content_type_parameter(
  self : Context,
  name : String,
) -> String? {
  header_parameter(self.header("Content-Type").view(), name)
}

///|
/// Whether lower-cased `media_type` matches the lower-cased media type
/// `pattern`. A pattern without wildcards is an exact match; `type/*`,
/// `*/*` and `*` accept groups, while a subtype such as `*+json` accepts
/// structured suffixes. Parameters are not part of either side.
fn content_type_pattern_matches(
  pattern : StringView,
  media_type : StringView,
) -> Bool {
  if pattern == "*" || pattern == "*/*" {
    return true
  }
  let pattern_slash = match pattern.find("/") {
    Some(index) => index
    None => return false
  }
  let media_type_slash = match media_type.find("/") {
    Some(index) => index
    None => return false
  }
  if pattern_slash <= 0 ||
    pattern_slash + 1 >= pattern.length() ||
    media_type_slash <= 0 ||
    media_type_slash + 1 >= media_type.length() {
    return false
  }
  let pattern_type = pattern[:pattern_slash]
  let pattern_subtype = pattern[pattern_slash + 1:]
  let media_type_type = media_type[:media_type_slash]
  let media_type_subtype = media_type[media_type_slash + 1:]
  if pattern_type != "*" && pattern_type != media_type_type {
    return false
  }
  if pattern_subtype == "*" {
    return true
  }
  if pattern_subtype.has_prefix("*+") {
    let suffix = pattern_subtype[1:]
    return media_type_subtype.length() > suffix.length() &&
      media_type_subtype.has_suffix(suffix)
  }
  pattern_subtype == media_type_subtype
}

///|
/// Middleware that accepts only the listed request media types.
///
/// The check applies to requests whose body is not empty; a bodyless request
/// passes regardless of its `Content-Type`, which keeps empty `POST`/`DELETE`
/// calls working. A non-empty body with no `Content-Type` is rejected unless
/// `allow_missing=true`. Matching ignores parameters (so
/// `application/json; charset=utf-8` matches `application/json`) and is
/// case-insensitive; entries may be exact media types, `type/*`, `*/*`, `*`,
/// or a structured-suffix pattern such as `application/*+json`.
///
/// Requests that do not match are answered with `415 Unsupported Media Type`
/// before the handler runs. An empty `types` list therefore rejects every
/// non-empty body. Names are compared after trimming, and an invalid entry
/// simply never matches.
pub fn middleware_allowed_content_types(
  types : Array[String],
  allow_missing~ : Bool = false,
) -> Middleware {
  let patterns : Array[String] = Array(capacity=types.length())
  for media_type in types {
    patterns.push(parsed_content_type(media_type))
  }
  fn(next) {
    fn(ctx) raise {
      if ctx.body_bytes().length() == 0 {
        next(ctx)
        return
      }
      let actual = ctx.content_type()
      if actual == "" {
        if allow_missing {
          next(ctx)
          return
        }
      } else {
        let actual_view = actual.view()
        for pattern in patterns {
          if content_type_pattern_matches(pattern.view(), actual_view) {
            next(ctx)
            return
          }
        }
      }
      clear_replaced_body_headers(ctx.response.headers)
      clear_replaced_representation_headers(ctx.response.headers)
      ctx.text(415, "415 Unsupported Media Type")
    }
  }
}

