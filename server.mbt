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
async fn read_body_bytes(reader : &@io.Reader, limit : Int32) -> Bytes {
  let first = match reader.read_some(max_len=8192) {
    None => return b""
    Some(chunk) => chunk
  }
  let first_length = first.length()
  if first_length > limit {
    raise PayloadTooLarge
  }
  let second = match reader.read_some(max_len=8192) {
    None => return first
    Some(chunk) => chunk
  }
  let mut total = first_length + second.length()
  if total > limit {
    raise PayloadTooLarge
  }
  let chunks : Array[Bytes] = [first, second]
  let mut done = false
  while !done {
    match reader.read_some(max_len=8192) {
      None => done = true
      Some(chunk) => {
        total = total + chunk.length()
        if total > limit {
          raise PayloadTooLarge
        }
        chunks.push(chunk)
      }
    }
  }
  let buffer = @buffer.Buffer::Buffer(size_hint=total)
  for chunk in chunks {
    buffer.write_bytes(chunk)
  }
  buffer.to_bytes()
}

///|
async fn read_body(reader : &@io.Reader, limit : Int32) -> String {
  @utf8.decode_lossy(read_body_bytes(reader, limit))
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
  let buffer = @buffer.Buffer::Buffer(size_hint=data.length() * 4)
  let mut total = 0
  let mut done = false
  while !done {
    let chunk = decoder.read_some(max_len=8192) catch {
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
    let text = name.to_string()
    let stale_length = gzip_encoded &&
      (text.view().equal_ignore_ascii_case("content-encoding".view()) ||
        text.view().equal_ignore_ascii_case("content-length".view()))
    if !stale_length {
      headers.set(text, value)
    }
  }
  let body_text = if gzip_encoded {
    @utf8.decode_lossy(
      decode_gzip_body(read_body_bytes(body, max_body_size), max_body_size),
    )
  } else {
    read_body(body, max_body_size)
  }
  {
    method: request_method_to_string(request.meth),
    path: request.path,
    headers,
    body: body_text,
  }
}

///|
/// Bounded cache of the most recently built validators, keyed by file path.
/// Each entry records the `(size, mtime)` it was built from, so a changed
/// file replaces its stale validators on the next request. The `Content-Type`
/// derived from the path is cached alongside them.
let validators_cache : Map[
  String,
  (Int64, Int64, Int, (String, String), String),
] = Map([])

///|
/// Recency ticks for `validators_cache`, driving the shared LRU eviction.
let validators_cache_ages : Map[String, Int] = Map([])

///|
/// Maximum number of files tracked by `validators_cache`.
const VALIDATORS_CACHE_LIMIT : Int = 64

///|
/// Build the `ETag`, `Last-Modified` and `Content-Type` for a file from its
/// path, size and modification time.
fn file_validators(
  path : String,
  size : Int64,
  mtime_secs : Int64,
  mtime_nanos : Int,
) -> (String, String, String) {
  match validators_cache.get(path) {
    Some((cached_size, cached_secs, cached_nanos, value, content_type)) =>
      if cached_size == size &&
        cached_secs == mtime_secs &&
        cached_nanos == mtime_nanos {
        cache_touch(validators_cache_ages, path)
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
    validators_cache,
    validators_cache_ages,
    VALIDATORS_CACHE_LIMIT,
    path,
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
    Some(value) =>
      trim_ascii_space(value.view()) == etag.view() ||
      (match parse_http_date(value) {
        Some(since) => mtime_secs > 0L && mtime_secs <= since
        None => false
      })
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
      send_simple(conn, 404, "404 Not Found", head)
      return
    }
  }
  defer handle.close()
  if handle.kind() is @fs.Directory {
    send_simple(conn, 404, "404 Not Found", head)
    return
  }
  let size = handle.size() catch {
    _ => {
      send_simple(conn, 500, "500 Internal Server Error", head)
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
  )
  let headers : @http.Headers = Map([], capacity=response.headers.length() + 4)
  for name, value in response.headers {
    headers.set(@http.CaseInsensitiveString(name), value)
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
  let effective_etag = headers.get(header_etag).unwrap_or(etag)
  match evaluate_preconditions(
    request,
    effective_etag,
    mtime_secs,
    head || request.meth is @http.Get,
  ) {
    PreconditionFailed => {
      send_simple(conn, 412, "412 Precondition Failed", head)
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
        if if_range_allows(request, effective_etag, mtime_secs) {
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
/// Last peer address formatted by `socket_addr_host` and its host string.
/// The async runtime is single threaded, so the plain refs are safe.
let cached_peer_addr : Ref[@socket.Addr?] = Ref(None)

///|
let cached_peer_host : Ref[String] = Ref("")

///|
/// Host part of a peer address, without the ephemeral port.
///
/// Recorded as the `remote_addr` context state so IP-based logic (logging,
/// `Context::ip`, rate limiting) keys by client rather than by connection.
fn socket_addr_host(addr : @socket.Addr) -> String {
  match cached_peer_addr.val {
    Some(cached) =>
      if cached == addr {
        return cached_peer_host.val
      }
    None => ()
  }
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
  cached_peer_addr.val = Some(addr)
  cached_peer_host.val = host
  host
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
async fn send_response(
  conn : @http.ServerConnection,
  response : Response,
  head : Bool,
) -> Unit {
  let headers : @http.Headers = Map([], capacity=response.headers.length() + 1)
  for name, value in response.headers {
    headers.set(@http.CaseInsensitiveString(name), value)
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
    (@http.CaseInsensitiveString("Content-Type"), "text/plain; charset=utf-8"),
    (header_content_length, bytes.length().to_string()),
  ])
  send_with_date(conn, code, status_text(code), headers)
  if !head {
    conn.write(bytes)
  }
  conn.end_response()
}

///|
fn append_trailing_slash(path : String) -> String {
  match path.find("?") {
    Some(index) => path[:index].to_owned() + "/" + path[index:].to_owned()
    None => path + "/"
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
  let chunk_size : Int32 = if length < 65536L { length.to_int() } else { 65536 }
  let buffer = FixedArray::make(chunk_size, b'\x00')
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
async fn serve_static_file(
  conn : @http.ServerConnection,
  file_path : String,
  head : Bool,
  request : @http.Request,
  cache_control : String,
  precompressed : Bool,
) -> Unit {
  let mut precompressed_handle : @fs.File? = None
  if precompressed {
    match request.headers.get(header_accept_encoding) {
      Some(value) =>
        if accept_encoding_allows_gzip_cached(value) {
          precompressed_handle = open_precompressed_gzip(file_path)
        }
      None => ()
    }
  }
  let serving_gzip = precompressed_handle is Some(_)
  let file = match precompressed_handle {
    Some(handle) => handle
    None => @fs.open(file_path, mode=@fs.ReadOnly) catch {
      _ => {
        send_simple(conn, 404, "404 Not Found", head)
        return
      }
    }
  }
  defer file.close()
  if file.kind() is @fs.Directory {
    let location = append_trailing_slash(request.path)
    let headers : @http.Headers = Map([
      (@http.CaseInsensitiveString("Location"), location),
    ])
    send_with_date(conn, 301, "Moved Permanently", headers)
    conn.end_response()
    return
  }
  let decorate_headers = fn(headers : @http.Headers) {
    if precompressed {
      add_vary_header(headers, "Accept-Encoding")
    }
    if serving_gzip {
      headers.set(header_content_encoding, "gzip")
    }
  }
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
  )
  let etag_key = header_etag
  let last_modified_key = header_last_modified
  let cache_control_key = header_cache_control
  match evaluate_preconditions(request, etag, mtime_secs, true) {
    PreconditionFailed => {
      send_simple(conn, 412, "412 Precondition Failed", head)
      return
    }
    PreconditionNotModified => {
      let headers : @http.Headers = Map([
        (etag_key, etag),
        (last_modified_key, last_modified),
      ])
      if cache_control != "" {
        headers.set(cache_control_key, cache_control)
      }
      decorate_headers(headers)
      send_with_date(conn, 304, "Not Modified", headers)
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
      let headers : @http.Headers = Map([
        (content_range_key, "bytes */" + size.to_string()),
        (accept_ranges_key, "bytes"),
      ])
      decorate_headers(headers)
      send_with_date(conn, 416, "Range Not Satisfiable", headers)
      conn.end_response()
    }
    ByteRangeSpec(start, end) => {
      let length = end - start + 1L
      let headers : @http.Headers = Map([
        (content_type_key, content_type_value),
        (content_length_key, length.to_string()),
        (
          content_range_key,
          "bytes " +
          start.to_string() +
          "-" +
          end.to_string() +
          "/" +
          size.to_string(),
        ),
        (etag_key, etag),
        (last_modified_key, last_modified),
        (accept_ranges_key, "bytes"),
      ])
      if cache_control != "" {
        headers.set(cache_control_key, cache_control)
      }
      decorate_headers(headers)
      send_with_date(conn, 206, "Partial Content", headers)
      if !head {
        write_file_range(conn, file, start, length)
      }
      conn.end_response()
    }
    ByteRangeFull => {
      let headers : @http.Headers = Map([
        (content_type_key, content_type_value),
        (content_length_key, size.to_string()),
        (etag_key, etag),
        (last_modified_key, last_modified),
        (accept_ranges_key, "bytes"),
      ])
      if cache_control != "" {
        headers.set(cache_control_key, cache_control)
      }
      decorate_headers(headers)
      send_with_date(conn, 200, "OK", headers)
      if !head {
        conn.write_reader(file)
      }
      conn.end_response()
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
  let ctx = Context::new(req)
  ctx.state.set("remote_addr", socket_addr_host(conn.client_addr()))
  app.handle(ctx) catch {
    HttpError(status, message) => error_response(ctx, status, message)
    HttpErrorPayload(status, message, payload) =>
      error_response_with_payload(ctx, status, message, payload)
    err => internal_error(ctx, "\{err}")
  }
  let file = ctx.file_response()
  if file is None && app.compress_enabled {
    compress_response(request, ctx.response, app.compress_min_size)
  }
  if file is None {
    if app.etag_enabled {
      apply_etag(ctx.response)
    }
    apply_preconditions(request, ctx.response)
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
) -> Unit {
  let req = request_from_http(request, body, app.max_body_size) catch {
    PayloadTooLarge => {
      send_simple(conn, 413, "413 Payload Too Large", false)
      return
    }
    MalformedRequestBody => {
      send_simple(conn, 400, "400 Bad Request", false)
      return
    }
    _ => {
      send_simple(conn, 500, "500 Internal Server Error", false)
      return
    }
  }
  let socket = @websocket.from_http_server(request, conn) catch {
    _ => return
  }
  defer conn.close()
  defer socket.close()
  let ctx = Context::new(req)
  defer ctx.run_cleanups()
  ctx.state.set("remote_addr", socket_addr_host(conn.client_addr()))
  for name, value in params {
    ctx.state.set(PARAM_PREFIX + name, value)
  }
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
) -> Unit {
  let req = request_from_http(request, body, app.max_body_size) catch {
    PayloadTooLarge => {
      send_simple(conn, 413, "413 Payload Too Large", false)
      return
    }
    MalformedRequestBody => {
      send_simple(conn, 400, "400 Bad Request", false)
      return
    }
    _ => {
      send_simple(conn, 500, "500 Internal Server Error", false)
      return
    }
  }
  let headers : @http.Headers = Map([
    (header_content_type, "text/event-stream; charset=utf-8"),
    (header_cache_control, "no-cache"),
    (header_x_accel_buffering, "no"),
  ])
  send_with_date(conn, 200, "OK", headers)
  conn.flush() catch {
    _ => {
      conn.close()
      return
    }
  }
  let ctx = Context::new(req)
  defer ctx.run_cleanups()
  ctx.state.set("remote_addr", socket_addr_host(conn.client_addr()))
  for name, value in params {
    ctx.state.set(PARAM_PREFIX + name, value)
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
) -> Unit {
  let req = request_from_http(request, body, app.max_body_size) catch {
    PayloadTooLarge => {
      send_simple(conn, 413, "413 Payload Too Large", false)
      return
    }
    MalformedRequestBody => {
      send_simple(conn, 400, "400 Bad Request", false)
      return
    }
    _ => {
      send_simple(conn, 500, "500 Internal Server Error", false)
      return
    }
  }
  let ctx = Context::new(req)
  defer ctx.run_cleanups()
  ctx.state.set("remote_addr", socket_addr_host(conn.client_addr()))
  for name, value in params {
    ctx.state.set(PARAM_PREFIX + name, value)
  }
  let stream = Stream::new(conn)
  let mut failed = false
  handler(ctx, stream) catch {
    _ => failed = true
  }
  if failed && !stream.is_started() {
    stream.abort()
    send_simple(conn, 500, "500 Internal Server Error", false) catch {
      _ => conn.close()
    }
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
  let head = request.meth is @http.Head
  if request.meth is @http.Get {
    match app.resolve_websocket(request.path) {
      Some((handler, params)) => {
        handle_websocket(app, request, body, conn, handler, params)
        return
      }
      None =>
        match app.resolve_sse(request.path) {
          Some((handler, params)) => {
            handle_sse(app, request, body, conn, handler, params)
            return
          }
          None =>
            match app.resolve_stream(request.path) {
              Some((handler, params)) => {
                handle_stream(app, request, body, conn, handler, params)
                return
              }
              None => ()
            }
        }
    }
  }
  if (head || request.meth is @http.Get) && !app.static_mounts.is_empty() {
    // Dynamic routes take precedence over static mounts, so check them first
    // and skip the static lookup (and cache bookkeeping) entirely when the
    // request is handled elsewhere.
    if !app.has_route(if head { "HEAD" } else { "GET" }, request.path) &&
      !app.has_websocket(request.path) &&
      !app.has_sse(request.path) &&
      !app.has_stream(request.path) {
      match app.static_lookup(request.path) {
        Some((file_path, cache_control, precompressed)) => {
          serve_static_file(
            conn,
            file_path,
            head,
            request,
            cache_control,
            precompressed,
          )
          return
        }
        None => ()
      }
    }
  }
  let (response, file) = if app.timeout > 0 {
    @async.with_timeout(app.timeout, () => {
      build_response(app, request, body, conn)
    }) catch {
      @async.TimeoutError => {
        send_simple(conn, 504, "504 Gateway Timeout", head)
        return
      }
      PayloadTooLarge => {
        send_simple(conn, 413, "413 Payload Too Large", head)
        return
      }
      MalformedRequestBody => {
        send_simple(conn, 400, "400 Bad Request", head)
        return
      }
      err => {
        ignore(err)
        send_simple(conn, 500, "500 Internal Server Error", head)
        return
      }
    }
  } else {
    build_response(app, request, body, conn) catch {
      PayloadTooLarge => {
        send_simple(conn, 413, "413 Payload Too Large", head)
        return
      }
      MalformedRequestBody => {
        send_simple(conn, 400, "400 Bad Request", head)
        return
      }
      err => {
        ignore(err)
        send_simple(conn, 500, "500 Internal Server Error", head)
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
pub fn Feather::listen_address(self : Feather) -> String {
  let host = self.config.host
  let needs_brackets = host.contains(":") &&
    !(host.has_prefix("[") && host.has_suffix("]"))
  let display_host = if needs_brackets { "[" + host + "]" } else { host }
  "\{display_host}:\{self.config.port}"
}

///|
pub async fn Feather::serve(self : Feather) -> Unit {
  let addr = @socket.Addr::parse(self.listen_address()) catch {
    _ => @socket.Addr::parse("127.0.0.1:" + self.config.port.to_string())
  }
  self.app.serve(addr)
}

///|
pub async fn Feather::serve_with(
  self : Feather,
  server : @http.Server,
  max_connections? : Int32,
) -> Unit {
  self.app.serve_with(server, max_connections?)
}
