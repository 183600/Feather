///|
/// Enable automatic `ETag` generation for dynamic responses.
///
/// A tag is derived from the response body (after compression, so encodings
/// keep distinct validators) for 2xx responses with a non-empty body and no
/// `ETag` of their own. Requests whose `If-None-Match` matches are answered
/// with an empty `304 Not Modified`, saving bandwidth for cacheable JSON and
/// text APIs. Responses that opt out with `Cache-Control: no-store` are left
/// untouched.
pub fn App::etag(self : App) -> App {
  self.etag_enabled = true
  self
}

///|
/// FNV-1a hash of `data`, rendered as 16 lowercase hex digits.
fn fnv1a_hex(data : Bytes) -> String {
  let mut hash = 14695981039346656037UL
  for byte in data {
    hash = (hash ^ byte.to_uint64()) * 1099511628211UL
  }
  let hex = hash.to_string(radix=16)
  let padding = 16 - hex.length()
  if padding <= 0 {
    return hex
  }
  let builder = StringBuilder()
  for i = 0; i < padding; i = i + 1 {
    builder.write_char('0')
  }
  builder.write_string(hex)
  builder.to_string()
}

///|
fn apply_etag(request : @http.Request, response : Response) -> Unit {
  if response.status < 200 || response.status >= 300 || response.status == 204 {
    return
  }
  match get_header_ignore_case(response.headers, "Cache-Control") {
    Some(control) =>
      if contains_ignore_ascii_case(control.view(), "no-store".view()) {
        return
      }
    None => ()
  }
  let etag = match get_header_ignore_case(response.headers, "ETag") {
    Some(existing) => existing
    None => {
      let data = match response.data {
        Some(data) => data
        None =>
          if response.body.is_empty() {
            return
          } else {
            @utf8.encode(response.body)
          }
      }
      let computed = "\"" +
        data.length().to_string() +
        "-" +
        fnv1a_hex(data) +
        "\""
      response.headers.set("ETag", computed)
      computed
    }
  }
  match request.headers.get(header_if_none_match) {
    Some(value) =>
      if etag_header_matches(value.view(), etag) {
        response.status = 304
        response.body = ""
        response.data = None
        response.headers.remove("Content-Type")
        response.headers.remove("Content-Length")
      }
    None => ()
  }
}

///|
pub fn Feather::etag(self : Feather) -> Feather {
  ignore(self.app.etag())
  self
}
