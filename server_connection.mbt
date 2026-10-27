///|
pub suberror PayloadTooLarge

///|
let header_if_none_match : @http.CaseInsensitiveString = @http.CaseInsensitiveString(
  "If-None-Match",
)

///|
let header_if_match : @http.CaseInsensitiveString = @http.CaseInsensitiveString(
  "If-Match",
)

///|
let header_if_modified_since : @http.CaseInsensitiveString = @http.CaseInsensitiveString(
  "If-Modified-Since",
)

///|
let header_if_unmodified_since : @http.CaseInsensitiveString = @http.CaseInsensitiveString(
  "If-Unmodified-Since",
)

///|
let header_if_range : @http.CaseInsensitiveString = @http.CaseInsensitiveString(
  "If-Range",
)

///|
let header_range : @http.CaseInsensitiveString = @http.CaseInsensitiveString(
  "Range",
)

///|
let header_content_type : @http.CaseInsensitiveString = @http.CaseInsensitiveString(
  "Content-Type",
)

///|
let header_content_length : @http.CaseInsensitiveString = @http.CaseInsensitiveString(
  "Content-Length",
)

///|
let header_content_disposition : @http.CaseInsensitiveString = @http.CaseInsensitiveString(
  "Content-Disposition",
)

///|
let header_content_range : @http.CaseInsensitiveString = @http.CaseInsensitiveString(
  "Content-Range",
)

///|
let header_accept_ranges : @http.CaseInsensitiveString = @http.CaseInsensitiveString(
  "Accept-Ranges",
)

///|
let header_etag : @http.CaseInsensitiveString = @http.CaseInsensitiveString(
  "ETag",
)

///|
let header_last_modified : @http.CaseInsensitiveString = @http.CaseInsensitiveString(
  "Last-Modified",
)

///|
let header_cache_control : @http.CaseInsensitiveString = @http.CaseInsensitiveString(
  "Cache-Control",
)

///|
let header_set_cookie : @http.CaseInsensitiveString = @http.CaseInsensitiveString(
  "Set-Cookie",
)

///|
let header_date : @http.CaseInsensitiveString = @http.CaseInsensitiveString(
  "Date",
)

///|
let header_content_encoding : @http.CaseInsensitiveString = @http.CaseInsensitiveString(
  "Content-Encoding",
)

///|
let header_vary : @http.CaseInsensitiveString = @http.CaseInsensitiveString(
  "Vary",
)

///|
let header_x_accel_buffering : @http.CaseInsensitiveString = @http.CaseInsensitiveString(
  "X-Accel-Buffering",
)

///|
let header_expect : @http.CaseInsensitiveString = @http.CaseInsensitiveString(
  "Expect",
)

///|
let header_connection : @http.CaseInsensitiveString = @http.CaseInsensitiveString(
  "Connection",
)

///|
let header_location : @http.CaseInsensitiveString = @http.CaseInsensitiveString(
  "Location",
)

///|
/// Raised when a request body declares a content coding but cannot be decoded.
priv suberror MalformedRequestBody

///|
/// Raised when a request body declares a content coding this server cannot
/// decode. RFC 9110 §8.4.1 lets a recipient reject an unsupported coding with
/// `415 Unsupported Media Type` instead of handing compressed bytes to a
/// handler as if they were the representation.
priv suberror UnsupportedRequestBodyCoding

///|
/// How a request's `Content-Encoding` field relates to the one coding the
/// server can decode.
priv enum RequestBodyCoding {
  RequestBodyIdentity
  RequestBodyGzip
  RequestBodyUnsupported
}

///|
let cached_date_second : Ref[Int64] = Ref(-1L)

///|
let cached_date_value : Ref[String] = Ref("")

///|
/// `format_http_date` value for the current second.
/// The async runtime is single threaded, so the plain refs are safe.
fn cached_http_date(unix_seconds : Int64) -> String {
  if cached_date_second.val == unix_seconds {
    cached_date_value.val
  } else {
    let formatted = format_http_date(unix_seconds)
    cached_date_second.val = unix_seconds
    cached_date_value.val = formatted
    formatted
  }
}

///|
/// Send a response, stamping the mandatory `Date` header (RFC 7231 §7.1.1.2)
/// when the handler did not already provide one.
async fn send_with_date(
  conn : @http.ServerConnection,
  code : Int32,
  reason : String,
  headers : @http.Headers,
  cookies? : Array[@http.Cookie],
) -> Unit {
  if !headers.contains(header_date) {
    headers.set(header_date, cached_http_date(@async.now() / 1000L))
  }
  conn.send_response(code, reason, extra_headers=headers, cookies?)
}

///|
/// Size of the chunks read from a request body.
const BODY_READ_CHUNK_SIZE : Int32 = 65536

///|
/// Upper bound on the buffer pre-sized from `Content-Length`.
const BODY_SIZE_HINT_LIMIT : Int32 = 1048576

///|
/// `Content-Length` clamped to the body limit and the pre-size cap, or `0` when
/// the header is absent or malformed.
fn body_size_hint(request : @http.Request, limit : Int32) -> Int32 {
  let cap : Int32 = if limit < BODY_SIZE_HINT_LIMIT {
    limit
  } else {
    BODY_SIZE_HINT_LIMIT
  }
  if cap <= 0 {
    return 0
  }
  let view = match request.headers.get(header_content_length) {
    Some(value) => trim_ascii_space(value.view())
    None => return 0
  }
  let mut total = 0
  let mut i = 0
  while i < view.length() {
    let digit = view.unsafe_get(i).to_int() - 48
    if digit < 0 || digit > 9 {
      return 0
    }
    if total > cap / 10 {
      return cap
    }
    total = total * 10 + digit
    if total > cap {
      return cap
    }
    i = i + 1
  }
  total
}

///|
/// Whether a well-formed `Content-Length` already proves that the request body
/// exceeds `limit`.
///
/// Checking the declared length before reading lets an oversized upload be
/// rejected immediately instead of waiting for bytes that may never arrive.
/// Malformed values are left to the runtime body reader, which reports them as
/// a normal body-size failure.
fn declared_body_exceeds_limit(
  request : @http.Request,
  limit : Int32,
) -> Bool {
  let view = match request.headers.get(header_content_length) {
    Some(value) => trim_ascii_space(value.view())
    None => return false
  }
  if view.is_empty() {
    return false
  }
  let limit64 = limit.to_int64()
  let mut total = 0L
  let mut i = 0
  while i < view.length() {
    let digit = view.unsafe_get(i).to_int() - 48
    if digit < 0 || digit > 9 {
      return false
    }
    total = total * 10L + digit.to_int64()
    if total > limit64 {
      return true
    }
    i = i + 1
  }
  false
}

///|
/// Bytes that may be read from a gzip-coded request body before decoding.
///
/// The configured body limit applies to the decoded representation, but the
/// compressed input is slightly larger than an incompressible payload because
/// of the gzip header, deflate block framing and trailer. Allow that bounded
/// overhead here and enforce the real limit again after decompression.
fn gzip_body_read_limit(limit : Int32) -> Int32 {
  if limit < 0 {
    return limit
  }
  // Deflate's fixed-Huffman fallback can add roughly one bit per input byte,
  // on top of the gzip header, block framing and trailer. Leave enough room
  // for that worst case without letting the compressed input grow unbounded.
  let overhead = limit / 8 + 256
  if limit > 2147483647 - overhead {
    2147483647
  } else {
    limit + overhead
  }
}

///|
async fn read_body_bytes(
  reader : &@io.Reader,
  limit : Int32,
  size_hint~ : Int32 = 0,
) -> Bytes {
  let first = match reader.read_some(max_len=BODY_READ_CHUNK_SIZE) {
    None => return b""
    Some(chunk) => chunk
  }
  let mut total = first.length()
  if total > limit {
    raise PayloadTooLarge
  }
  let first_length = first.length()
  let hint : Int32 = if size_hint > first_length {
    if size_hint < limit {
      size_hint
    } else {
      limit
    }
  } else if first_length < limit {
    first_length
  } else {
    limit
  }
  let buffer = @buffer.Buffer::Buffer(size_hint=hint)
  buffer.write_bytes(first)
  let mut done = false
  while !done {
    match reader.read_some(max_len=BODY_READ_CHUNK_SIZE) {
      None => done = true
      Some(chunk) => {
        total = total + chunk.length()
        if total > limit {
          raise PayloadTooLarge
        }
        buffer.write_bytes(chunk)
      }
    }
  }
  buffer.to_bytes()
}

///|
async fn read_body(
  reader : &@io.Reader,
  limit : Int32,
  size_hint~ : Int32 = 0,
) -> String {
  @utf8.decode_lossy(read_body_bytes(reader, limit, size_hint~))
}

///|
/// Decode a gzip-compressed request body.
///
/// The decompressed size is bounded by `limit` so a small compressed payload
/// cannot expand without bound; a corrupt stream raises
/// `MalformedRequestBody`.
async fn decode_gzip_body(data : Bytes, limit : Int32) -> Bytes {
  let reader = @io.MemoryReader(async fn(writer) { writer.write(data) })
  defer reader.close()
  let decoder = @gzip.Decoder::Decoder(reader)
  let hint : Int32 = if data.length() * 4 < limit {
    data.length() * 4
  } else {
    limit
  }
  let buffer = @buffer.Buffer::Buffer(size_hint=hint)
  let mut total = 0
  let mut done = false
  while !done {
    let chunk = decoder.read_some(max_len=BODY_READ_CHUNK_SIZE) catch {
      _ => raise MalformedRequestBody
    }
    match chunk {
      None => done = true
      Some(chunk) => {
        total = total + chunk.length()
        if total > limit {
          raise PayloadTooLarge
        }
        buffer.write_bytes(chunk)
      }
    }
  }
  buffer.to_bytes()
}

///|
/// Authority of an absolute-form request target, or `None` for origin-form,
/// authority-form and malformed targets.
fn absolute_target_authority(path : String) -> String? {
  let view = path.view()
  let length = view.length()
  if length == 0 || view.unsafe_get(0) == ('/' : UInt16) {
    return None
  }
  let separator = match view.find("://") {
    Some(index) => index
    None => return None
  }
  let first = view.unsafe_get(0).to_int()
  if !((first >= 65 && first <= 90) || (first >= 97 && first <= 122)) {
    return None
  }
  let mut i = 1
  while i < separator {
    if !is_uri_scheme_character(view.unsafe_get(i).to_int()) {
      return None
    }
    i = i + 1
  }
  let authority_start = separator + 3
  let mut end = authority_start
  while end < length {
    let code = view.unsafe_get(end)
    if code == ('/' : UInt16) ||
      code == ('?' : UInt16) ||
      code == ('#' : UInt16) {
      break
    }
    end = end + 1
  }
  if end == authority_start {
    return None
  }
  let authority = view[authority_start:end]
  // Userinfo is not part of an HTTP Host value; the host follows the last `@`.
  let host = match authority.find("@") {
    Some(_) => {
      let mut last = 0
      for index in 0..<authority.length() {
        if authority.unsafe_get(index) == ('@' : UInt16) {
          last = index + 1
        }
      }
      authority[last:]
    }
    None => authority
  }
  if host.is_empty() {
    None
  } else {
    match host_authority_host(host) {
      Some(_) => Some(host.to_owned())
      // A malformed authority must not be installed as `Host` or used to
      // reduce a target that only resembles an absolute URI.
      None => None
    }
  }
}

///|
/// Normalize an absolute-form request target before routing or static lookup.
/// Origin-form and authority-form targets are copied unchanged. For an
/// absolute-form target the authority replaces `Host`, as required when an
/// origin server receives a request through a proxy-style target.
fn normalize_http_request(request : @http.Request) -> @http.Request {
  let path = normalize_request_target(request.path)
  let authority = absolute_target_authority(request.path)
  match authority {
    Some(authority) => {
      request.headers.set(@http.CaseInsensitiveString("Host"), authority)
      { meth: request.meth, path, headers: request.headers }
    }
    None => if path == request.path {
      request
    } else {
      { meth: request.meth, path, headers: request.headers }
    }
  }
}

///|
fn request_method_to_string(meth : @http.RequestMethod) -> String {
  match meth {
    @http.Get => "GET"
    @http.Head => "HEAD"
    @http.Post => "POST"
    @http.Put => "PUT"
    @http.Delete => "DELETE"
    @http.Connect => "CONNECT"
    @http.Options => "OPTIONS"
    @http.Trace => "TRACE"
    @http.Patch => "PATCH"
  }
}

///|
/// Classify a request's `Content-Encoding` field.
///
/// A body may be decoded only when the field names exactly one `gzip` coding
/// (or its historical `x-gzip` alias), optionally combined with `identity`.
/// Repeated gzip codings would require two decode passes and any unknown
/// coding selects bytes this server cannot decode; both are reported as
/// unsupported instead of silently treating compressed bytes as the body.
fn request_body_coding(value : StringView) -> RequestBodyCoding {
  let mut gzip_count = 0
  let mut unsupported = false
  for part in value.split(",") {
    let coding = trim_ascii_space(part)
    if coding.is_empty() || coding.equal_ignore_ascii_case("identity".view()) {
      continue
    }
    if coding.equal_ignore_ascii_case("gzip".view()) ||
      coding.equal_ignore_ascii_case("x-gzip".view()) {
      gzip_count = gzip_count + 1
    } else {
      unsupported = true
    }
  }
  if unsupported || gzip_count > 1 {
    RequestBodyUnsupported
  } else if gzip_count == 1 {
    RequestBodyGzip
  } else {
    RequestBodyIdentity
  }
}

///|
/// Whether a response `Content-Encoding` field names any coding other than
/// `identity`. A header carrying only `identity` still selects the unencoded
/// representation and must obey an explicit refusal of identity.
fn content_encoding_has_non_identity(value : StringView) -> Bool {
  for part in value.split(",") {
    let coding = trim_ascii_space(part)
    if !coding.is_empty() &&
      !coding.equal_ignore_ascii_case("identity".view()) {
      return true
    }
  }
  false
}

///|
/// Whether every non-identity coding in a response `Content-Encoding` field is
/// acceptable to the client. A missing request header places no restriction on
/// the encoding; an explicitly empty one accepts identity only.
fn content_encoding_is_acceptable(
  accept_encoding : String?,
  value : StringView,
) -> Bool {
  let entries = match accept_encoding {
    None => return true
    Some(header) => encoding_entries_cached(header)
  }
  for part in value.split(",") {
    let coding = trim_ascii_space(part)
    if coding.is_empty() || coding.equal_ignore_ascii_case("identity".view()) {
      continue
    }
    if encoding_quality_from(entries, coding) <= 0 {
      return false
    }
  }
  true
}

///|
/// Read an asynchronous endpoint's request body under the application request
/// timeout. Long-lived SSE/stream/WebSocket handlers themselves are exempt from
/// the timeout, but a client must not be able to hold the connection open
/// forever by declaring a body it never sends.
async fn request_from_http_with_timeout(
  app : App,
  request : @http.Request,
  body : &@io.Reader,
  conn : @http.ServerConnection,
) -> (Request, Bytes?)? {
  let read = () => {
    let (req, raw_body) = request_from_http(request, body, app.max_body_size)
    Some((req, raw_body))
  }
  let head = request.meth is @http.Head
  if app.timeout > 0 {
    @async.with_timeout(app.timeout, read) catch {
      @async.TimeoutError => {
        send_error_and_close(conn, 504, "504 Gateway Timeout", head)
        return None
      }
      PayloadTooLarge => {
        send_error_and_close(conn, 413, "413 Payload Too Large", head)
        return None
      }
      MalformedRequestBody => {
        send_simple(conn, 400, "400 Bad Request", head)
        return None
      }
      UnsupportedRequestBodyCoding => {
        send_error_and_close(
          conn, 415, "415 Unsupported Media Type", head,
        )
        return None
      }
      _ => {
        send_error_and_close(conn, 500, "500 Internal Server Error", head)
        return None
      }
    }
  } else {
    read() catch {
      PayloadTooLarge => {
        send_error_and_close(conn, 413, "413 Payload Too Large", head)
        return None
      }
      MalformedRequestBody => {
        send_simple(conn, 400, "400 Bad Request", head)
        return None
      }
      UnsupportedRequestBodyCoding => {
        send_error_and_close(
          conn, 415, "415 Unsupported Media Type", head,
        )
        return None
      }
      _ => {
        send_error_and_close(conn, 500, "500 Internal Server Error", head)
        return None
      }
    }
  }
}

///|
/// Build the framework `Request` from an HTTP request and its body stream.
///
/// The second component carries the body exactly as received (after gzip
/// decoding) when those bytes are not valid UTF-8, so binary payloads stay
/// intact; it is `None` for well-formed UTF-8 bodies, where `Request::body`
/// already is the exact text.
async fn request_from_http(
  request : @http.Request,
  body : &@io.Reader,
  max_body_size : Int32,
) -> (Request, Bytes?) {
  let coding = match request.headers.get(header_content_encoding) {
    Some(value) => request_body_coding(value.view())
    None => RequestBodyIdentity
  }
  if coding is RequestBodyUnsupported {
    raise UnsupportedRequestBodyCoding
  }
  let gzip_encoded = coding is RequestBodyGzip
  let headers : Map[String, String] = Map([], capacity=request.headers.length())
  for name, value in request.headers {
    let text = match request_header_name_cache.get(name) {
      Some(text) => {
        cache_touch(request_header_name_ages, name)
        text
      }
      None => {
        let text = name.to_string()
        cache_set(
          request_header_name_cache,
          request_header_name_ages,
          HEADER_NAME_CACHE_LIMIT,
          name,
          text,
        )
        text
      }
    }
    let stale_length = gzip_encoded &&
      (
        text.view().equal_ignore_ascii_case("content-encoding".view()) ||
        text.view().equal_ignore_ascii_case("content-length".view())
      )
    if !stale_length {
      headers.set(text, value)
    }
  }
  let read_limit = if gzip_encoded {
    gzip_body_read_limit(max_body_size)
  } else {
    max_body_size
  }
  let body_hint = body_size_hint(request, read_limit)
  let raw_body = if gzip_encoded {
    decode_gzip_body(
      read_body_bytes(body, read_limit, size_hint=body_hint),
      max_body_size,
    )
  } else {
    read_body_bytes(body, read_limit, size_hint=body_hint)
  }
  let strict_text : String? = Some(@utf8.decode(raw_body)) catch {
    @utf8.Malformed(_) => None
  }
  let (body_text, preserved) = match strict_text {
    Some(text) => (text, None)
    None => (@utf8.decode_lossy(raw_body), Some(raw_body))
  }
  (
    {
      method: request_method_to_string(request.meth),
      path: request.path,
      headers,
      body: body_text,
    },
    preserved,
  )
}

///|
/// Bounded caches of the most recently built validators, keyed by file path.
/// Each entry records the `(size, mtime)` it was built from, so a changed file
/// replaces its stale validators on the next request. The precompressed
/// representation has its own cache because it has different size and mtime
/// but keeps the `Content-Type` derived from the original path.
let validators_cache : Map[
  String,
  (Int64, Int64, Int32, (String, String), String),
] = Map([])

///|
/// Recency ticks for `validators_cache`, driving the shared LRU eviction.
let validators_cache_ages : Map[String, Int32] = Map([])

///|
/// Validators for precompressed representations, keyed by the source path.
let gzip_validators_cache : Map[
  String,
  (Int64, Int64, Int32, (String, String), String),
] = Map([])

///|
/// Recency ticks for `gzip_validators_cache`.
let gzip_validators_cache_ages : Map[String, Int32] = Map([])

///|
/// Maximum number of files tracked by each validators cache.
const VALIDATORS_CACHE_LIMIT : Int32 = 64

///|
/// Build the `ETag`, `Last-Modified` and `Content-Type` for a file from its
/// path, size and modification time.
fn file_validators(
  path : String,
  size : Int64,
  mtime_secs : Int64,
  mtime_nanos : Int32,
  cache_key~ : String,
  gzip~ : Bool = false,
) -> (String, String, String) {
  let cache = if gzip { gzip_validators_cache } else { validators_cache }
  let ages = if gzip {
    gzip_validators_cache_ages
  } else {
    validators_cache_ages
  }
  match cache.get(cache_key) {
    Some((cached_size, cached_secs, cached_nanos, value, content_type)) =>
      if cached_size == size &&
        cached_secs == mtime_secs &&
        cached_nanos == mtime_nanos {
        cache_touch(ages, cache_key)
        return (value.0, value.1, content_type)
      }
    None => ()
  }
  let etag = "\"" +
    size.to_string() +
    "-" +
    mtime_secs.to_string() +
    "-" +
    mtime_nanos.to_string() +
    "\""
  let value = (etag, format_http_date(mtime_secs))
  let content_type = mime_type_for(path)
  cache_set(
    cache,
    ages,
    VALIDATORS_CACHE_LIMIT,
    cache_key,
    (size, mtime_secs, mtime_nanos, value, content_type),
  )
  (etag, value.1, content_type)
}

///|
/// Whether an `If-Range` condition still matches the representation, in which
/// case a `Range` request may be served partially.
fn if_range_allows(
  request : @http.Request,
  etag : String,
  mtime_secs : Int64,
) -> Bool {
  match request.headers.get(header_if_range) {
    Some(value) => {
      // RFC 9110 §13.1.5: entity-tags use the strong comparison function, so a
      // weak tag never matches; HTTP-dates require an exact match.
      let token = trim_ascii_space(value.view())
      let etag_view = etag.view()
      if etag != "" &&
        !etag_view.has_prefix("W/") &&
        !token.has_prefix("W/") &&
        token == etag_view {
        true
      } else {
        match parse_http_date_view(token) {
          // The epoch is a real `Last-Modified` value (it is also what an
          // unknown filesystem mtime advertises), so compare it exactly rather
          // than using zero as an "unknown" sentinel here.
          Some(since) => mtime_secs == since
          None => false
        }
      }
    }
    None => true
  }
}

///|
async fn send_file_response(
  conn : @http.ServerConnection,
  response : Response,
  file : FileResponse,
  head : Bool,
  request : @http.Request,
  connect~ : Bool = false,
  auto_etag~ : Bool = true,
  compress_enabled~ : Bool = false,
  compress_min_size~ : Int32 = 1024,
) -> Unit {
  // A 2xx CONNECT response establishes a tunnel rather than carrying a
  // representation, so the prepared file is not sent and no length is framed.
  let connect_tunnel = connect &&
    response.status >= 200 &&
    response.status < 300
  if connect_tunnel {
    let headers = static_base_headers(response.headers, response.cookies, 1)
    headers.remove(header_content_length)
    clear_bodyless_representation_headers(headers)
    send_with_date(
      conn,
      response.status,
      status_text(response.status),
      headers,
      cookies=response.cookies,
    )
    conn.end_response()
    return
  }
  let handle = @fs.open(file.path, mode=@fs.ReadOnly) catch {
    _ => {
      // A bodyless status does not need the file's bytes, so a missing file
      // must not override an intentional 1xx/204/205/304 response.
      if status_allows_body(response.status) {
        send_static_error(
          conn,
          response.headers,
          response.cookies,
          head,
          404,
          "404 Not Found",
          false,
        )
      } else {
        send_response(conn, response, head, connect~)
      }
      return
    }
  }
  defer handle.close()
  if handle.kind() is @fs.Directory {
    // The same rule applies to a path that names a directory: for a bodyless
    // status there is no file body to send, so report the requested status.
    if status_allows_body(response.status) {
      send_static_error(
        conn,
        response.headers,
        response.cookies,
        head,
        404,
        "404 Not Found",
        false,
      )
    } else {
      send_response(conn, response, head, connect~)
    }
    return
  }
  let size = handle.size() catch {
    _ => {
      // Size is only needed to frame a body. A bodyless status still has a
      // well-defined response without it.
      if status_allows_body(response.status) {
        send_static_error(
          conn,
          response.headers,
          response.cookies,
          head,
          500,
          "500 Internal Server Error",
          false,
        )
      } else {
        send_response(conn, response, head, connect~)
      }
      return
    }
  }
  let mtime = handle.mtime() catch { _ => (0L, 0) }
  let (mtime_secs, mtime_nanos) = mtime
  let (etag, last_modified, content_type_value) = file_validators(
    file.path,
    size,
    mtime_secs,
    mtime_nanos,
    cache_key=file.path,
  )
  let accept_encoding = request.headers.get(header_accept_encoding)
  let refuses_identity = match accept_encoding {
    Some(value) => accept_encoding_refuses_identity(value)
    None => false
  }
  let existing_encoding = get_header_ignore_case(
    response.headers,
    "Content-Encoding",
  )
  let existing_non_identity = match existing_encoding {
    Some(value) => content_encoding_has_non_identity(value.view())
    None => false
  }
  // A handler may hand over an already encoded file. Treat that as the
  // selected representation instead of assuming the bytes are identity: the
  // coding has to be acceptable, but refusing identity alone must not reject
  // an acceptable non-identity coding.
  let existing_encoding_acceptable = if existing_non_identity {
    match existing_encoding {
      Some(value) =>
        content_encoding_is_acceptable(accept_encoding, value.view())
      None => true
    }
  } else {
    !refuses_identity
  }
  let effective_content_type = match
    get_header_ignore_case(response.headers, "Content-Type") {
    Some(value) => value
    None =>
      if file.content_type != "" {
        file.content_type
      } else {
        content_type_value
      }
  }
  let no_transform = match
    get_header_ignore_case(response.headers, "Cache-Control") {
    Some(control) =>
      cache_control_has_directive(control.view(), "no-transform".view())
    None => false
  }
  // A file response is a representation like any other, so the application's
  // gzip setting applies when the media type is compressible and the handler
  // did not opt out or provide an encoding of its own. Ranges and validators
  // below are computed over the representation that is actually sent.
  let compressible = compress_enabled &&
    status_allows_body(response.status) &&
    response.status != 206 &&
    !no_transform &&
    // `identity` selects the unencoded representation, not "leave the bytes
    // alone": the compression stage may replace it exactly like a response
    // with no Content-Encoding at all. A non-identity coding is already the
    // selected representation and is kept below.
    !existing_non_identity &&
    get_header_ignore_case(response.headers, "Content-Range") is None &&
    content_type_is_compressible(effective_content_type.view())
  let mut compressed_body : Bytes? = None
  if compressible {
    match accept_encoding {
      Some(value) =>
        if accept_encoding_allows_gzip_cached(value) &&
          (
            refuses_identity ||
            size >= compress_min_size.to_int64()
          ) {
          match read_file_bytes(handle, size) {
            Some(raw) => {
              let compressed : Bytes? = Some(gzip_compress(raw)) catch {
                _ => None
              }
              match compressed {
                Some(bytes) =>
                  if refuses_identity || bytes.length() < raw.length() {
                    compressed_body = Some(bytes)
                  }
                None => ()
              }
            }
            None => ()
          }
        }
      None => ()
    }
  }
  let serving_gzip = compressed_body is Some(_)
  if !serving_gzip &&
    !existing_encoding_acceptable &&
    status_allows_body(response.status) {
    send_static_error(
      conn,
      response.headers,
      response.cookies,
      head,
      406,
      "406 Not Acceptable",
      false,
      vary_encoding=true,
    )
    return
  }
  // The selected representation always depends on `Accept-Encoding`: even
  // when application compression is off and the handler supplied no coding,
  // this URL answers 406 to a client that refuses identity. A shared cache must
  // not reuse the identity 200 for that client, so vary unconditionally.
  let vary_encoding = true
  // Capture the validator supplied by the handler before compression weakens
  // it, so a satisfied strong `If-Match` is not re-checked against `W/...`.
  let handler_etag = get_header_ignore_case(response.headers, "ETag").unwrap_or(
    "",
  )
  // `Context::no_etag` suppresses only the generated validator; an explicit
  // handler/middleware ETag is still preserved below.
  let generated_etag = if auto_etag {
    if serving_gzip {
      "W/" + etag
    } else {
      etag
    }
  } else {
    ""
  }
  let headers = static_base_headers(response.headers, response.cookies, 6)
  if !headers.contains(header_content_type) {
    headers.set(header_content_type, effective_content_type)
  }
  // `static_base_headers` strips a representation's coding because the static
  // path chooses it itself. A queued file is different: a coding present at
  // this point was supplied by the handler after `Context::file` and describes
  // the bytes being sent, so it must survive.
  if existing_non_identity {
    match existing_encoding {
      Some(value) => headers.set(header_content_encoding, value)
      None => ()
    }
  }
  if serving_gzip {
    headers.set(header_content_encoding, "gzip")
    // A transformed representation is only weakly equivalent to the original
    // file, so an ETag supplied by a handler must become weak as well.
    match get_header_ignore_case(response.headers, "ETag") {
      Some(value) =>
        if !value.has_prefix("W/") {
          headers.set(header_etag, "W/" + value)
        }
      None => ()
    }
  }
  if generated_etag != "" && !headers.contains(header_etag) {
    headers.set(header_etag, generated_etag)
  }
  if !headers.contains(header_last_modified) {
    headers.set(header_last_modified, last_modified)
  }
  if vary_encoding {
    add_vary_header(headers, "Accept-Encoding")
  }
  // A handler may override `ETag` / `Last-Modified`; preconditions must be
  // evaluated against the validators the response actually advertises.
  let effective_etag = headers.get(header_etag).unwrap_or("")
  let effective_mtime = match headers.get(header_last_modified) {
    Some(value) =>
      match parse_http_date_view(trim_ascii_space(value.view())) {
        Some(seconds) => seconds
        None => mtime_secs
      }
    None => mtime_secs
  }
  if status_allows_preconditions(response.status) {
    let (precondition_input, allows_not_modified) = precondition_input_http(
      request,
    )
    let remaining_preconditions = drop_satisfied_if_match(
      precondition_input, handler_etag,
    )
    match
      evaluate_preconditions_input(
        remaining_preconditions,
        effective_etag,
        Some(effective_mtime),
        allows_not_modified,
      ) {
      PreconditionFailed => {
        send_static_error(
          conn,
          response.headers,
          response.cookies,
          head,
          412,
          "412 Precondition Failed",
          false,
          vary_encoding=vary_encoding,
        )
        return
      }
      PreconditionNotModified => {
        headers.remove(header_content_length)
        headers.remove(header_content_type)
        headers.remove(header_content_disposition)
        send_with_date(
          conn,
          304,
          "Not Modified",
          headers,
          cookies=response.cookies,
        )
        conn.end_response()
        return
      }
      PreconditionPass => ()
    }
  }
  let representation_size = match compressed_body {
    Some(bytes) => bytes.length().to_int64()
    None => size
  }
  let mut status = response.status
  let mut start = 0L
  let mut length = representation_size
  if response.status == 200 && request.meth is @http.Get {
    match request.headers.get(header_range) {
      Some(value) =>
        if if_range_allows(request, effective_etag, effective_mtime) {
          match parse_byte_range(value, representation_size) {
            ByteRangeSpec(range_start, range_end) => {
              status = 206
              start = range_start
              length = range_end - range_start + 1L
            }
            ByteRangeInvalid => {
              headers.remove(header_content_length)
              headers.remove(header_content_type)
              headers.remove(header_content_encoding)
              headers.remove(header_content_disposition)
              // The 416 body is not the selected representation, so its
              // validators must not describe the error response as if it were
              // a cacheable file.
              headers.remove(header_etag)
              headers.remove(header_last_modified)
              headers.set(
                header_content_range,
                "bytes */" + representation_size.to_string(),
              )
              // The resource supports ranges even when this particular range
              // is unsatisfiable; keep the 416 consistent with the 200/206
              // responses and with the static-file path.
              headers.set(header_accept_ranges, "bytes")
              if vary_encoding {
                add_vary_header(headers, "Accept-Encoding")
              }
              send_with_date(
                conn,
                416,
                status_text(416),
                headers,
                cookies=response.cookies,
              )
              conn.end_response()
              return
            }
            ByteRangeFull => ()
          }
        }
      None => ()
    }
  }
  if status == 206 {
    headers.set(
      header_content_range,
      "bytes " +
      start.to_string() +
      "-" +
      (start + length - 1L).to_string() +
      "/" +
      representation_size.to_string(),
    )
  }
  if !headers.contains(header_accept_ranges) {
    headers.set(header_accept_ranges, "bytes")
  }
  let body_allowed = status_allows_body(status)
  if body_allowed {
    headers.set(header_content_length, length.to_string())
  } else {
    headers.remove(header_content_length)
    clear_bodyless_representation_headers(
      headers, keep_validators=status == 304,
    )
    if status == 205 {
      // `205 Reset Content` must still frame its body as zero length, for
      // GET and HEAD alike.
      headers.set(header_content_length, "0")
    }
  }
  send_with_date(
    conn,
    status,
    status_text(status),
    headers,
    cookies=response.cookies,
  )
  if !head && body_allowed && length > 0L {
    match compressed_body {
      Some(bytes) => write_bytes_range(conn, bytes, start, length)
      None => write_file_range(conn, handle, start, length)
    }
  }
  conn.end_response()
}

///|
/// Bounded cache of formatted peer hosts, keyed by peer address.
let peer_host_cache : Map[@socket.Addr, String] = Map([])

///|
/// Recency ticks for `peer_host_cache`.
let peer_host_cache_ages : Map[@socket.Addr, Int32] = Map([])

///|
/// Maximum number of peer addresses tracked by `peer_host_cache`.
const PEER_HOST_CACHE_LIMIT : Int32 = 64

///|
/// Host part of a peer address, without the ephemeral port.
///
/// Recorded as the `remote_addr` context state so IP-based logic (logging,
/// `Context::ip`, rate limiting) keys by client rather than by connection.
fn socket_addr_host(addr : @socket.Addr) -> String {
  match peer_host_cache.get(addr) {
    Some(host) => {
      cache_touch(peer_host_cache_ages, addr)
      host
    }
    None => {
      let host = if addr.is_ipv6() {
        let text = addr.to_string()
        match text.find("]") {
          Some(index) => text[:index + 1].to_owned()
          None => text
        }
      } else {
        let ip = addr.ip()
        "\{ip >> 24}.\{(ip >> 16) & 255}.\{(ip >> 8) & 255}.\{ip & 255}"
      }
      cache_set(
        peer_host_cache,
        peer_host_cache_ages,
        PEER_HOST_CACHE_LIMIT,
        addr,
        host,
      )
      host
    }
  }
}

///|
/// UTF-8 byte length of the text `encode_utf8_lossy` would produce: a valid
/// surrogate pair counts as four bytes and every other lone surrogate as the
/// three bytes of U+FFFD. Unlike `@utf8.encode` this never aborts, so it can
/// size an arbitrary caller-supplied string.
fn utf8_byte_length_lossy(view : StringView) -> Int32 {
  let length = view.length()
  let mut total = 0
  let mut i = 0
  while i < length {
    let unit = view.unsafe_get(i)
    let code = unit.to_int()
    if code < 0x80 {
      total = total + 1
    } else if code < 0x800 {
      total = total + 2
    } else if unit.is_leading_surrogate() {
      if i + 1 < length && view.unsafe_get(i + 1).is_trailing_surrogate() {
        total = total + 4
        i = i + 1
      } else {
        total = total + 3
      }
    } else {
      total = total + 3
    }
    i = i + 1
  }
  total
}

///|
/// Bounded cache of `CaseInsensitiveString` header keys.
let header_name_cache : Map[String, @http.CaseInsensitiveString] = Map([])

///|
/// Recency ticks for `header_name_cache`.
let header_name_cache_ages : Map[String, Int32] = Map([])

///|
/// Maximum number of header names tracked by `header_name_cache`.
const HEADER_NAME_CACHE_LIMIT : Int32 = 128

///|
/// Request header name spellings, keyed case-insensitively.
let request_header_name_cache : Map[@http.CaseInsensitiveString, String] = Map([])

///|
/// Recency ticks for `request_header_name_cache`.
let request_header_name_ages : Map[@http.CaseInsensitiveString, Int32] = Map([])

///|
fn header_key(name : String) -> @http.CaseInsensitiveString {
  if name == "Content-Type" {
    return header_content_type
  } else if name == "Content-Length" {
    return header_content_length
  } else if name == "ETag" {
    return header_etag
  } else if name == "Last-Modified" {
    return header_last_modified
  } else if name == "Cache-Control" {
    return header_cache_control
  } else if name == "Set-Cookie" {
    return header_set_cookie
  } else if name == "Vary" {
    return header_vary
  } else if name == "Content-Encoding" {
    return header_content_encoding
  } else if name == "Content-Range" {
    return header_content_range
  } else if name == "Accept-Ranges" {
    return header_accept_ranges
  } else if name == "Location" {
    return header_location
  } else if name == "Date" {
    return header_date
  }
  match header_name_cache.get(name) {
    Some(key) => {
      cache_touch(header_name_cache_ages, name)
      key
    }
    None => {
      let key = @http.CaseInsensitiveString(name)
      cache_set(
        header_name_cache,
        header_name_cache_ages,
        HEADER_NAME_CACHE_LIMIT,
        name,
        key,
      )
      key
    }
  }
}

///|
async fn send_response(
  conn : @http.ServerConnection,
  response : Response,
  head : Bool,
  connect~ : Bool = false,
) -> Unit {
  let headers : @http.Headers = Map([], capacity=response.headers.length() + 1)
  for name, value in response.headers {
    if name.view().equal_ignore_ascii_case("transfer-encoding".view()) ||
      name.view().equal_ignore_ascii_case("connection".view()) {
      continue
    }
    headers.set(header_key(name), value)
  }
  // RFC 9110 §9.3.6: a 2xx response to CONNECT has no content and must not
  // carry Content-Length or Transfer-Encoding. The runtime refuses to write a
  // body for such a response, so framing it with a length would abort the
  // connection.
  let connect_tunnel = connect &&
    response.status >= 200 &&
    response.status < 300
  let body_allowed = !connect_tunnel &&
    response.status >= 200 &&
    response.status != 204 &&
    response.status != 205 &&
    response.status != 304
  if connect_tunnel || !body_allowed {
    clear_bodyless_representation_headers(
      headers, keep_validators=response.status == 304,
    )
  }
  let has_body = body_allowed &&
    (match response.data {
      Some(data) => data.length() > 0
      None => !response.body.is_empty()
    })
  let body_bytes : Bytes? = if head || !has_body {
    None
  } else {
    match response.data {
      Some(data) => Some(data)
      None => Some(encode_utf8_lossy(response.body.view()))
    }
  }
  if connect_tunnel {
    headers.remove(header_content_length)
  } else if has_body {
    // The body is fully buffered, so its byte length is authoritative: a
    // `Content-Length` seeded by middleware or copied from the handler must not
    // frame a different number of bytes than are actually written.
    let body_length = match body_bytes {
      Some(data) => data.length()
      None =>
        match response.data {
          Some(data) => data.length()
          None => utf8_byte_length_lossy(response.body.view())
        }
    }
    headers.set(header_content_length, body_length.to_string())
  } else if response.status == 205 {
    // `205 Reset Content` must indicate a zero-length body. The runtime emits
    // that framing automatically for GET but not for HEAD, so write it
    // explicitly to keep both methods on the same framing.
    headers.set(header_content_length, "0")
  } else if head && body_allowed {
    // A HEAD response has no bytes but must advertise the same zero length as
    // the matching GET, replacing any stale length seeded by middleware.
    headers.set(header_content_length, "0")
  } else {
    // An empty body is framed by the runtime (zero bytes); a `Content-Length`
    // seeded by middleware must not claim otherwise.
    headers.remove(header_content_length)
  }
  if response.cookies.length() > 0 {
    headers.remove(header_set_cookie)
  }
  send_with_date(
    conn,
    response.status,
    status_text(response.status),
    headers,
    cookies=response.cookies,
  )
  if !head && has_body {
    match body_bytes {
      Some(data) => conn.write(data)
      None => ()
    }
  }
  conn.end_response()
}

///|
async fn send_simple(
  conn : @http.ServerConnection,
  code : Int32,
  body : String,
  head : Bool,
) -> Unit {
  let bytes = encode_utf8_lossy(body.view())
  let headers : @http.Headers = Map([
    (header_content_type, "text/plain; charset=utf-8"),
    (header_content_length, bytes.length().to_string()),
  ])
  send_with_date(conn, code, status_text(code), headers)
  if !head {
    conn.write(bytes)
  }
  conn.end_response()
}

///|
/// Answer with a plain-text error and close the connection.
///
/// Used when the request body may still be unread: the per-connection loop
/// would otherwise block draining bytes the client may never send, letting a
/// stalled upload pin a connection indefinitely. Closing the connection after
/// the error is explicitly allowed for 413 (RFC 9110 §15.5.14) and keeps the
/// server from accumulating stuck tasks.
async fn send_error_and_close(
  conn : @http.ServerConnection,
  code : Int32,
  body : String,
  head : Bool,
) -> Unit {
  send_simple(conn, code, body, head) catch {
    _ => ()
  }
  conn.close()
}

///|
/// Reject an upload whose declared length already exceeds the body limit.
///
/// The response is sent immediately, then the connection briefly drains any
/// body bytes the client has already pipelined. Draining keeps the close
/// graceful for well-behaved clients that sent the whole body with the
/// headers, while the short timeout still bounds a client that only declared a
/// length and never uploaded anything.
async fn send_oversized_and_close(
  conn : @http.ServerConnection,
  head : Bool,
) -> Unit {
  send_simple(conn, 413, "413 Payload Too Large", head) catch {
    _ => ()
  }
  @async.with_timeout(50, () => conn.skip_request_body()) catch {
    _ => ()
  }
  conn.close()
}

