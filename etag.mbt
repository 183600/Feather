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
/// Append the FNV-1a hash of `data` to `builder` as 16 lowercase hex digits.
fn write_fnv1a_hex(builder : StringBuilder, data : Bytes) -> Unit {
  let mut hash = 14695981039346656037UL
  for byte in data {
    hash = (hash ^ byte.to_uint64()) * 1099511628211UL
  }
  for i = 0; i < 16; i = i + 1 {
    let nibble = ((hash >> ((15 - i) * 4)) & 15UL).to_int()
    builder.write_char(
      (if nibble < 10 {
        b'0'.to_int() + nibble
      } else {
        b'a'.to_int() + nibble - 10
      }).unsafe_to_char(),
    )
  }
}

///|
/// Give a successful response a strong `ETag` derived from its body when it
/// has none. Responses that opt out with `Cache-Control: no-store`, hold no
/// representation, or already carry a validator are left untouched.
fn apply_etag(response : Response) -> Unit {
  if response.status < 200 ||
    response.status >= 300 ||
    response.status == 204 ||
    response.status == 205 {
    return
  }
  if get_header_ignore_case(response.headers, "Content-Range") is Some(_) {
    return
  }
  match get_header_ignore_case(response.headers, "Cache-Control") {
    Some(control) =>
      if contains_ignore_ascii_case(control.view(), "no-store".view()) {
        return
      }
    None => ()
  }
  if get_header_ignore_case(response.headers, "ETag") is Some(_) {
    return
  }
  let data = match response.data {
    Some(data) => data
    None =>
      if response.body.is_empty() {
        return
      } else {
        let encoded = @utf8.encode(response.body)
        response.body = ""
        response.data = Some(encoded)
        encoded
      }
  }
  if data.length() == 0 {
    return
  }
  response.headers.set(
    "ETag",
    {
      let builder = StringBuilder(size_hint=32)
      builder.write_char('"')
      builder.write_string(data.length().to_string())
      builder.write_char('-')
      write_fnv1a_hex(builder, data)
      builder.write_char('"')
      builder.to_string()
    },
  )
}

///|
/// Evaluate the request's precondition headers against the response's `ETag` /
/// `Last-Modified` validators, turning a successful response into
/// `304 Not Modified` or `412 Precondition Failed` as RFC 9110 §13 requires.
///
/// Preconditions select a representation, so error responses are left
/// untouched, as are ranged responses, whose `If-Range` handling happens where
/// the range is computed. Responses that opt out of caching with `no-store`
/// are treated as unvalidatable.
fn apply_preconditions(request : @http.Request, response : Response) -> Unit {
  if response.status < 200 ||
    response.status >= 300 ||
    response.status == 204 ||
    response.status == 205 ||
    response.status == 206 {
    return
  }
  // These are the only request headers `evaluate_preconditions` consults.
  let has_if_match = request.headers.contains(header_if_match)
  let has_if_none_match = request.headers.contains(header_if_none_match)
  let has_if_modified_since = request.headers.contains(header_if_modified_since)
  let has_if_unmodified_since = request.headers.contains(
    header_if_unmodified_since,
  )
  if !has_if_match &&
    !has_if_none_match &&
    !has_if_modified_since &&
    !has_if_unmodified_since {
    return
  }
  match get_header_ignore_case(response.headers, "Cache-Control") {
    Some(control) =>
      if contains_ignore_ascii_case(control.view(), "no-store".view()) {
        return
      }
    None => ()
  }
  let etag = if has_if_match || has_if_none_match {
    match get_header_ignore_case(response.headers, "ETag") {
      Some(existing) => existing
      None => ""
    }
  } else {
    ""
  }
  let mtime_secs = if has_if_modified_since || has_if_unmodified_since {
    match get_header_ignore_case(response.headers, "Last-Modified") {
      Some(value) =>
        match parse_http_date(value) {
          Some(seconds) => seconds
          None => 0L
        }
      None => 0L
    }
  } else {
    0L
  }
  let allows_not_modified = request.meth is @http.Get || request.meth is @http.Head
  match evaluate_preconditions(request, etag, mtime_secs, allows_not_modified) {
    PreconditionPass => ()
    PreconditionNotModified => {
      response.status = 304
      response.body = ""
      response.data = None
      ignore(remove_header_ignore_case(response.headers, "Content-Type"))
      ignore(remove_header_ignore_case(response.headers, "Content-Length"))
    }
    PreconditionFailed => {
      response.status = 412
      response.body = "412 Precondition Failed"
      response.data = None
      set_header_ignore_case(
        response.headers,
        "Content-Type",
        "text/plain; charset=utf-8",
      )
      ignore(remove_header_ignore_case(response.headers, "Content-Length"))
      ignore(remove_header_ignore_case(response.headers, "Content-Encoding"))
    }
  }
}

///|
/// Map a method string from the facade request onto the async HTTP crate's
/// method type. Unknown methods map to `POST` so `304 Not Modified` is never
/// produced for them (`apply_preconditions` only allows it for GET/HEAD).
fn request_method_from_string(meth : String) -> @http.RequestMethod {
  match meth.to_upper() {
    "GET" => @http.Get
    "HEAD" => @http.Head
    "POST" => @http.Post
    "PUT" => @http.Put
    "DELETE" => @http.Delete
    "CONNECT" => @http.Connect
    "OPTIONS" => @http.Options
    "TRACE" => @http.Trace
    "PATCH" => @http.Patch
    _ => @http.Post
  }
}

///|
/// Adapt the facade's request to the `@http.Request` shape
/// `apply_preconditions` consumes, so the offline `App::respond` path
/// evaluates conditional requests like the server does.
fn precondition_request(request : Request) -> @http.Request {
  let headers : @http.Headers = Map([])
  for name, value in request.headers {
    headers.set(@http.CaseInsensitiveString(name), value)
  }
  {
    meth: request_method_from_string(request.method),
    path: request.path,
    headers,
  }
}

///|
pub fn Feather::etag(self : Feather) -> Feather {
  ignore(self.app.etag())
  self
}
