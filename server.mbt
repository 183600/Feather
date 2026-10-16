///|
pub suberror PayloadTooLarge

///|
let header_if_none_match : @http.CaseInsensitiveString = @http.CaseInsensitiveString(
  "If-None-Match",
)

///|
let header_if_modified_since : @http.CaseInsensitiveString = @http.CaseInsensitiveString(
  "If-Modified-Since",
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
/// Raised when a request body declares a content coding but cannot be decoded.
priv suberror MalformedRequestBody

///|
let cached_date_second : Ref[Int64] = Ref(-1L)

///|
let cached_date_value : Ref[String] = Ref("")

///|
/// `format_http_date` for the current second, memoized so a burst of
/// responses within the same second reuses one formatted `Date` value.
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
  match reader.read_some(max_len=8192) {
    None => first
    Some(second) => {
      let mut total = first_length + second.length()
      if total > limit {
        raise PayloadTooLarge
      }
      let buffer = @buffer.Buffer::Buffer(size_hint=total)
      buffer.write_bytes(first)
      buffer.write_bytes(second)
      let mut done = false
      while !done {
        match reader.read_some(max_len=8192) {
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
  }
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
  let buffer = @buffer.Buffer::Buffer(size_hint=data.length())
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
/// Build the `ETag` and `Last-Modified` validators for a file from its size
/// and modification time.
fn file_validators(
  size : Int64,
  mtime_secs : Int64,
  mtime_nanos : Int,
) -> (String, String) {
  let etag = "\"" +
    size.to_string() +
    "-" +
    mtime_secs.to_string() +
    "-" +
    mtime_nanos.to_string() +
    "\""
  (etag, format_http_date(mtime_secs))
}

///|
/// Whether the request's conditional headers allow answering `304 Not Modified`
/// for a representation identified by `etag` / `mtime_secs`.
///
/// `If-None-Match` takes precedence over `If-Modified-Since`.
fn conditional_not_modified(
  request : @http.Request,
  etag : String,
  mtime_secs : Int64,
) -> Bool {
  match request.headers.get(header_if_none_match) {
    Some(value) => etag_header_matches(value.view(), etag)
    None =>
      match request.headers.get(header_if_modified_since) {
        Some(value) =>
          match parse_http_date(value) {
            Some(since) => mtime_secs > 0L && mtime_secs <= since
            None => false
          }
        None => false
      }
  }
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
      value == etag ||
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
  let (etag, last_modified) = file_validators(size, mtime_secs, mtime_nanos)
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
  if conditional_not_modified(request, effective_etag, mtime_secs) {
    let not_modified_headers : @http.Headers = Map([], capacity=2)
    not_modified_headers.set(header_etag, effective_etag)
    match headers.get(header_last_modified) {
      Some(value) => not_modified_headers.set(header_last_modified, value)
      None => ()
    }
    send_with_date(
      conn,
      304,
      "Not Modified",
      not_modified_headers,
      cookies=response.cookies,
    )
    conn.end_response()
    return
  }
  let mut status = response.status
  let mut start = 0L
  let mut length = size
  match request.headers.get(header_range) {
    Some(value) => {
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
    }
    None => ()
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
  let body_allowed = status != 204 && status != 304
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
async fn send_response(
  conn : @http.ServerConnection,
  response : Response,
  head : Bool,
) -> Unit {
  let headers : @http.Headers = Map([], capacity=response.headers.length() + 1)
  for name, value in response.headers {
    headers.set(@http.CaseInsensitiveString(name), value)
  }
  let body_bytes = match response.data {
    Some(data) => data
    None =>
      if response.body.is_empty() {
        b""
      } else {
        @utf8.encode(response.body)
      }
  }
  let has_body = body_bytes.length() > 0
  if has_body && !headers.contains(header_content_length) {
    headers.set(header_content_length, body_bytes.length().to_string())
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
    conn.write(body_bytes)
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
  let headers : @http.Headers = Map([
    (@http.CaseInsensitiveString("Content-Type"), "text/plain; charset=utf-8"),
  ])
  send_with_date(conn, code, status_text(code), headers)
  if !head {
    conn.write_string(body)
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
  let chunk_size : Int32 = 65536
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
async fn serve_static_file(
  conn : @http.ServerConnection,
  file_path : String,
  head : Bool,
  request : @http.Request,
  cache_control : String,
) -> Unit {
  let file = @fs.open(file_path, mode=@fs.ReadOnly) catch {
    _ => {
      send_simple(conn, 404, "404 Not Found", head)
      return
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
  let size = file.size() catch {
    _ => 0L
  }
  let mtime = file.mtime() catch {
    _ => (0L, 0)
  }
  let (mtime_secs, mtime_nanos) = mtime
  let (etag, last_modified) = file_validators(size, mtime_secs, mtime_nanos)
  let etag_key = header_etag
  let last_modified_key = header_last_modified
  let cache_control_key = header_cache_control
  if conditional_not_modified(request, etag, mtime_secs) {
    let headers : @http.Headers = Map([
      (etag_key, etag),
      (last_modified_key, last_modified),
    ])
    if cache_control != "" {
      headers.set(cache_control_key, cache_control)
    }
    send_with_date(conn, 304, "Not Modified", headers)
    conn.end_response()
    return
  }
  let range = match request.headers.get(header_range) {
    Some(value) =>
      if if_range_allows(request, etag, mtime_secs) {
        parse_byte_range(value, size)
      } else {
        ByteRangeFull
      }
    None => ByteRangeFull
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
      send_with_date(conn, 416, "Range Not Satisfiable", headers)
      conn.end_response()
    }
    ByteRangeSpec(start, end) => {
      let length = end - start + 1L
      let headers : @http.Headers = Map([
        (content_type_key, mime_type_for(file_path)),
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
      send_with_date(conn, 206, "Partial Content", headers)
      if !head {
        write_file_range(conn, file, start, length)
      }
      conn.end_response()
    }
    ByteRangeFull => {
      let headers : @http.Headers = Map([
        (content_type_key, mime_type_for(file_path)),
        (content_length_key, size.to_string()),
        (etag_key, etag),
        (last_modified_key, last_modified),
        (accept_ranges_key, "bytes"),
      ])
      if cache_control != "" {
        headers.set(cache_control_key, cache_control)
      }
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
  ctx.state.set("remote_addr", conn.client_addr().to_string())
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
  ctx.state.set("remote_addr", conn.client_addr().to_string())
  for name, value in params {
    ctx.state.set(PARAM_PREFIX + name, value)
  }
  handler(ctx, socket) catch {
    _ => ()
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
      None => ()
    }
  }
  if head || request.meth is @http.Get {
    match app.static_file_for(request.path) {
      Some(file_path) =>
        if !app.has_route(if head { "HEAD" } else { "GET" }, request.path) {
          serve_static_file(
            conn,
            file_path,
            head,
            request,
            app.static_cache_control_for(request.path),
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
  let addr = @socket.Addr::parse(self.listen_address())
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
