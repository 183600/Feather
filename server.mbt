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
/// Normalize an absolute-form request target before routing or static lookup.
/// Origin-form and authority-form targets are copied unchanged.
fn normalize_http_request(request : @http.Request) -> @http.Request {
  let path = normalize_request_target(request.path)
  if path == request.path {
    request
  } else {
    { meth: request.meth, path, headers: request.headers }
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
/// Whether a request's `Content-Encoding` field describes exactly one `gzip`
/// coding, optionally combined with `identity`, so the body can be decoded by
/// a single gzip pass. Repeated or unknown codings are left untouched because
/// decoding only one of them would corrupt the body.
fn request_content_encoding_is_gzip(value : StringView) -> Bool {
  let mut gzip_count = 0
  let mut unsupported = false
  for part in value.split(",") {
    let coding = trim_ascii_space(part)
    if coding.is_empty() || coding.equal_ignore_ascii_case("identity".view()) {
      continue
    }
    if coding.equal_ignore_ascii_case("gzip".view()) {
      gzip_count = gzip_count + 1
    } else {
      unsupported = true
    }
  }
  gzip_count == 1 && !unsupported
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
  let gzip_encoded = match request.headers.get(header_content_encoding) {
    Some(value) => request_content_encoding_is_gzip(value.view())
    None => false
  }
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
  let body_hint = body_size_hint(request, max_body_size)
  let raw_body = if gzip_encoded {
    decode_gzip_body(
      read_body_bytes(body, max_body_size, size_hint=body_hint),
      max_body_size,
    )
  } else {
    read_body_bytes(body, max_body_size, size_hint=body_hint)
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
    headers.remove(header_content_type)
    headers.remove(header_content_encoding)
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
      send_static_error(
        conn,
        response.headers,
        response.cookies,
        head,
        404,
        "404 Not Found",
        false,
      )
      return
    }
  }
  defer handle.close()
  if handle.kind() is @fs.Directory {
    send_static_error(
      conn,
      response.headers,
      response.cookies,
      head,
      404,
      "404 Not Found",
      false,
    )
    return
  }
  let size = handle.size() catch {
    _ => {
      send_static_error(
        conn,
        response.headers,
        response.cookies,
        head,
        500,
        "500 Internal Server Error",
        false,
      )
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
    get_header_ignore_case(response.headers, "Content-Encoding") is None &&
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
  if !serving_gzip && refuses_identity && status_allows_body(response.status) {
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
  let vary_encoding = compressible
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
    match
      evaluate_preconditions(
        request,
        effective_etag,
        effective_mtime,
        head || request.meth is @http.Get,
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
        )
        return
      }
      PreconditionNotModified => {
        headers.remove(header_content_length)
        headers.remove(header_content_type)
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
              headers.set(
                header_content_range,
                "bytes */" + representation_size.to_string(),
              )
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
/// UTF-8 byte length of a string, matching the size of `@utf8.encode`'s
/// output. Invalid surrogate pairs abort, exactly like `@utf8.encode`.
fn utf8_byte_length(view : StringView) -> Int32 {
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
        abort("invalid surrogate pair")
      }
    } else if unit.is_trailing_surrogate() {
      abort("invalid surrogate pair")
    } else {
      total = total + 3
    }
    i = i + 1
  }
  total
}

///|
/// UTF-8 byte length of the text `encode_utf8_lossy` would produce: a valid
/// surrogate pair counts as four bytes and every other lone surrogate as the
/// three bytes of U+FFFD. Unlike `utf8_byte_length` this never aborts, so it
/// can size an arbitrary caller-supplied string.
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

///|
/// Context state key marking that the middleware chain called through to an
/// asynchronous endpoint (WebSocket, SSE or streaming response).
const ASYNC_CHAIN_PASS_KEY : String = "__feather_async_pass"

///|
/// Apply the ordinary dynamic-response pipeline (preconditions, compression,
/// generated ETags) to a context produced by a handler or middleware chain.
///
/// Async endpoint middleware can short-circuit with an ordinary response; it
/// must go through the same negotiation and validator stages as a normal route
/// instead of being written verbatim.
async fn finalize_dynamic_response(
  app : App,
  request : @http.Request,
  ctx : Context,
) -> Unit {
  if ctx.file_response() is None {
    let (input, allows_not_modified) = precondition_input_http(request)
    let (failed, remaining) = precheck_preconditions(
      input,
      allows_not_modified,
      ctx.response,
    )
    if !failed {
      let (compress, min_size) = compression_settings(app, ctx)
      if compress {
        compress_response(accept_encoding_of(request), ctx.response, min_size)
      }
      if response_etag_enabled(app, ctx) {
        apply_etag(ctx.response)
      }
      apply_preconditions_input(remaining, allows_not_modified, ctx.response)
    }
  }
}

///|
/// Send the response a short-circuiting middleware produced for an
/// asynchronous endpoint, supporting both ordinary bodies and file responses.
async fn send_context_response(
  app : App,
  conn : @http.ServerConnection,
  ctx : Context,
  head : Bool,
  request : @http.Request,
) -> Unit {
  finalize_dynamic_response(app, request, ctx)
  let connect = request.meth is @http.Connect
  match ctx.file_response() {
    Some(file) => {
      let (compress, compress_min_size) = compression_settings(app, ctx)
      send_file_response(
        conn,
        ctx.response,
        file,
        head,
        request,
        connect~,
        auto_etag=response_file_etag_enabled(ctx),
        compress_enabled=compress,
        compress_min_size~,
      )
    }
    None => send_response(conn, ctx.response, head, connect~)
  }
}

///|
/// Terminal of every asynchronous middleware chain: records in the request
/// state that the chain called through to the endpoint.
fn async_chain_terminal(ctx : Context) -> Unit raise {
  ctx.state.set(ASYNC_CHAIN_PASS_KEY, "1")
}

///|
/// The application-level asynchronous middleware chain.
fn App::async_middleware_chain(self : App) -> Handler {
  match self.async_chain {
    Some(chain) => chain
    None => {
      let chain = if self.middlewares.length() == 0 {
        async_chain_terminal
      } else {
        apply_middleware(self.middlewares, async_chain_terminal)
      }
      self.async_chain = Some(chain)
      chain
    }
  }
}

///|
/// Run an already-composed middleware chain before an asynchronous endpoint
/// starts.
///
/// Middleware that short-circuits (for example an authenticator) answers the
/// request instead of letting the endpoint start. Middleware that calls through
/// lets the endpoint proceed; headers and cookies it added to the response are
/// carried into SSE and streaming responses.
fn run_async_middleware_chain(chain : Handler, ctx : Context) -> Bool {
  // A previous chain (the application-level one) may have left its pass marker
  // behind; clear it so only a call-through in this chain counts.
  ctx.state.remove(ASYNC_CHAIN_PASS_KEY)
  let mut failed = false
  chain(ctx) catch {
    HttpError(status, message) => {
      error_response(ctx, status, message)
      failed = true
    }
    HttpErrorPayload(status, message, payload) => {
      error_response_with_payload(ctx, status, message, payload)
      failed = true
    }
    HttpProblem(status, type_name, title, detail, instance) => {
      problem_response(ctx, status, type_name, title, detail, instance)
      failed = true
    }
    err => {
      internal_error(ctx, "\{err}")
      failed = true
    }
  }
  !failed && ctx.state.get(ASYNC_CHAIN_PASS_KEY) is Some(_)
}

///|
/// Run the application middleware chain, then any middleware attached to the
/// matched asynchronous route (such as the mounted application's middleware).
/// Both chains were composed when the application or route was built. Returns
/// `true` when both chains called through.
fn App::run_async_middleware(
  self : App,
  ctx : Context,
  route_chain : Handler,
) -> Bool {
  if !run_async_middleware_chain(self.async_middleware_chain(), ctx) {
    return false
  }
  run_async_middleware_chain(route_chain, ctx)
}

///|
/// Whether a response header must not be carried into a streaming response,
/// because the runtime computes it from the chunked body instead.
fn is_stream_reserved_header(name : String) -> Bool {
  name.view().equal_ignore_ascii_case("content-length".view()) ||
  name.view().equal_ignore_ascii_case("transfer-encoding".view()) ||
  name.view().equal_ignore_ascii_case("connection".view())
}

///|
/// Copy the headers a middleware chain accumulated into a map suitable for a
/// `Stream`, dropping the framing headers the runtime owns.
fn stream_seed_headers(response : Response) -> Map[String, String] {
  let headers : Map[String, String] = Map(
    [],
    capacity=response.headers.length(),
  )
  for name, value in response.headers {
    if !is_stream_reserved_header(name) &&
      !name.view().equal_ignore_ascii_case("content-encoding".view()) &&
      !name.view().equal_ignore_ascii_case("content-range".view()) {
      headers.set(name, value)
    }
  }
  headers
}

///|
/// Answer an `Expect: 100-continue` handshake with the interim `100 Continue`
/// response (RFC 9110 §10.1.1), so clients that wait for it before uploading
/// a body are not left blocked until they time out. The final response is sent
/// as usual once the body has been read.
async fn send_continue_if_expected(
  request : @http.Request,
  conn : @http.ServerConnection,
) -> Unit {
  match request.headers.get(header_expect) {
    Some(value) =>
      if trim_ascii_space(value.view()).equal_ignore_ascii_case(
          "100-continue".view(),
        ) {
        conn.send_response(100, "Continue") catch {
          _ => ()
        }
        conn.end_response() catch {
          _ => ()
        }
      }
    None => ()
  }
}

///|
/// Whether the request's `Connection` header asks for the connection to close
/// after this response. The runtime owns the connection loop, so the framework
/// closes the socket itself to make `Connection: close` effective.
fn request_wants_close(request : @http.Request) -> Bool {
  match request.headers.get(header_connection) {
    Some(value) =>
      header_list_has_token(value.view(), "close".view())
    None => false
  }
}

///|
fn append_trailing_slash(path : String) -> String {
  // Insert the slash into the path component, before the first `?` or `#`.
  // The fragment delimiter may come first, in which case a `?` inside it is
  // part of the fragment and must not decide where the slash goes.
  let (head, tail) = match path_head_end(path) {
    Some(index) => (path[:index], path[index:])
    None => (path, "")
  }
  // A location that starts with `//` is a scheme-relative URL, so a request
  // target with duplicate leading slashes must not be echoed verbatim: a
  // browser would interpret the redirect as a different host. Collapse the
  // leading slashes to the origin-relative single slash the static lookup
  // already used.
  let view = head.view()
  let length = view.length()
  let mut first = 0
  while first < length && view.unsafe_get(first) == ('/' : UInt16) {
    first = first + 1
  }
  let normalized : String = if first == 0 {
    if length == 0 {
      ""
    } else {
      // A location is always origin-relative here. Prefixing the slash also
      // keeps an absolute-form request target (`GET http://host/path`) from
      // turning into an absolute redirect to that host.
      "/" + head.to_owned()
    }
  } else if first == length {
    "/"
  } else {
    "/" + view[first:].to_owned()
  }
  if normalized.has_suffix("/") {
    normalized + tail.to_owned()
  } else {
    normalized + "/" + tail.to_owned()
  }
}

///|
/// Read buffers used by `write_file_range`. The async runtime is single
/// threaded, so a plain array is safe.
let file_range_buffers : Array[FixedArray[Byte]] = []

///|
/// Maximum number of range buffers retained.
const FILE_RANGE_POOL_LIMIT : Int32 = 4

///|
/// Size of the range buffers.
const FILE_RANGE_CHUNK_SIZE : Int32 = 65536

///|
fn acquire_file_range_buffer() -> FixedArray[Byte] {
  match file_range_buffers.pop() {
    Some(buffer) => buffer
    None => FixedArray::make(FILE_RANGE_CHUNK_SIZE, b'\x00')
  }
}

///|
fn release_file_range_buffer(buffer : FixedArray[Byte]) -> Unit {
  if file_range_buffers.length() < FILE_RANGE_POOL_LIMIT {
    file_range_buffers.push(buffer)
  }
}

///|
async fn write_file_range(
  conn : @http.ServerConnection,
  file : @fs.File,
  start : Int64,
  length : Int64,
) -> Unit {
  if length <= 0L {
    return
  }
  let chunk_size : Int32 = if length < FILE_RANGE_CHUNK_SIZE.to_int64() {
    length.to_int()
  } else {
    65536
  }
  let buffer = acquire_file_range_buffer()
  defer release_file_range_buffer(buffer)
  let mut remaining = length
  let mut position = start
  while remaining > 0 {
    let want : Int32 = if remaining < chunk_size.to_int64() {
      remaining.to_int()
    } else {
      chunk_size
    }
    let read = file.read_at(buffer, position~, len=want) catch { _ => 0 }
    if read <= 0 {
      break
    }
    conn.write(buffer.unsafe_reinterpret_as_bytes()[:read])
    remaining = remaining - read.to_int64()
    position = position + read.to_int64()
  }
}

///|
/// Read an entire regular file into memory. Returns `None` for a file too large
/// to address as a single MoonBit `Bytes` or when a read fails.
async fn read_file_bytes(file : @fs.File, size : Int64) -> Bytes? {
  if size < 0L || size > 2147483647L {
    return None
  }
  let length = size.to_int()
  if length == 0 {
    return Some(b"")
  }
  let buffer = FixedArray::make(length, b'\x00')
  let mut offset = 0
  while offset < length {
    let read = file.read_at(
      buffer,
      position=offset.to_int64(),
      len=length - offset,
    ) catch {
      _ => return None
    }
    if read <= 0 {
      return None
    }
    offset = offset + read
  }
  Some(buffer.unsafe_reinterpret_as_bytes())
}

///|
/// Write `length` bytes starting at `start` from an in-memory representation.
async fn write_bytes_range(
  conn : @http.ServerConnection,
  data : Bytes,
  start : Int64,
  length : Int64,
) -> Unit {
  if length <= 0L {
    return
  }
  let first = start.to_int()
  let count = length.to_int()
  conn.write(data[first:first + count])
}

///|
/// Open the `gzip` sibling of `file_path`, if it exists and is a regular file.
async fn open_precompressed_gzip(file_path : String) -> @fs.File? {
  let handle = Some(@fs.open(file_path + ".gz", mode=@fs.ReadOnly)) catch {
    _ => None
  }
  match handle {
    Some(handle) =>
      if handle.kind() is @fs.Directory {
        handle.close()
        None
      } else {
        Some(handle)
      }
    None => None
  }
}

///|
/// Append `value` to the `Vary` header without duplicating an existing entry.
fn add_vary_header(headers : @http.Headers, value : String) -> Unit {
  match headers.get(header_vary) {
    Some(existing) =>
      if trim_ascii_space(existing.view()).is_empty() {
        headers.set(header_vary, value)
      } else if !header_list_has_token(existing.view(), value.view()) {
        headers.set(header_vary, existing + ", " + value)
      }
    None => headers.set(header_vary, value)
  }
}

///|
/// Build the outgoing headers for a static response, seeding them with the
/// headers a request context accumulated. A `Set-Cookie` entry is dropped when
/// the response carries cookies, which are sent separately.
fn static_base_headers(
  extra_headers : Map[String, String],
  cookies : Array[@http.Cookie],
  capacity : Int32,
) -> @http.Headers {
  let headers : @http.Headers = Map(
    [],
    capacity=extra_headers.length() + capacity,
  )
  for name, value in extra_headers {
    // Framing headers are recomputed for whatever this response turns out to
    // be; a middleware's body length must not leak into 304/416/redirects.
    if is_stream_reserved_header(name) {
      continue
    }
    // The static file, range and encoding are chosen here, so representation
    // metadata prepared for a different body must not leak in either.
    if name.view().equal_ignore_ascii_case("content-encoding".view()) ||
      name.view().equal_ignore_ascii_case("content-range".view()) {
      continue
    }
    if cookies.length() > 0 &&
      name.view().equal_ignore_ascii_case("set-cookie".view()) {
      continue
    }
    headers.set(header_key(name), value)
  }
  headers
}

///|
/// Headers for a static directory redirect. A redirect has no representation,
/// so a content type prepared for a file body must not leak into it.
fn static_redirect_headers(
  extra_headers : Map[String, String],
  cookies : Array[@http.Cookie],
  location : String,
) -> @http.Headers {
  let headers = static_base_headers(extra_headers, cookies, 1)
  headers.remove(header_content_type)
  headers.set(header_location, location)
  headers
}

///|
async fn send_static_redirect(
  conn : @http.ServerConnection,
  extra_headers : Map[String, String],
  cookies : Array[@http.Cookie],
  location : String,
) -> Unit {
  send_with_date(
    conn,
    301,
    "Moved Permanently",
    static_redirect_headers(extra_headers, cookies, location),
    cookies~,
  )
  conn.end_response()
}

///|
/// Add a response header only when the response does not already carry one,
/// so middleware-supplied representation headers survive static file serving
/// just as handler-supplied values survive `send_file_response`.
fn set_header_if_absent(
  headers : @http.Headers,
  name : @http.CaseInsensitiveString,
  value : String,
) -> Unit {
  if !headers.contains(name) {
    headers.set(name, value)
  }
}

///|
/// Send a plain-text error response for a static request, carrying the request
/// context's headers and cookies.
async fn send_static_error(
  conn : @http.ServerConnection,
  extra_headers : Map[String, String],
  cookies : Array[@http.Cookie],
  head : Bool,
  code : Int32,
  body : String,
  precompressed : Bool,
  vary_encoding~ : Bool = false,
) -> Unit {
  let bytes = encode_utf8_lossy(body.view())
  let headers = static_base_headers(extra_headers, cookies, 2)
  // The error body is plain text, not the representation a middleware may have
  // prepared for a file response.
  headers.remove(header_content_encoding)
  headers.remove(header_content_range)
  if precompressed || vary_encoding {
    // Whether this path resolves to a file depends on `Accept-Encoding`, so
    // caches must not reuse an identity error for a gzip-capable client.
    add_vary_header(headers, "Accept-Encoding")
  }
  headers.set(header_content_type, "text/plain; charset=utf-8")
  headers.set(header_content_length, bytes.length().to_string())
  send_with_date(conn, code, status_text(code), headers, cookies~)
  if !head {
    conn.write(bytes)
  }
  conn.end_response()
}

///|
/// Add the negotiation headers a static file response needs. `vary_encoding`
/// is set whenever the selected representation depends on `Accept-Encoding`,
/// including an on-the-fly gzip encoding from `App::compress`.
fn decorate_static_headers(
  headers : @http.Headers,
  vary_encoding : Bool,
  serving_gzip : Bool,
) -> Unit {
  if vary_encoding {
    add_vary_header(headers, "Accept-Encoding")
  }
  if serving_gzip {
    headers.set(header_content_encoding, "gzip")
  }
}

///|
/// Report whether `path` currently names a directory. A failed open is not a
/// directory, so the static handler can still produce the usual 404.
async fn static_target_is_directory(path : String) -> Bool {
  let file = @fs.open(path, mode=@fs.ReadOnly) catch { _ => return false }
  defer file.close()
  file.kind() is @fs.Directory
}

///|
/// Report whether `path` currently names a regular file. A failed open or a
/// directory is not a file, which lets directory redirects wait until the
/// configured index actually exists.
async fn static_target_is_regular_file(path : String) -> Bool {
  let file = @fs.open(path, mode=@fs.ReadOnly) catch { _ => return false }
  defer file.close()
  file.kind() is @fs.Regular
}

///|
/// Serve a static file, seeding every response with the headers and cookies a
/// request context accumulated (middleware and handler output), so static
/// responses carry the same security, CORS and session headers as dynamic
/// ones.
async fn serve_static_file(
  conn : @http.ServerConnection,
  file_path : String,
  head : Bool,
  request : @http.Request,
  cache_control : String,
  precompressed : Bool,
  redirect_directories : Bool,
  extra_headers : Map[String, String],
  cookies : Array[@http.Cookie],
  response_started~ : Ref[Bool],
  index~ : String = "",
  redirect_root~ : Bool = false,
  auto_etag~ : Bool = true,
  compress_enabled~ : Bool = false,
  compress_min_size~ : Int32 = 1024,
) -> Unit {
  // From here on every path writes a response header. Record that before the
  // first await so a timeout racing with file lookup or streaming closes the
  // connection instead of attempting a second (invalid) response.
  response_started.val = true
  let accept_encoding = request.headers.get(header_accept_encoding)
  let refuses_identity = match accept_encoding {
    Some(value) => accept_encoding_refuses_identity(value)
    None => false
  }
  let mut gzip_handle : @fs.File? = None
  let base : @fs.File? = Some(@fs.open(file_path, mode=@fs.ReadOnly)) catch {
    _ => {
      // A mount may ship only the precompressed sibling of an asset, so probe
      // it before reporting the source file as missing.
      if precompressed {
        match accept_encoding {
          Some(value) =>
            // Here identity is unavailable, so any positive gzip quality is
            // enough; unlike the two-representation choice below, it does not
            // have to outrank identity.
            if accept_encoding_accepts_gzip(value) {
              gzip_handle = open_precompressed_gzip(file_path)
            }
          None => ()
        }
      }
      if gzip_handle is None {
        if refuses_identity {
          // A gzip-only asset still exists even when the client accepts no
          // coding for it, so distinguish that from a genuinely missing file.
          let sibling_exists = if precompressed {
            match open_precompressed_gzip(file_path) {
              Some(handle) => {
                handle.close()
                true
              }
              None => false
            }
          } else {
            false
          }
          if sibling_exists {
            send_static_error(
              conn,
              extra_headers,
              cookies,
              head,
              406,
              "406 Not Acceptable",
              precompressed,
              vary_encoding=true,
            )
          } else {
            send_static_error(
              conn, extra_headers, cookies, head, 404, "404 Not Found", precompressed,
            )
          }
        } else {
          send_static_error(
            conn, extra_headers, cookies, head, 404, "404 Not Found", precompressed,
          )
        }
        return
      }
      None
    }
  }
  match base {
    Some(handle) =>
      if handle.kind() is @fs.Directory {
        handle.close()
        // Only redirect to the canonical directory URL once the configured
        // index exists, so a missing index reports 404 directly instead of
        // redirecting to another 404.
        if !redirect_directories ||
          index == "" ||
          !static_target_is_regular_file(join_fs_path(file_path, index)) {
          send_static_error(
            conn, extra_headers, cookies, head, 404, "404 Not Found", precompressed,
          )
          return
        }
        let location = append_trailing_slash(request.path)
        // The redirect target may already be the requested path when the
        // resolved index is itself a directory (for example a directory named
        // `index.html`). Redirecting there would loop forever, so report the
        // missing file instead.
        if location == request.path {
          send_static_error(
            conn,
            extra_headers,
            cookies,
            head,
            404,
            "404 Not Found",
            precompressed,
          )
          return
        }
        send_static_redirect(conn, extra_headers, cookies, location)
        return
      }
    None => ()
  }
  if redirect_root {
    // The mount root (`/assets`) is a directory request too: redirect it to
    // the canonical `/assets/` spelling before serving its index. Doing this
    // after opening the file keeps a missing index a 404 rather than a
    // redirect to another 404.
    let location = append_trailing_slash(request.path)
    if location != request.path {
      send_static_redirect(conn, extra_headers, cookies, location)
      return
    }
  }
  if precompressed && gzip_handle is None {
    match base {
      Some(_) =>
        match accept_encoding {
          Some(value) =>
            if accept_encoding_allows_gzip_cached(value) {
              // The probe always runs: a `.gz` sibling may appear (or vanish)
              // while the server is running, so a remembered miss would keep
              // serving the identity representation even after a deploy added
              // the precompressed file.
              gzip_handle = open_precompressed_gzip(file_path)
            }
          None => ()
        }
      None => ()
    }
  }
  let serving_gzip = gzip_handle is Some(_)
  let file = match gzip_handle {
    Some(handle) => {
      match base {
        Some(base_file) => base_file.close()
        None => ()
      }
      handle
    }
    None =>
      match base {
        Some(base_file) => base_file
        None => {
          send_static_error(
            conn, extra_headers, cookies, head, 404, "404 Not Found", precompressed,
          )
          return
        }
      }
  }
  defer file.close()
  let size = file.size() catch {
    _ => {
      send_static_error(
        conn, extra_headers, cookies, head, 500, "500 Internal Server Error", precompressed,
      )
      return
    }
  }
  let mtime = file.mtime() catch { _ => (0L, 0) }
  let (mtime_secs, mtime_nanos) = mtime
  let (etag, last_modified, content_type_value) = file_validators(
    file_path,
    size,
    mtime_secs,
    mtime_nanos,
    cache_key=file_path,
    gzip=serving_gzip,
  )
  // A precompressed sibling is already the negotiated representation. Without
  // one, `App::compress` can still gzip an eligible static file on the fly;
  // this keeps static responses subject to the same application-wide
  // compression setting as dynamic ones.
  let mut compressed_body : Bytes? = None
  let mut dynamic_gzip = false
  let effective_cache_control = match
    get_header_ignore_case(extra_headers, "Cache-Control") {
    Some(value) => value
    None => cache_control
  }
  let no_transform = cache_control_has_directive(
    effective_cache_control.view(),
    "no-transform".view(),
  )
  // Middleware may override the file's media type, and compression depends on
  // the representation's actual type, not the extension-derived default.
  let effective_content_type = match
    get_header_ignore_case(extra_headers, "Content-Type") {
    Some(value) => value
    None => content_type_value
  }
  let dynamic_eligible = !serving_gzip &&
    compress_enabled &&
    !no_transform &&
    content_type_is_compressible(effective_content_type.view())
  if dynamic_eligible {
    match accept_encoding {
      Some(value) =>
        if accept_encoding_allows_gzip_cached(value) &&
          (
            refuses_identity ||
            size >= (if compress_min_size > 0 {
              compress_min_size.to_int64()
            } else {
              0L
            })
          ) {
          match read_file_bytes(file, size) {
            Some(raw) => {
              let compressed : Bytes? = Some(gzip_compress(raw)) catch {
                _ => None
              }
              match compressed {
                Some(bytes) =>
                  // Like dynamic compression, keep the identity
                  // representation when gzip would not shrink it, unless the
                  // client explicitly refused identity.
                  if refuses_identity || bytes.length() < raw.length() {
                    compressed_body = Some(bytes)
                    dynamic_gzip = true
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
  let serving_selected_gzip = serving_gzip || dynamic_gzip
  if !serving_selected_gzip && refuses_identity {
    // There is no acceptable representation: no precompressed sibling, no
    // on-the-fly encoding, and the client explicitly rejected identity.
    send_static_error(
      conn,
      extra_headers,
      cookies,
      head,
      406,
      "406 Not Acceptable",
      precompressed,
      vary_encoding=true,
    )
    return
  }
  // `Vary` describes the representation-selection process, not just this
  // response: once application compression is enabled for a compressible
  // static file, a gzip-capable client must not share a cache entry with an
  // identity client even when this particular reply ended up uncompressed.
  let vary_encoding = precompressed || dynamic_eligible
  // A dynamic gzip representation is semantically equivalent to the source
  // file but has different bytes, so its generated validator must be weak.
  let generated_etag = if auto_etag {
    if dynamic_gzip { "W/" + etag } else { etag }
  } else {
    ""
  }
  // A gzipped body is only weakly equivalent to the source file when the
  // framework produced it by transforming that file. Weaken a middleware-
  // supplied strong validator in that case, matching the dynamic compression
  // stage, so it cannot be reused for the identity bytes. A precompressed
  // sibling also selects a different representation, so the same rule applies.
  if serving_selected_gzip {
    match get_header_ignore_case(extra_headers, "ETag") {
      Some(value) =>
        if !value.has_prefix("W/") {
          set_header_ignore_case(extra_headers, "ETag", "W/" + value)
        }
      None => ()
    }
  }
  let etag_key = header_etag
  let last_modified_key = header_last_modified
  let cache_control_key = header_cache_control
  // A middleware may override the validators the static file would otherwise
  // advertise. Preconditions must be evaluated against the values the response
  // actually carries, matching `send_file_response`.
  let effective_etag = match get_header_ignore_case(extra_headers, "ETag") {
    Some(value) => value
    None => generated_etag
  }
  let effective_mtime = match
    get_header_ignore_case(extra_headers, "Last-Modified") {
    Some(value) =>
      match parse_http_date_view(trim_ascii_space(value.view())) {
        Some(seconds) => seconds
        None => mtime_secs
      }
    None => mtime_secs
  }
  match evaluate_preconditions(request, effective_etag, effective_mtime, true) {
    PreconditionFailed => {
      send_static_error(
        conn,
        extra_headers,
        cookies,
        head,
        412,
        "412 Precondition Failed",
        precompressed,
        vary_encoding=vary_encoding,
      )
      return
    }
    PreconditionNotModified => {
      let headers = static_base_headers(extra_headers, cookies, 2)
      // A 304 carries no body, so the framing and content type a middleware
      // seeded for a body response must not leak into it.
      headers.remove(header_content_type)
      headers.remove(header_content_length)
      if generated_etag != "" {
        set_header_if_absent(headers, etag_key, generated_etag)
      }
      set_header_if_absent(headers, last_modified_key, last_modified)
      if cache_control != "" {
        set_header_if_absent(headers, cache_control_key, cache_control)
      }
      decorate_static_headers(
        headers, vary_encoding, serving_selected_gzip,
      )
      send_with_date(conn, 304, "Not Modified", headers, cookies~)
      conn.end_response()
      return
    }
    PreconditionPass => ()
  }
  let representation_size = match compressed_body {
    Some(bytes) => bytes.length().to_int64()
    None => size
  }
  let range = if head {
    ByteRangeFull
  } else {
    match request.headers.get(header_range) {
      Some(value) =>
        if if_range_allows(request, effective_etag, effective_mtime) {
          parse_byte_range(value, representation_size)
        } else {
          ByteRangeFull
        }
      None => ByteRangeFull
    }
  }
  let content_type_key = header_content_type
  let content_length_key = header_content_length
  let content_range_key = header_content_range
  let accept_ranges_key = header_accept_ranges
  match range {
    ByteRangeInvalid => {
      let headers = static_base_headers(extra_headers, cookies, 2)
      headers.remove(content_type_key)
      headers.set(
        content_range_key,
        "bytes */" + representation_size.to_string(),
      )
      headers.set(accept_ranges_key, "bytes")
      decorate_static_headers(headers, vary_encoding, false)
      send_with_date(conn, 416, "Range Not Satisfiable", headers, cookies~)
      conn.end_response()
    }
    ByteRangeSpec(start, end) => {
      let length = end - start + 1L
      let headers = static_base_headers(extra_headers, cookies, 6)
      set_header_if_absent(headers, content_type_key, content_type_value)
      headers.set(content_length_key, length.to_string())
      headers.set(
        content_range_key,
        "bytes " +
        start.to_string() +
        "-" +
        end.to_string() +
        "/" +
        representation_size.to_string(),
      )
      if generated_etag != "" {
        set_header_if_absent(headers, etag_key, generated_etag)
      }
      set_header_if_absent(headers, last_modified_key, last_modified)
      headers.set(accept_ranges_key, "bytes")
      if cache_control != "" {
        set_header_if_absent(headers, cache_control_key, cache_control)
      }
      decorate_static_headers(
        headers, vary_encoding, serving_selected_gzip,
      )
      send_with_date(conn, 206, "Partial Content", headers, cookies~)
      if !head {
        match compressed_body {
          Some(bytes) => write_bytes_range(conn, bytes, start, length)
          None => write_file_range(conn, file, start, length)
        }
      }
      conn.end_response()
    }
    ByteRangeFull => {
      let headers = static_base_headers(extra_headers, cookies, 5)
      set_header_if_absent(headers, content_type_key, content_type_value)
      headers.set(content_length_key, representation_size.to_string())
      if generated_etag != "" {
        set_header_if_absent(headers, etag_key, generated_etag)
      }
      set_header_if_absent(headers, last_modified_key, last_modified)
      headers.set(accept_ranges_key, "bytes")
      if cache_control != "" {
        set_header_if_absent(headers, cache_control_key, cache_control)
      }
      decorate_static_headers(
        headers, vary_encoding, serving_selected_gzip,
      )
      send_with_date(conn, 200, "OK", headers, cookies~)
      if !head {
        match compressed_body {
          Some(bytes) => write_bytes_range(conn, bytes, 0L, representation_size)
          None => write_file_range(conn, file, 0L, size)
        }
      }
      conn.end_response()
    }
  }
}

///|
/// Context state key the static middleware chain sets when the request falls
/// through to the file.
const STATIC_CHAIN_PASS_KEY : String = "__feather_static_pass"

///|
/// Extra budget for static requests before a very small request timeout fires,
/// so opening and statting the file cannot abort before the status line is
/// written. The body transfer itself remains subject to the configured
/// timeout.
const STATIC_TIMEOUT_HEADROOM : Int32 = 50

///|
/// How long a graceful shutdown keeps serving (answering `503`) after all
/// in-flight requests have finished, so idle kept-alive connections have a
/// chance to observe the drain before the server task is cancelled.
const GRACEFUL_DRAIN_SETTLE_MS : Int32 = 250

///|
/// Serve a static mount after running the application middleware chain.
///
/// The chain wraps the static lookup: middleware that short-circuits (for
/// example an authenticator) decides the response, while middleware that calls
/// through gets its response headers and cookies merged into the file response.
async fn handle_static(
  app : App,
  request : @http.Request,
  body : &@io.Reader,
  conn : @http.ServerConnection,
  file_path : String,
  cache_control : String,
  precompressed : Bool,
  mount : StaticMount,
  head : Bool,
  response_started~ : Ref[Bool],
) -> Unit {
  if app.middlewares.length() == 0 && mount.middlewares.length() == 0 {
    // The middleware-free fast path skips `request_from_http`, but the body
    // still has to be consumed under the application-wide limit: a static
    // request must not smuggle an unbounded body past `App::max_body_size`
    // just because no handler ever asks for it.
    ignore(
      read_body_bytes(body, app.max_body_size) catch {
        PayloadTooLarge => {
          send_error_and_close(conn, 413, "413 Payload Too Large", head)
          return
        }
        _ => {
          send_error_and_close(conn, 500, "500 Internal Server Error", head)
          return
        }
      },
    )
    serve_static_file(
      conn,
      file_path,
      head,
      request,
      cache_control,
      precompressed,
      !mount.index.is_empty(),
      Map([]),
      [],
      response_started~,
      redirect_root=static_root_needs_slash(request.path, mount),
      index=mount.index,
      compress_enabled=app.compress_enabled,
      compress_min_size=app.compress_min_size,
    )
    return
  }
  let (req, raw_body) = request_from_http(request, body, app.max_body_size) catch {
    PayloadTooLarge => {
      send_error_and_close(conn, 413, "413 Payload Too Large", head)
      return
    }
    MalformedRequestBody => {
      send_simple(conn, 400, "400 Bad Request", head)
      return
    }
    _ => {
      send_error_and_close(conn, 500, "500 Internal Server Error", head)
      return
    }
  }
  let ctx = app.context_for_request(req)
  defer ctx.run_cleanups()
  attach_raw_body(ctx, raw_body)
  ctx.state.set("remote_addr", socket_addr_host(conn.client_addr()))
  let chain = if mount.middlewares.length() == 0 {
    match app.static_chain {
      Some(chain) => chain
      None => {
        let terminal : Handler = fn(ctx) {
          ctx.state.set(STATIC_CHAIN_PASS_KEY, "1")
        }
        let chain = apply_middleware(app.middlewares, terminal)
        app.static_chain = Some(chain)
        chain
      }
    }
  } else {
    match mount.chain {
      Some(chain) => chain
      None => {
        let terminal : Handler = fn(ctx) {
          ctx.state.set(STATIC_CHAIN_PASS_KEY, "1")
        }
        let chain = apply_middleware(
          app.middlewares,
          apply_middleware(mount.middlewares, terminal),
        )
        mount.chain = Some(chain)
        chain
      }
    }
  }
  let mut failed = false
  chain(ctx) catch {
    HttpError(status, message) => {
      error_response(ctx, status, message)
      failed = true
    }
    HttpErrorPayload(status, message, payload) => {
      error_response_with_payload(ctx, status, message, payload)
      failed = true
    }
    HttpProblem(status, type_name, title, detail, instance) => {
      problem_response(ctx, status, type_name, title, detail, instance)
      failed = true
    }
    err => {
      internal_error(ctx, "\{err}")
      failed = true
    }
  }
  if !failed && ctx.state.get(STATIC_CHAIN_PASS_KEY) is Some(_) {
    let (compress, min_size) = compression_settings(app, ctx)
    serve_static_file(
      conn,
      file_path,
      head,
      request,
      cache_control,
      precompressed,
      !mount.index.is_empty(),
      ctx.response.headers,
      ctx.response.cookies,
      response_started~,
      redirect_root=static_root_needs_slash(request.path, mount),
      index=mount.index,
      auto_etag=response_file_etag_enabled(ctx),
      compress_enabled=compress,
      compress_min_size=min_size,
    )
  } else {
    // The middleware chain produced a complete response (or an error), and the
    // branch below writes it under the request timeout. Mark the response as
    // started before the first write so a late timeout closes the connection
    // instead of trying to send a second response on it.
    response_started.val = true
    match ctx.file_response() {
      Some(file) => {
        let (compress, min_size) = compression_settings(app, ctx)
        send_file_response(
          conn,
          ctx.response,
          file,
          head,
          request,
          auto_etag=response_file_etag_enabled(ctx),
          compress_enabled=compress,
          compress_min_size=min_size,
        )
      }
      None => {
        let (input, allows_not_modified) = precondition_input_http(request)
        let (failed, remaining) = precheck_preconditions(
          input,
          allows_not_modified,
          ctx.response,
        )
        if !failed {
          let (compress, min_size) = compression_settings(app, ctx)
          if compress {
            compress_response(
              accept_encoding_of(request),
              ctx.response,
              min_size,
            )
          }
          if response_etag_enabled(app, ctx) {
            apply_etag(ctx.response)
          }
          apply_preconditions_input(
            remaining,
            allows_not_modified,
            ctx.response,
          )
        }
        send_response(conn, ctx.response, head)
      }
    }
  }
}

///|
async fn build_response(
  app : App,
  request : @http.Request,
  body : &@io.Reader,
  conn : @http.ServerConnection,
) -> (Response, FileResponse?, Bool, Bool, Int32) {
  let (req, raw_body) = request_from_http(request, body, app.max_body_size)
  let ctx = app.context_for_request(req)
  attach_raw_body(ctx, raw_body)
  ctx.state.set("remote_addr", socket_addr_host(conn.client_addr()))
  app.handle(ctx) catch {
    HttpError(status, message) => error_response(ctx, status, message)
    HttpErrorPayload(status, message, payload) =>
      error_response_with_payload(ctx, status, message, payload)
    HttpProblem(status, type_name, title, detail, instance) =>
      problem_response(ctx, status, type_name, title, detail, instance)
    err => internal_error(ctx, "\{err}")
  }
  let file = ctx.file_response()
  let auto_etag = response_file_etag_enabled(ctx)
  let (compress, compress_min_size) = compression_settings(app, ctx)
  finalize_dynamic_response(app, request, ctx)
  (ctx.response, file, auto_etag, compress, compress_min_size)
}

///|
async fn handle_websocket(
  app : App,
  request : @http.Request,
  body : &@io.Reader,
  conn : @http.ServerConnection,
  handler : WebSocketHandler,
  params : Map[String, String],
  route_chain : Handler,
  route_path : String,
  head : Bool,
) -> Unit {
  let (req, raw_body) = request_from_http(request, body, app.max_body_size) catch {
    PayloadTooLarge => {
      send_error_and_close(conn, 413, "413 Payload Too Large", head)
      return
    }
    MalformedRequestBody => {
      send_simple(conn, 400, "400 Bad Request", head)
      return
    }
    _ => {
      send_error_and_close(conn, 500, "500 Internal Server Error", head)
      return
    }
  }
  let ctx = app.context_for_request(req)
  defer ctx.run_cleanups()
  attach_raw_body(ctx, raw_body)
  ctx.state.set("remote_addr", socket_addr_host(conn.client_addr()))
  ctx.state.set(ROUTE_PATTERN_STATE_KEY, route_path)
  ctx.state.set(ROUTE_METHOD_STATE_KEY, "GET")
  for name, value in params {
    ctx.state.set(PARAM_PREFIX + name, value)
  }
  if !app.run_async_middleware(ctx, route_chain) {
    send_context_response(app, conn, ctx, head, request)
    return
  }
  if head {
    // A WebSocket endpoint only has a successful GET response in the form of
    // the `101` upgrade handshake, which cannot be represented by HEAD. Report
    // the method as not allowed instead of pretending the route does not exist.
    method_not_allowed_with_allow(ctx, "GET")
    send_context_response(app, conn, ctx, true, request)
    return
  }
  let socket = @websocket.from_http_server(request, conn) catch { _ => return }
  defer conn.close()
  defer socket.close()
  handler(ctx, socket) catch {
    _ => ()
  }
}

///|
/// Headers the server sends when an SSE handler starts. Building them before
/// invoking the handler also lets a HEAD request describe the same response
/// without starting the event stream.
fn sse_response_headers(ctx : Context) -> @http.Headers {
  let headers : @http.Headers = Map(
    [],
    capacity=ctx.response.headers.length() + 3,
  )
  for name, value in ctx.response.headers {
    if !is_stream_reserved_header(name) &&
      !name.view().equal_ignore_ascii_case("content-type".view()) &&
      !name.view().equal_ignore_ascii_case("content-encoding".view()) &&
      !name.view().equal_ignore_ascii_case("content-range".view()) {
      headers.set(header_key(name), value)
    }
  }
  headers.set(header_content_type, "text/event-stream; charset=utf-8")
  if !headers.contains(header_cache_control) {
    headers.set(header_cache_control, "no-cache")
  }
  if !headers.contains(header_x_accel_buffering) {
    headers.set(header_x_accel_buffering, "no")
  }
  if ctx.response.cookies.length() > 0 {
    headers.remove(header_set_cookie)
  }
  headers
}

///|
/// Stream server-sent events for a handler registered with `App::sse`.
///
/// The response header is sent before the handler runs so events are delivered
/// while the handler is still producing them. A handler failure (most often a
/// client disconnect surfacing as a write error) just tears the stream down.
async fn handle_sse(
  app : App,
  request : @http.Request,
  body : &@io.Reader,
  conn : @http.ServerConnection,
  handler : SseHandler,
  params : Map[String, String],
  route_chain : Handler,
  route_path : String,
  head : Bool,
) -> Unit {
  let (req, raw_body) = request_from_http(request, body, app.max_body_size) catch {
    PayloadTooLarge => {
      send_error_and_close(conn, 413, "413 Payload Too Large", head)
      return
    }
    MalformedRequestBody => {
      send_simple(conn, 400, "400 Bad Request", head)
      return
    }
    _ => {
      send_error_and_close(conn, 500, "500 Internal Server Error", head)
      return
    }
  }
  let ctx = app.context_for_request(req)
  defer ctx.run_cleanups()
  attach_raw_body(ctx, raw_body)
  ctx.state.set("remote_addr", socket_addr_host(conn.client_addr()))
  ctx.state.set(ROUTE_PATTERN_STATE_KEY, route_path)
  ctx.state.set(ROUTE_METHOD_STATE_KEY, "GET")
  for name, value in params {
    ctx.state.set(PARAM_PREFIX + name, value)
  }
  if !app.run_async_middleware(ctx, route_chain) {
    send_context_response(app, conn, ctx, head, request)
    return
  }
  let headers = sse_response_headers(ctx)
  send_with_date(conn, 200, "OK", headers, cookies=ctx.response.cookies)
  if head {
    conn.end_response()
    return
  }
  conn.flush() catch {
    _ => {
      conn.close()
      return
    }
  }
  let sse = Sse::new(conn)
  handler(ctx, sse) catch {
    _ => ()
  }
  sse.close() catch {
    _ => conn.close()
  }
}

///|
/// Stream a chunked response for a handler registered with `App::stream`.
///
/// The response header is sent by the first `Stream` write (or by `close`),
/// and the handler controls the status and headers through the handle. A
/// handler failure (most often a client disconnect surfacing as a write error)
/// just tears the stream down.
async fn handle_stream(
  app : App,
  request : @http.Request,
  body : &@io.Reader,
  conn : @http.ServerConnection,
  handler : StreamHandler,
  params : Map[String, String],
  route_chain : Handler,
  route_path : String,
  head : Bool,
) -> Unit {
  let (req, raw_body) = request_from_http(request, body, app.max_body_size) catch {
    PayloadTooLarge => {
      send_error_and_close(conn, 413, "413 Payload Too Large", head)
      return
    }
    MalformedRequestBody => {
      send_simple(conn, 400, "400 Bad Request", head)
      return
    }
    _ => {
      send_error_and_close(conn, 500, "500 Internal Server Error", head)
      return
    }
  }
  let ctx = app.context_for_request(req)
  defer ctx.run_cleanups()
  attach_raw_body(ctx, raw_body)
  ctx.state.set("remote_addr", socket_addr_host(conn.client_addr()))
  ctx.state.set(ROUTE_PATTERN_STATE_KEY, route_path)
  ctx.state.set(ROUTE_METHOD_STATE_KEY, "GET")
  for name, value in params {
    ctx.state.set(PARAM_PREFIX + name, value)
  }
  if !app.run_async_middleware(ctx, route_chain) {
    send_context_response(app, conn, ctx, head, request)
    return
  }
  if head {
    // A HEAD request gets the response header an empty stream would send, but
    // the handler is not started because it may stream indefinitely.
    let stream = Stream::new(
      conn,
      status=ctx.response.status,
      headers=stream_seed_headers(ctx.response),
      cookies=ctx.response.cookies,
    )
    stream.close() catch {
      _ => conn.close()
    }
    return
  }
  let stream = Stream::new(
    conn,
    status=ctx.response.status,
    headers=stream_seed_headers(ctx.response),
    cookies=ctx.response.cookies,
  )
  let mut failed = false
  handler(ctx, stream) catch {
    _ => failed = true
  }
  if failed && !stream.is_started() {
    stream.abort()
    send_simple(conn, 500, "500 Internal Server Error", false) catch {
      _ => conn.close()
    }
  } else if failed {
    // The response header is already on the wire and the handler failed
    // halfway through, so the chunked body cannot be terminated cleanly.
    // Closing without the final chunk lets the client detect the truncation
    // instead of accepting a partial body as a successful response.
    stream.abort()
    conn.close()
  } else {
    stream.close() catch {
      _ => conn.close()
    }
  }
}

///|
async fn handle_request(
  app : App,
  request : @http.Request,
  body : &@io.Reader,
  conn : @http.ServerConnection,
) -> Unit {
  let request = normalize_http_request(request)
  if app.draining {
    send_simple(
      conn,
      503,
      "503 Service Unavailable",
      request.meth is @http.Head,
    )
    conn.close()
    return
  }
  app.in_flight.val = app.in_flight.val + 1
  defer {
    app.in_flight.val = app.in_flight.val - 1
  }
  let close_after_response = request_wants_close(request)
  defer {
    if close_after_response {
      conn.close()
    }
  }
  let head = request.meth is @http.Head
  // Reject a declared oversized body before the `100-continue` handshake or
  // the first read, so a client that never uploads cannot pin the connection.
  if declared_body_exceeds_limit(request, app.max_body_size) {
    send_oversized_and_close(conn, head)
    return
  }
  send_continue_if_expected(request, conn)
  if request.meth is @http.Get || head {
    match app.resolve_websocket_full(request.path) {
      Some((handler, params, middlewares, route_path)) => {
        handle_websocket(
          app, request, body, conn, handler, params, middlewares, route_path, head,
        )
        return
      }
      None =>
        match app.resolve_sse_full(request.path) {
          Some((handler, params, middlewares, route_path)) => {
            handle_sse(
              app, request, body, conn, handler, params, middlewares, route_path,
              head,
            )
            return
          }
          None =>
            match app.resolve_stream_full(request.path) {
              Some((handler, params, middlewares, route_path)) => {
                handle_stream(
                  app, request, body, conn, handler, params, middlewares, route_path,
                  head,
                )
                return
              }
              None => ()
            }
        }
    }
  }
  // Dynamic routes take precedence over static mounts, so check them first.
  // A failed async resolve above already proves there is no websocket, SSE or
  // stream route for the path, so only the ordinary route table still needs
  // checking.
  let static_eligible = if request.meth is @http.Get {
    !app.static_mounts.is_empty() && !app.has_route("GET", request.path)
  } else if head {
    !app.static_mounts.is_empty() &&
    !app.has_route("HEAD", request.path) &&
    !app.has_websocket(request.path) &&
    !app.has_sse(request.path) &&
    !app.has_stream(request.path)
  } else {
    false
  }
  if static_eligible {
    match app.static_lookup(request.path) {
      Some((file_path, cache_control, precompressed, mount)) => {
        // With no index configured, a slashless directory request must fall
        // through to the router instead of being statically served (or
        // redirected), matching the behaviour of trailing-slash requests.
        if !(mount.index.is_empty() && static_target_is_directory(file_path)) {
          // Static requests read the body and serve files just like dynamic
          // ones, so they must obey the same per-request timeout. Once a
          // response header has been written, a late timeout can only close
          // the connection: sending a second 504 would abort the runtime's
          // response state machine.
          let response_started = Ref(false)
          if app.timeout > 0 {
            // Opening and statting a file can occasionally take longer than a
            // very small timeout, which would otherwise abort before the status
            // line is written. Give static responses a little headroom so they
            // can commit the header; the body transfer is still bounded.
            let static_timeout = if app.timeout >
              2147483647 - STATIC_TIMEOUT_HEADROOM {
              app.timeout
            } else {
              app.timeout + STATIC_TIMEOUT_HEADROOM
            }
            @async.with_timeout(static_timeout, () => {
              handle_static(
                app, request, body, conn, file_path, cache_control, precompressed, mount,
                head,
                response_started~,
              )
            }) catch {
              @async.TimeoutError =>
                if response_started.val {
                  conn.close()
                } else {
                  send_error_and_close(conn, 504, "504 Gateway Timeout", head)
                }
              _ =>
                send_error_and_close(
                  conn, 500, "500 Internal Server Error", head,
                )
            }
          } else {
            handle_static(
              app, request, body, conn, file_path, cache_control, precompressed, mount,
              head,
              response_started~,
            )
          }
          return
        }
      }
      None => ()
    }
  }
  let (response, file, auto_etag, compress, compress_min_size) = if app.timeout >
    0 {
    @async.with_timeout(app.timeout, () => {
      build_response(app, request, body, conn)
    }) catch {
      @async.TimeoutError => {
        send_error_and_close(conn, 504, "504 Gateway Timeout", head)
        return
      }
      PayloadTooLarge => {
        send_error_and_close(conn, 413, "413 Payload Too Large", head)
        return
      }
      MalformedRequestBody => {
        send_simple(conn, 400, "400 Bad Request", head)
        return
      }
      err => {
        ignore(err)
        send_error_and_close(conn, 500, "500 Internal Server Error", head)
        return
      }
    }
  } else {
    build_response(app, request, body, conn) catch {
      PayloadTooLarge => {
        send_error_and_close(conn, 413, "413 Payload Too Large", head)
        return
      }
      MalformedRequestBody => {
        send_simple(conn, 400, "400 Bad Request", head)
        return
      }
      err => {
        ignore(err)
        send_error_and_close(conn, 500, "500 Internal Server Error", head)
        return
      }
    }
  }
  match file {
    Some(file) =>
      send_file_response(
        conn,
        response,
        file,
        head,
        request,
        connect=request.meth is @http.Connect,
        auto_etag~,
        compress_enabled=compress,
        compress_min_size~,
      )
    None =>
      send_response(
        conn,
        response,
        head,
        connect=request.meth is @http.Connect,
      )
  }
}

///|
pub async fn App::serve_with(
  self : App,
  server : @http.Server,
  max_connections? : Int32,
) -> Unit {
  server.run_forever(
    (request : @http.Request, body : &@io.Reader, conn : @http.ServerConnection) => {
      handle_request(self, request, body, conn)
    },
    max_connections?,
  )
}

///|
pub async fn App::serve(self : App, addr : @socket.Addr) -> Unit {
  self.serve_with(@http.Server(addr))
}

///|
/// Serve `server` until the `stop` task resolves.
///
/// `stop` runs concurrently with the accept loop. When it completes the
/// listener is closed and the serving task is cancelled, so an application can
/// be shut down from any task, for example after a signal handler or a test
/// timer fires. An error raised by `stop` (or by the server itself)
/// propagates once the server is torn down.
pub async fn App::serve_with_until(
  self : App,
  server : @http.Server,
  stop~ : async () -> Unit,
  max_connections? : Int32,
) -> Unit {
  @async.with_task_group(group => {
    group.spawn_bg(no_wait=true, () => self.serve_with(server, max_connections?))
    stop()
    server.close()
  })
}

///|
/// Listen on `addr` until the `stop` task resolves.
pub async fn App::serve_until(
  self : App,
  addr : @socket.Addr,
  stop~ : async () -> Unit,
) -> Unit {
  self.serve_with_until(@http.Server(addr), stop~)
}

///|
/// Serve `server` until `stop` resolves, then drain in-flight requests.
///
/// Unlike [`App::serve_with_until`], which cancels every in-flight request as
/// soon as `stop` resolves, this variant performs a graceful shutdown:
///
/// 1. the listener is closed immediately so no new connections are accepted;
/// 2. requests that are already being handled are allowed to finish;
/// 3. requests arriving on kept-alive connections during the drain are
///    answered with `503 Service Unavailable`;
/// 4. `drain_timeout` milliseconds after `stop` any request still running is
///    cancelled and the server returns anyway.
///
/// A `drain_timeout` of `0` waits indefinitely for in-flight requests. An
/// error raised by `stop` propagates once the drain completes.
pub async fn App::serve_with_graceful_until(
  self : App,
  server : @http.Server,
  stop~ : async () -> Unit,
  drain_timeout~ : Int32 = 0,
  max_connections? : Int32,
) -> Unit {
  let app = self
  @async.with_task_group(group => {
    // Clear the drain flag once shutdown has completed so this application
    // can be served again later.
    defer {
      app.draining = false
    }
    let serving : @async.Task[Unit] = group.spawn(no_wait=true, () => {
      app.serve_with(server, max_connections?)
    })
    // A failing `stop` must not abort the drain; the error is re-raised after
    // in-flight requests have finished.
    let mut stop_error : Error? = None
    stop() catch {
      err => stop_error = Some(err)
    }
    server.close()
    app.draining = true
    let mut timed_out = false
    if drain_timeout > 0 {
      let mut waited = 0
      while app.in_flight.val > 0 && waited < drain_timeout {
        @async.sleep(10)
        waited = waited + 10
      }
      if app.in_flight.val > 0 {
        timed_out = true
        serving.cancel()
      }
    } else {
      // A zero timeout means waiting for in-flight requests without a bound.
      while app.in_flight.val > 0 {
        @async.sleep(10)
      }
    }
    if !timed_out {
      // Let idle kept-alive connections observe the drain and receive a
      // `503` for anything they send before the server task is cancelled.
      @async.sleep(GRACEFUL_DRAIN_SETTLE_MS)
      serving.cancel()
    }
    match stop_error {
      Some(err) => raise err
      None => ()
    }
  })
}

///|
/// Listen on `addr` until `stop` resolves, then drain in-flight requests.
pub async fn App::serve_graceful_until(
  self : App,
  addr : @socket.Addr,
  stop~ : async () -> Unit,
  drain_timeout~ : Int32 = 0,
) -> Unit {
  self.serve_with_graceful_until(@http.Server(addr), stop~, drain_timeout~)
}

///|
pub fn Feather::listen_address(self : Feather) -> String {
  let host = self.config.host
  let needs_brackets = host.contains(":") &&
    !(host.has_prefix("[") && host.has_suffix("]"))
  let display_host = if needs_brackets { "[" + host + "]" } else { host }
  "\{display_host}:\{self.config.port}"
}

///|
/// Resolve the configured host and port, falling back to a loopback address
/// when the host is not directly parseable (for example a host name).
fn Feather::resolve_addr(self : Feather) -> @socket.Addr raise {
  @socket.Addr::parse(self.listen_address()) catch {
    _ => @socket.Addr::parse("127.0.0.1:" + self.config.port.to_string())
  }
}

///|
pub async fn Feather::serve(self : Feather) -> Unit {
  self.app.serve(self.resolve_addr())
}

///|
pub async fn Feather::serve_with(
  self : Feather,
  server : @http.Server,
  max_connections? : Int32,
) -> Unit {
  self.app.serve_with(server, max_connections?)
}

///|
/// Serve the application until the `stop` task resolves.
pub async fn Feather::serve_with_until(
  self : Feather,
  server : @http.Server,
  stop~ : async () -> Unit,
  max_connections? : Int32,
) -> Unit {
  self.app.serve_with_until(server, stop~, max_connections?)
}

///|
/// Listen on the configured address until the `stop` task resolves.
pub async fn Feather::serve_until(
  self : Feather,
  stop~ : async () -> Unit,
) -> Unit {
  self.app.serve_until(self.resolve_addr(), stop~)
}

///|
/// Serve `server` until `stop` resolves, then drain in-flight requests.
pub async fn Feather::serve_with_graceful_until(
  self : Feather,
  server : @http.Server,
  stop~ : async () -> Unit,
  drain_timeout~ : Int32 = 0,
  max_connections? : Int32,
) -> Unit {
  self.app.serve_with_graceful_until(
    server,
    stop~,
    drain_timeout~,
    max_connections?,
  )
}

///|
/// Listen on the configured address until `stop` resolves, then drain
/// in-flight requests.
pub async fn Feather::serve_graceful_until(
  self : Feather,
  stop~ : async () -> Unit,
  drain_timeout~ : Int32 = 0,
) -> Unit {
  self.app.serve_graceful_until(self.resolve_addr(), stop~, drain_timeout~)
}
