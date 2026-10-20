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
const BODY_READ_CHUNK_SIZE : Int = 65536

///|
/// Upper bound on the buffer pre-sized from `Content-Length`.
const BODY_SIZE_HINT_LIMIT : Int = 1048576

///|
/// `Content-Length` clamped to the body limit and the pre-size cap, or `0` when
/// the header is absent or malformed.
fn body_size_hint(request : @http.Request, limit : Int32) -> Int {
  let limit_int = limit
  let cap : Int = if limit_int < BODY_SIZE_HINT_LIMIT {
    limit_int
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
async fn read_body_bytes(
  reader : &@io.Reader,
  limit : Int32,
  size_hint~ : Int = 0,
) -> Bytes {
  let first = match reader.read_some(max_len=BODY_READ_CHUNK_SIZE) {
    None => return b""
    Some(chunk) => chunk
  }
  let mut total = first.length()
  if total > limit {
    raise PayloadTooLarge
  }
  let limit_int = limit
  let first_length = first.length()
  let hint : Int = if size_hint > first_length {
    if size_hint < limit_int { size_hint } else { limit_int }
  } else if first_length < limit_int {
    first_length
  } else {
    limit_int
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
  size_hint~ : Int = 0,
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
  let reader = @io.MemoryReader(async fn(writer) {
    writer.write(data)
  })
  defer reader.close()
  let decoder = @gzip.Decoder::Decoder(reader)
  let limit_int = limit
  let hint : Int = if data.length() * 4 < limit_int {
    data.length() * 4
  } else {
    limit_int
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
async fn request_from_http(
  request : @http.Request,
  body : &@io.Reader,
  max_body_size : Int32,
) -> Request {
  let gzip_encoded = match request.headers.get(header_content_encoding) {
    Some(value) =>
      trim_ascii_space(value.view()).equal_ignore_ascii_case("gzip".view())
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
      (text.view().equal_ignore_ascii_case("content-encoding".view()) ||
        text.view().equal_ignore_ascii_case("content-length".view()))
    if !stale_length {
      headers.set(text, value)
    }
  }
  let body_hint = body_size_hint(request, max_body_size)
  let body_text = if gzip_encoded {
    @utf8.decode_lossy(
      decode_gzip_body(
        read_body_bytes(body, max_body_size, size_hint=body_hint),
        max_body_size,
      ),
    )
  } else {
    read_body(body, max_body_size, size_hint=body_hint)
  }
  {
    method: request_method_to_string(request.meth),
    path: request.path,
    headers,
    body: body_text,
  }
}

///|
/// Bounded caches of the most recently built validators, keyed by file path.
/// Each entry records the `(size, mtime)` it was built from, so a changed file
/// replaces its stale validators on the next request. The precompressed
/// representation has its own cache because it has different size and mtime
/// but keeps the `Content-Type` derived from the original path.
let validators_cache : Map[
  String,
  (Int64, Int64, Int, (String, String), String),
] = Map([])

///|
/// Recency ticks for `validators_cache`, driving the shared LRU eviction.
let validators_cache_ages : Map[String, Int] = Map([])

///|
/// Validators for precompressed representations, keyed by the source path.
let gzip_validators_cache : Map[
  String,
  (Int64, Int64, Int, (String, String), String),
] = Map([])

///|
/// Recency ticks for `gzip_validators_cache`.
let gzip_validators_cache_ages : Map[String, Int] = Map([])

///|
/// Maximum number of files tracked by each validators cache.
const VALIDATORS_CACHE_LIMIT : Int = 64

///|
/// Build the `ETag`, `Last-Modified` and `Content-Type` for a file from its
/// path, size and modification time.
fn file_validators(
  path : String,
  size : Int64,
  mtime_secs : Int64,
  mtime_nanos : Int,
  cache_key~ : String,
  gzip~ : Bool = false,
) -> (String, String, String) {
  let cache = if gzip { gzip_validators_cache } else { validators_cache }
  let ages = if gzip { gzip_validators_cache_ages } else { validators_cache_ages }
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
        match parse_http_date(value) {
          Some(since) => mtime_secs > 0L && mtime_secs == since
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
) -> Unit {
  let handle = @fs.open(file.path, mode=@fs.ReadOnly) catch {
    _ => {
      send_static_error(
        conn,
        response.headers,
        response.cookies,
        head,
        404,
        "404 Not Found",
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
      )
      return
    }
  }
  let mtime = handle.mtime() catch {
    _ => (0L, 0)
  }
  let (mtime_secs, mtime_nanos) = mtime
  let (etag, last_modified, _) = file_validators(
    file.path,
    size,
    mtime_secs,
    mtime_nanos,
    cache_key=file.path,
  )
  let headers : @http.Headers = Map([], capacity=response.headers.length() + 4)
  for name, value in response.headers {
    headers.set(header_key(name), value)
  }
  if !headers.contains(header_content_type) {
    headers.set(header_content_type, file.content_type)
  }
  if !headers.contains(header_etag) {
    headers.set(header_etag, etag)
  }
  if !headers.contains(header_last_modified) {
    headers.set(header_last_modified, last_modified)
  }
  if response.cookies.length() > 0 {
    headers.remove(header_set_cookie)
  }
  // A handler may override `ETag` / `Last-Modified`; preconditions must be
  // evaluated against the validators the response actually advertises.
  let effective_etag = headers.get(header_etag).unwrap_or(etag)
  let effective_mtime = match headers.get(header_last_modified) {
    Some(value) =>
      match parse_http_date(value) {
        Some(seconds) => seconds
        None => mtime_secs
      }
    None => mtime_secs
  }
  match evaluate_preconditions(
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
  let mut status = response.status
  let mut start = 0L
  let mut length = size
  if response.status == 200 && request.meth is @http.Get {
    match request.headers.get(header_range) {
      Some(value) =>
        if if_range_allows(request, effective_etag, effective_mtime) {
          match parse_byte_range(value, size) {
            ByteRangeSpec(range_start, range_end) => {
              status = 206
              start = range_start
              length = range_end - range_start + 1L
            }
            ByteRangeInvalid => {
              headers.remove(header_content_length)
              headers.set(header_content_range, "bytes */" + size.to_string())
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
      size.to_string(),
    )
  }
  if !headers.contains(header_accept_ranges) {
    headers.set(header_accept_ranges, "bytes")
  }
  let body_allowed = status != 204 && status != 205 && status != 304
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
    if start == 0L && length == size {
      conn.write_reader(handle)
    } else {
      write_file_range(conn, handle, start, length)
    }
  }
  conn.end_response()
}

///|
/// Bounded cache of formatted peer hosts, keyed by peer address.
let peer_host_cache : Map[@socket.Addr, String] = Map([])

///|
/// Recency ticks for `peer_host_cache`.
let peer_host_cache_ages : Map[@socket.Addr, Int] = Map([])

///|
/// Maximum number of peer addresses tracked by `peer_host_cache`.
const PEER_HOST_CACHE_LIMIT : Int = 64

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
fn utf8_byte_length(view : StringView) -> Int {
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
/// Bounded cache of `CaseInsensitiveString` header keys.
let header_name_cache : Map[String, @http.CaseInsensitiveString] = Map([])

///|
/// Recency ticks for `header_name_cache`.
let header_name_cache_ages : Map[String, Int] = Map([])

///|
/// Maximum number of header names tracked by `header_name_cache`.
const HEADER_NAME_CACHE_LIMIT : Int = 128

///|
/// Request header name spellings, keyed case-insensitively.
let request_header_name_cache : Map[@http.CaseInsensitiveString, String] = Map(
  [],
)

///|
/// Recency ticks for `request_header_name_cache`.
let request_header_name_ages : Map[@http.CaseInsensitiveString, Int] = Map([])

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
) -> Unit {
  let headers : @http.Headers = Map([], capacity=response.headers.length() + 1)
  for name, value in response.headers {
    headers.set(header_key(name), value)
  }
  let body_allowed = response.status >= 200 &&
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
      None => Some(@utf8.encode(response.body))
    }
  }
  if has_body && !headers.contains(header_content_length) {
    let body_length = match body_bytes {
      Some(data) => data.length()
      None =>
        match response.data {
          Some(data) => data.length()
          None => utf8_byte_length(response.body.view())
        }
    }
    headers.set(header_content_length, body_length.to_string())
  } else if !body_allowed {
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
  let bytes = @utf8.encode(body)
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
/// Context state key marking that the middleware chain called through to an
/// asynchronous endpoint (WebSocket, SSE or streaming response).
const ASYNC_CHAIN_PASS_KEY : String = "__feather_async_pass"

///|
/// Send the response a short-circuiting middleware produced for an
/// asynchronous endpoint, supporting both ordinary bodies and file responses.
async fn send_context_response(
  conn : @http.ServerConnection,
  ctx : Context,
  head : Bool,
  request : @http.Request,
) -> Unit {
  match ctx.file_response() {
    Some(file) => send_file_response(conn, ctx.response, file, head, request)
    None => send_response(conn, ctx.response, head)
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
  chain(ctx) catch {
    HttpError(status, message) => error_response(ctx, status, message)
    HttpErrorPayload(status, message, payload) =>
      error_response_with_payload(ctx, status, message, payload)
    err => internal_error(ctx, "\{err}")
  }
  ctx.state.get(ASYNC_CHAIN_PASS_KEY) is Some(_)
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
    if !is_stream_reserved_header(name) {
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
fn append_trailing_slash(path : String) -> String {
  match path.find("?") {
    Some(index) => path[:index].to_owned() + "/" + path[index:].to_owned()
    None => path + "/"
  }
}

///|
/// Read buffers used by `write_file_range`. The async runtime is single
/// threaded, so a plain array is safe.
let file_range_buffers : Array[FixedArray[Byte]] = []

///|
/// Maximum number of range buffers retained.
const FILE_RANGE_POOL_LIMIT : Int = 4

///|
/// Size of the range buffers.
const FILE_RANGE_CHUNK_SIZE : Int = 65536

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
    let read = file.read_at(buffer, position=position, len=want) catch {
      _ => 0
    }
    if read <= 0 {
      break
    }
    conn.write(buffer.unsafe_reinterpret_as_bytes()[:read])
    remaining = remaining - read.to_int64()
    position = position + read.to_int64()
  }
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
      if !header_list_has_token(existing.view(), value.view()) {
        headers.set(header_vary, existing + ", " + value)
      }
    None => headers.set(header_vary, value)
  }
}

///|
/// Bounded cache recording whether a static file has a precompressed `.gz`
/// sibling, keyed by path and validated against the base file's `(size, mtime)`
/// so a changed file is probed again.
let gzip_probe_cache : Map[String, (Int64, Int64, Int, Bool)] = Map([])

///|
/// Recency ticks for `gzip_probe_cache`.
let gzip_probe_ages : Map[String, Int] = Map([])

///|
/// Maximum number of paths tracked by `gzip_probe_cache`.
const GZIP_PROBE_CACHE_LIMIT : Int = 64

///|
/// Build the outgoing headers for a static response, seeding them with the
/// headers a request context accumulated. A `Set-Cookie` entry is dropped when
/// the response carries cookies, which are sent separately.
fn static_base_headers(
  extra_headers : Map[String, String],
  cookies : Array[@http.Cookie],
  capacity : Int,
) -> @http.Headers {
  let headers : @http.Headers = Map(
    [],
    capacity=extra_headers.length() + capacity,
  )
  for name, value in extra_headers {
    if cookies.length() > 0 &&
      name.view().equal_ignore_ascii_case("set-cookie".view()) {
      continue
    }
    headers.set(header_key(name), value)
  }
  headers
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
) -> Unit {
  let bytes = @utf8.encode(body)
  let headers = static_base_headers(extra_headers, cookies, 2)
  headers.set(header_content_type, "text/plain; charset=utf-8")
  headers.set(header_content_length, bytes.length().to_string())
  send_with_date(conn, code, status_text(code), headers, cookies~)
  if !head {
    conn.write(bytes)
  }
  conn.end_response()
}

///|
/// Add the negotiation headers a static file response needs.
fn decorate_static_headers(
  headers : @http.Headers,
  precompressed : Bool,
  serving_gzip : Bool,
) -> Unit {
  if precompressed {
    add_vary_header(headers, "Accept-Encoding")
  }
  if serving_gzip {
    headers.set(header_content_encoding, "gzip")
  }
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
  extra_headers : Map[String, String],
  cookies : Array[@http.Cookie],
) -> Unit {
  let mut gzip_handle : @fs.File? = None
  let base : @fs.File? = Some(@fs.open(file_path, mode=@fs.ReadOnly)) catch {
    _ => {
      // A mount may ship only the precompressed sibling of an asset, so probe
      // it before reporting the source file as missing.
      if precompressed {
        match request.headers.get(header_accept_encoding) {
          Some(value) =>
            if accept_encoding_allows_gzip_cached(value) {
              gzip_handle = open_precompressed_gzip(file_path)
            }
          None => ()
        }
      }
      if gzip_handle is None {
        send_static_error(conn, extra_headers, cookies, head, 404, "404 Not Found")
        return
      }
      None
    }
  }
  match base {
    Some(handle) =>
      if handle.kind() is @fs.Directory {
        handle.close()
        let location = append_trailing_slash(request.path)
        let headers = static_base_headers(extra_headers, cookies, 1)
        headers.set(header_location, location)
        send_with_date(conn, 301, "Moved Permanently", headers, cookies~)
        conn.end_response()
        return
      }
    None => ()
  }
  if precompressed && gzip_handle is None {
    match base {
      Some(base_file) =>
        match request.headers.get(header_accept_encoding) {
          Some(value) =>
            if accept_encoding_allows_gzip_cached(value) {
              let base_size = base_file.size() catch {
                _ => 0L
              }
              let base_mtime = base_file.mtime() catch {
                _ => (0L, 0)
              }
              let (base_secs, base_nanos) = base_mtime
              let mut has_gzip = false
              let mut known = false
              match gzip_probe_cache.get(file_path) {
                Some((cached_size, cached_secs, cached_nanos, cached_has)) =>
                  if cached_size == base_size &&
                    cached_secs == base_secs &&
                    cached_nanos == base_nanos {
                    has_gzip = cached_has
                    known = true
                    cache_touch(gzip_probe_ages, file_path)
                  }
                None => ()
              }
              if !known {
                gzip_handle = open_precompressed_gzip(file_path)
                has_gzip = gzip_handle is Some(_)
                cache_set(
                  gzip_probe_cache,
                  gzip_probe_ages,
                  GZIP_PROBE_CACHE_LIMIT,
                  file_path,
                  (base_size, base_secs, base_nanos, has_gzip),
                )
              } else if has_gzip {
                gzip_handle = open_precompressed_gzip(file_path)
                if gzip_handle is None {
                  cache_set(
                    gzip_probe_cache,
                    gzip_probe_ages,
                    GZIP_PROBE_CACHE_LIMIT,
                    file_path,
                    (base_size, base_secs, base_nanos, false),
                  )
                }
              }
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
          send_static_error(conn, extra_headers, cookies, head, 404, "404 Not Found")
          return
        }
      }
  }
  defer file.close()
  let size = file.size() catch {
    _ => 0L
  }
  let mtime = file.mtime() catch {
    _ => (0L, 0)
  }
  let (mtime_secs, mtime_nanos) = mtime
  let (etag, last_modified, content_type_value) = file_validators(
    file_path,
    size,
    mtime_secs,
    mtime_nanos,
    cache_key=file_path,
    gzip=serving_gzip,
  )
  let etag_key = header_etag
  let last_modified_key = header_last_modified
  let cache_control_key = header_cache_control
  match evaluate_preconditions(request, etag, mtime_secs, true) {
    PreconditionFailed => {
      send_static_error(conn, extra_headers, cookies, head, 412, "412 Precondition Failed")
      return
    }
    PreconditionNotModified => {
      let headers = static_base_headers(extra_headers, cookies, 2)
      headers.set(etag_key, etag)
      headers.set(last_modified_key, last_modified)
      if cache_control != "" {
        headers.set(cache_control_key, cache_control)
      }
      decorate_static_headers(headers, precompressed, serving_gzip)
      send_with_date(conn, 304, "Not Modified", headers, cookies~)
      conn.end_response()
      return
    }
    PreconditionPass => ()
  }
  let range = if head {
    ByteRangeFull
  } else {
    match request.headers.get(header_range) {
      Some(value) =>
        if if_range_allows(request, etag, mtime_secs) {
          parse_byte_range(value, size)
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
      headers.set(content_range_key, "bytes */" + size.to_string())
      headers.set(accept_ranges_key, "bytes")
      decorate_static_headers(headers, precompressed, serving_gzip)
      send_with_date(conn, 416, "Range Not Satisfiable", headers, cookies~)
      conn.end_response()
    }
    ByteRangeSpec(start, end) => {
      let length = end - start + 1L
      let headers = static_base_headers(extra_headers, cookies, 6)
      headers.set(content_type_key, content_type_value)
      headers.set(content_length_key, length.to_string())
      headers.set(
        content_range_key,
        "bytes " +
        start.to_string() +
        "-" +
        end.to_string() +
        "/" +
        size.to_string(),
      )
      headers.set(etag_key, etag)
      headers.set(last_modified_key, last_modified)
      headers.set(accept_ranges_key, "bytes")
      if cache_control != "" {
        headers.set(cache_control_key, cache_control)
      }
      decorate_static_headers(headers, precompressed, serving_gzip)
      send_with_date(conn, 206, "Partial Content", headers, cookies~)
      if !head {
        write_file_range(conn, file, start, length)
      }
      conn.end_response()
    }
    ByteRangeFull => {
      let headers = static_base_headers(extra_headers, cookies, 5)
      headers.set(content_type_key, content_type_value)
      headers.set(content_length_key, size.to_string())
      headers.set(etag_key, etag)
      headers.set(last_modified_key, last_modified)
      headers.set(accept_ranges_key, "bytes")
      if cache_control != "" {
        headers.set(cache_control_key, cache_control)
      }
      decorate_static_headers(headers, precompressed, serving_gzip)
      send_with_date(conn, 200, "OK", headers, cookies~)
      if !head {
        conn.write_reader(file)
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
) -> Unit {
  if app.middlewares.length() == 0 && mount.middlewares.length() == 0 {
    serve_static_file(
      conn,
      file_path,
      head,
      request,
      cache_control,
      precompressed,
      Map([]),
      [],
    )
    return
  }
  let req = request_from_http(request, body, app.max_body_size) catch {
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
  chain(ctx) catch {
    HttpError(status, message) => error_response(ctx, status, message)
    HttpErrorPayload(status, message, payload) =>
      error_response_with_payload(ctx, status, message, payload)
    err => internal_error(ctx, "\{err}")
  }
  if ctx.state.get(STATIC_CHAIN_PASS_KEY) is Some(_) {
    serve_static_file(
      conn,
      file_path,
      head,
      request,
      cache_control,
      precompressed,
      ctx.response.headers,
      ctx.response.cookies,
    )
  } else {
    match ctx.file_response() {
      Some(file) => send_file_response(conn, ctx.response, file, head, request)
      None => {
        let (input, allows_not_modified) = precondition_input_http(request)
        let (failed, remaining) = precheck_preconditions(
          input,
          allows_not_modified,
          ctx.response,
        )
        if !failed {
          if app.compress_enabled {
            compress_response(request, ctx.response, app.compress_min_size)
          }
          if app.etag_enabled {
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
) -> (Response, FileResponse?) {
  let req = request_from_http(request, body, app.max_body_size)
  let ctx = app.context_for_request(req)
  ctx.state.set("remote_addr", socket_addr_host(conn.client_addr()))
  app.handle(ctx) catch {
    HttpError(status, message) => error_response(ctx, status, message)
    HttpErrorPayload(status, message, payload) =>
      error_response_with_payload(ctx, status, message, payload)
    err => internal_error(ctx, "\{err}")
  }
  let file = ctx.file_response()
  if file is None {
    let (input, allows_not_modified) = precondition_input_http(request)
    let (failed, remaining) = precheck_preconditions(
      input,
      allows_not_modified,
      ctx.response,
    )
    if !failed {
      if app.compress_enabled {
        compress_response(request, ctx.response, app.compress_min_size)
      }
      if app.etag_enabled {
        apply_etag(ctx.response)
      }
      apply_preconditions_input(remaining, allows_not_modified, ctx.response)
    }
  }
  (ctx.response, file)
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
) -> Unit {
  let req = request_from_http(request, body, app.max_body_size) catch {
    PayloadTooLarge => {
      send_error_and_close(conn, 413, "413 Payload Too Large", false)
      return
    }
    MalformedRequestBody => {
      send_simple(conn, 400, "400 Bad Request", false)
      return
    }
    _ => {
      send_error_and_close(conn, 500, "500 Internal Server Error", false)
      return
    }
  }
  let ctx = app.context_for_request(req)
  defer ctx.run_cleanups()
  ctx.state.set("remote_addr", socket_addr_host(conn.client_addr()))
  for name, value in params {
    ctx.state.set(PARAM_PREFIX + name, value)
  }
  if !app.run_async_middleware(ctx, route_chain) {
    send_context_response(conn, ctx, false, request)
    return
  }
  let socket = @websocket.from_http_server(request, conn) catch {
    _ => return
  }
  defer conn.close()
  defer socket.close()
  handler(ctx, socket) catch {
    _ => ()
  }
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
) -> Unit {
  let req = request_from_http(request, body, app.max_body_size) catch {
    PayloadTooLarge => {
      send_error_and_close(conn, 413, "413 Payload Too Large", false)
      return
    }
    MalformedRequestBody => {
      send_simple(conn, 400, "400 Bad Request", false)
      return
    }
    _ => {
      send_error_and_close(conn, 500, "500 Internal Server Error", false)
      return
    }
  }
  let ctx = app.context_for_request(req)
  defer ctx.run_cleanups()
  ctx.state.set("remote_addr", socket_addr_host(conn.client_addr()))
  for name, value in params {
    ctx.state.set(PARAM_PREFIX + name, value)
  }
  if !app.run_async_middleware(ctx, route_chain) {
    send_context_response(conn, ctx, false, request)
    return
  }
  let headers : @http.Headers = Map(
    [],
    capacity=ctx.response.headers.length() + 3,
  )
  for name, value in ctx.response.headers {
    if !is_stream_reserved_header(name) &&
      !name.view().equal_ignore_ascii_case("content-type".view()) {
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
  send_with_date(conn, 200, "OK", headers, cookies=ctx.response.cookies)
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
) -> Unit {
  let req = request_from_http(request, body, app.max_body_size) catch {
    PayloadTooLarge => {
      send_error_and_close(conn, 413, "413 Payload Too Large", false)
      return
    }
    MalformedRequestBody => {
      send_simple(conn, 400, "400 Bad Request", false)
      return
    }
    _ => {
      send_error_and_close(conn, 500, "500 Internal Server Error", false)
      return
    }
  }
  let ctx = app.context_for_request(req)
  defer ctx.run_cleanups()
  ctx.state.set("remote_addr", socket_addr_host(conn.client_addr()))
  for name, value in params {
    ctx.state.set(PARAM_PREFIX + name, value)
  }
  if !app.run_async_middleware(ctx, route_chain) {
    send_context_response(conn, ctx, false, request)
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
  send_continue_if_expected(request, conn)
  let head = request.meth is @http.Head
  if request.meth is @http.Get {
    match app.resolve_websocket_full(request.path) {
      Some((handler, params, middlewares)) => {
        handle_websocket(app, request, body, conn, handler, params, middlewares)
        return
      }
      None =>
        match app.resolve_sse_full(request.path) {
          Some((handler, params, middlewares)) => {
            handle_sse(app, request, body, conn, handler, params, middlewares)
            return
          }
          None =>
            match app.resolve_stream_full(request.path) {
              Some((handler, params, middlewares)) => {
                handle_stream(
                  app,
                  request,
                  body,
                  conn,
                  handler,
                  params,
                  middlewares,
                )
                return
              }
              None => ()
            }
        }
    }
  }
  // Dynamic routes take precedence over static mounts, so check them first.
  // A failed GET resolve above already proves there is no websocket, SSE or
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
        handle_static(
          app,
          request,
          body,
          conn,
          file_path,
          cache_control,
          precompressed,
          mount,
          head,
        )
        return
      }
      None => ()
    }
  }
  let (response, file) = if app.timeout > 0 {
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
    Some(file) => send_file_response(conn, response, file, head, request)
    None => send_response(conn, response, head)
  }
}

///|
pub async fn App::serve_with(
  self : App,
  server : @http.Server,
  max_connections? : Int32,
) -> Unit {
  server.run_forever(
    (
      request : @http.Request,
      body : &@io.Reader,
      conn : @http.ServerConnection,
    ) => handle_request(self, request, body, conn),
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
