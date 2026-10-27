///|
/// Percent-encode an RFC 5987 `ext-value` payload. `url_encode` leaves the
/// RFC 3986 sub-delimiters `'` and `*` unescaped, but neither is an RFC 5987
/// `attr-char`, so a filename containing one would produce a malformed
/// `filename*` parameter.
fn encode_rfc5987_value(value : String) -> String {
  let encoded = url_encode(value)
  let view = encoded.view()
  let length = view.length()
  let mut needs_escape = false
  let mut scan = 0
  while scan < length {
    let code = view.unsafe_get(scan).to_int()
    if code == 39 || code == 42 {
      needs_escape = true
      break
    }
    scan = scan + 1
  }
  if !needs_escape {
    return encoded
  }
  let builder = StringBuilder(size_hint=length + 8)
  let mut i = 0
  while i < length {
    let code = view.unsafe_get(i).to_int()
    if code == 39 {
      builder.write_string("%27")
    } else if code == 42 {
      builder.write_string("%2A")
    } else {
      builder.write_char(code.unsafe_to_char())
    }
    i = i + 1
  }
  builder.to_string()
}

///|
/// Build a `Content-Disposition` field value with `disposition` (`attachment`
/// or `inline`) and the given file name, quoting and escaping the ASCII form
/// and appending an RFC 6266 `filename*` parameter for non-ASCII names.
fn content_disposition_value(disposition : String, name : String) -> String {
  let clean = strip_control_characters(name)
  let view = clean.view()
  let length = view.length()
  let escaped = StringBuilder(size_hint=length + 8)
  let mut has_non_ascii = false
  let mut i = 0
  while i < length {
    let code = view.unsafe_get(i).to_int()
    if code < 0x80 {
      if code == 34 {
        escaped.write_string("\\\"")
      } else if code == 92 {
        escaped.write_string("\\\\")
      } else {
        escaped.write_char(code.unsafe_to_char())
      }
    } else {
      has_non_ascii = true
      escaped.write_char('_')
    }
    i = i + 1
  }
  if has_non_ascii {
    disposition +
    "; filename=\"" +
    escaped.to_string() +
    "\"; filename*=UTF-8''" +
    encode_rfc5987_value(clean)
  } else {
    disposition + "; filename=\"" + escaped.to_string() + "\""
  }
}

///|
fn content_disposition_attachment(name : String) -> String {
  content_disposition_value("attachment", name)
}

///|
/// Run the cleanups registered with `Context::defer_cleanup`, last
/// registered first. A cleanup that raises does not prevent the remaining
/// cleanups from running: the error is swallowed and the loop continues, so
/// resource release is best-effort and never masks the request outcome.
pub fn Context::run_cleanups(self : Context) -> Unit {
  while self.cleanups.length() > 0 {
    match self.cleanups.pop() {
      Some(cleanup) => cleanup() catch { _ => () }
      None => ()
    }
  }
}

///|
pub fn Context::file(
  self : Context,
  status : Int32,
  path : String,
  content_type? : String,
  download_name? : String,
) -> Unit {
  let resolved_type = match content_type {
    Some(content_type) => content_type
    None => mime_type_for(path)
  }
  self.response.status = status
  self.response.body = ""
  self.response.data = None
  clear_replaced_body_headers(self.response.headers)
  set_header_ignore_case(self.response.headers, "Content-Type", resolved_type)
  match download_name {
    Some(name) =>
      set_header_ignore_case(
        self.response.headers,
        "Content-Disposition",
        content_disposition_attachment(name),
      )
    None => ()
  }
  self.file = Some({ path, content_type: resolved_type, })
}

///|
pub fn Context::file_response(self : Context) -> FileResponse? {
  self.file
}

///|
/// Set `Content-Disposition: attachment` with `filename`, so browsers download
/// the response body instead of rendering it. The header can accompany any
/// body set through `Context::file`, `Context::text`, `Context::bytes` or
/// `Context::json`. The name is quoted and escaped, and non-ASCII names also
/// receive an RFC 6266 `filename*` parameter.
pub fn Context::attachment(self : Context, filename : String) -> Unit {
  set_header_ignore_case(
    self.response.headers,
    "Content-Disposition",
    content_disposition_value("attachment", filename),
  )
}

///|
/// Set `Content-Disposition: inline` with `filename`, keeping the response
/// eligible for in-place rendering (for example an image or PDF) while still
/// naming the payload. Escaping and non-ASCII handling follow
/// `Context::attachment`.
pub fn Context::inline(self : Context, filename : String) -> Unit {
  set_header_ignore_case(
    self.response.headers,
    "Content-Disposition",
    content_disposition_value("inline", filename),
  )
}

