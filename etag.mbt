///|
/// Enable automatic `ETag` generation for dynamic responses.
///
/// A tag is derived from the response body (after compression, so encodings
/// keep distinct validators) for 2xx responses with a non-empty body and no
/// `ETag` of their own. Requests whose `If-None-Match` matches are answered
/// with an empty `304 Not Modified` for cacheable JSON and text APIs. Responses
/// that opt out with `Cache-Control: no-store` are left untouched.
pub fn App::etag(self : App) -> App {
  self.etag_enabled = true
  self
}

///|
/// Append the FNV-1a hash of `data` to `builder` as 16 lowercase hex digits.
fn write_fnv1a_hex(builder : StringBuilder, data : Bytes) -> Unit {
  let mut hash = 14695981039346656037UL
  let length = data.length()
  let mut i = 0
  while i + 8 <= length {
    hash = (hash ^ data.unsafe_get(i).to_uint64()) * 1099511628211UL
    hash = (hash ^ data.unsafe_get(i + 1).to_uint64()) * 1099511628211UL
    hash = (hash ^ data.unsafe_get(i + 2).to_uint64()) * 1099511628211UL
    hash = (hash ^ data.unsafe_get(i + 3).to_uint64()) * 1099511628211UL
    hash = (hash ^ data.unsafe_get(i + 4).to_uint64()) * 1099511628211UL
    hash = (hash ^ data.unsafe_get(i + 5).to_uint64()) * 1099511628211UL
    hash = (hash ^ data.unsafe_get(i + 6).to_uint64()) * 1099511628211UL
    hash = (hash ^ data.unsafe_get(i + 7).to_uint64()) * 1099511628211UL
    i = i + 8
  }
  while i < length {
    hash = (hash ^ data.unsafe_get(i).to_uint64()) * 1099511628211UL
    i = i + 1
  }
  for j = 0; j < 16; j = j + 1 {
    let nibble = ((hash >> ((15 - j) * 4)) & 15UL).to_int()
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
/// Validators and opt-out headers that affect ETag generation and precondition
/// checks, collected in one case-insensitive pass.
priv struct ResponseValidators {
  etag : String?
  cache_control : String?
  last_modified : String?
  content_range : Bool
}

///|
#inline
fn response_validators(headers : Map[String, String]) -> ResponseValidators {
  if headers.is_empty() {
    return {
      etag: None,
      cache_control: None,
      last_modified: None,
      content_range: false,
    }
  }
  let mut etag : String? = None
  let mut cache_control : String? = None
  let mut last_modified : String? = None
  let mut content_range = false
  headers.each(fn(key, value) {
    let name = key.view()
    if etag is None && name.equal_ignore_ascii_case("ETag".view()) {
      etag = Some(value)
    } else if cache_control is None &&
      name.equal_ignore_ascii_case("Cache-Control".view()) {
      cache_control = Some(value)
    } else if last_modified is None &&
      name.equal_ignore_ascii_case("Last-Modified".view()) {
      last_modified = Some(value)
    } else if name.equal_ignore_ascii_case("Content-Range".view()) {
      content_range = true
    }
  })
  { etag, cache_control, last_modified, content_range, }
}

///|
/// Give a successful response a strong `ETag` derived from its body when it
/// has none. Responses that opt out with `Cache-Control: no-store`, hold no
/// representation, or already carry a validator are left untouched.
fn apply_etag(response : Response) -> Unit {
  if response.status < 200 ||
    response.status >= 300 ||
    response.status == 204 ||
    response.status == 205 ||
    response.status == 206 {
    return
  }
  let has_representation = match response.data {
    Some(data) => data.length() > 0
    None => !response.body.is_empty()
  }
  if !has_representation {
    return
  }
  let validators = response_validators(response.headers)
  let no_store = match validators.cache_control {
    Some(control) =>
      cache_control_has_directive(control.view(), "no-store".view())
    None => false
  }
  if validators.etag is Some(_) || validators.content_range || no_store {
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
fn apply_preconditions_input(
  input : PreconditionInput,
  allows_not_modified : Bool,
  response : Response,
) -> Unit {
  if response.status < 200 ||
    response.status >= 300 ||
    response.status == 204 ||
    response.status == 205 ||
    response.status == 206 {
    return
  }
  let has_if_match = input.if_match is Some(_)
  let has_if_none_match = input.if_none_match is Some(_)
  let has_if_modified_since = input.if_modified_since is Some(_)
  let has_if_unmodified_since = input.if_unmodified_since is Some(_)
  if !has_if_match &&
    !has_if_none_match &&
    !has_if_modified_since &&
    !has_if_unmodified_since {
    return
  }
  let mut etag = ""
  let mut mtime_secs = 0L
  if !response.headers.is_empty() {
    let validators = response_validators(response.headers)
    match validators.cache_control {
      Some(control) =>
        if cache_control_has_directive(control.view(), "no-store".view()) {
          return
        }
      None => ()
    }
    if has_if_match || has_if_none_match {
      etag = match validators.etag {
        Some(existing) => existing
        None => ""
      }
    }
    if has_if_modified_since || has_if_unmodified_since {
      mtime_secs = match validators.last_modified {
        Some(value) =>
          match parse_http_date(value) {
            Some(seconds) => seconds
            None => 0L
          }
        None => 0L
      }
    }
  }
  match
    evaluate_preconditions_input(input, etag, mtime_secs, allows_not_modified) {
    PreconditionPass => ()
    PreconditionNotModified => {
      response.status = 304
      response.body = ""
      response.data = None
      ignore(remove_header_ignore_case(response.headers, "Content-Type"))
      ignore(remove_header_ignore_case(response.headers, "Content-Length"))
      ignore(remove_header_ignore_case(response.headers, "Content-Range"))
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
      ignore(remove_header_ignore_case(response.headers, "Content-Range"))
    }
  }
}

///|
/// Parse the precondition headers of a server request once, together with
/// whether the request method allows a `304 Not Modified` answer.
fn precondition_input_http(
  request : @http.Request,
) -> (PreconditionInput, Bool) {
  (
    precondition_input_from_http(request),
    request.meth is @http.Get || request.meth is @http.Head,
  )
}

///|
/// Parse the precondition headers of a facade request (the offline
/// `App::respond` path) once, together with whether the method allows a
/// `304 Not Modified` answer.
fn precondition_input_facade(request : Request) -> (PreconditionInput, Bool) {
  let method = normalize_method(request.method)
  (
    precondition_input_from_map(request.headers),
    method == "GET" || method == "HEAD",
  )
}

///|
/// Whether the input carries any precondition header at all.
fn has_precondition_headers(input : PreconditionInput) -> Bool {
  input.if_match is Some(_) ||
  input.if_none_match is Some(_) ||
  input.if_modified_since is Some(_) ||
  input.if_unmodified_since is Some(_)
}

///|
/// Tag the response and evaluate the preconditions that are left.
///
/// This is the last step of the response pipeline: the body is final, so the
/// generated ETag describes the bytes that are sent, and the preconditions
/// are decided against it.
fn finish_response(
  app : App,
  response : Response,
  remaining : PreconditionInput,
  allows_not_modified : Bool,
) -> Unit {
  if app.etag_enabled {
    apply_etag(response)
  }
  apply_preconditions_input(remaining, allows_not_modified, response)
}

///|
/// Check the request's preconditions against the validators the handler
/// supplied, before compression and ETag generation.
///
/// Returns whether a precondition already failed (turning the response into
/// `412 Precondition Failed`) together with the input that still has to be
/// evaluated after the response has been compressed and any generated ETag
/// added.
///
/// `If-Match` is only decided here when the response already carries an ETag;
/// otherwise a tag may be generated from the body later, so the condition is
/// deferred. A satisfied `If-Match` (and the `If-Unmodified-Since` it
/// suppresses) is removed from the returned input because compression weakens
/// the tag, and re-checking the weakened form would turn the earlier strong
/// match into a spurious failure.
fn precheck_preconditions(
  input : PreconditionInput,
  allows_not_modified : Bool,
  response : Response,
) -> (Bool, PreconditionInput) {
  if response.status < 200 ||
    response.status >= 300 ||
    response.status == 204 ||
    response.status == 205 ||
    response.status == 206 {
    return (false, input)
  }
  // Requests without any precondition header need no `Cache-Control` check;
  // the result is `(false, input)` either way.
  if !has_precondition_headers(input) {
    return (false, input)
  }
  if response.headers.is_empty() {
    return (false, input)
  }
  let validators = response_validators(response.headers)
  match validators.cache_control {
    Some(control) =>
      if cache_control_has_directive(control.view(), "no-store".view()) {
        return (false, input)
      }
    None => ()
  }
  let response_etag = validators.etag
  let response_mtime = validators.last_modified
  if response_etag is None && response_mtime is None {
    return (false, input)
  }
  let etag = match response_etag {
    Some(value) => value
    None => ""
  }
  let mtime_secs = match response_mtime {
    Some(value) =>
      match parse_http_date(value) {
        Some(seconds) => seconds
        None => 0L
      }
    None => 0L
  }
  // Without a handler ETag the `If-Match` outcome is not final: generation may
  // produce a matching tag. Defer the whole precondition set until after
  // generation, because `If-Match` must be evaluated before the other
  // conditions and a failure must not be masked by `If-None-Match`.
  if response_etag is None && input.if_match is Some(_) {
    return (false, input)
  }
  match
    evaluate_preconditions_input(input, etag, mtime_secs, allows_not_modified) {
    PreconditionFailed => {
      apply_preconditions_input(input, allows_not_modified, response)
      (true, input)
    }
    _ =>
      if response_etag is Some(_) && input.if_match is Some(_) {
        (
          false,
          {
            if_match: None,
            if_none_match: input.if_none_match,
            if_modified_since: input.if_modified_since,
            if_unmodified_since: None,
          },
        )
      } else {
        (false, input)
      }
  }
}

///|
pub fn Feather::etag(self : Feather) -> Feather {
  ignore(self.app.etag())
  self
}
