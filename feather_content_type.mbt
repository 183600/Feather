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

