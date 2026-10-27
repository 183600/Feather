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

