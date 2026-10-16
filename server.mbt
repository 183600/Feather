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
async fn read_body(reader : &@io.Reader, limit : Int32) -> String {
  let first = match reader.read_some(max_len=8192) {
    None => return ""
    Some(chunk) => chunk
  }
  let first_length = first.length()
  if first_length > limit {
    raise PayloadTooLarge
  }
  match reader.read_some(max_len=8192) {
    None => @utf8.decode_lossy(first)
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
      @utf8.decode_lossy(buffer.to_bytes())
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
async fn request_from_http(
  request : @http.Request,
  body : &@io.Reader,
  max_body_size : Int32,
) -> Request {
  let headers : Map[String, String] = Map([], capacity=request.headers.length())
  for name, value in request.headers {
    headers.set(name.to_string(), value)
  }
  {
    method: request_method_to_string(request.meth),
    path: request.path,
    headers,
    body: read_body(body, max_body_size),
  }
}

///|
async fn send_file_response(
  conn : @http.ServerConnection,
  response : Response,
  file : FileResponse,
  head : Bool,
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
  let headers : @http.Headers = Map([], capacity=response.headers.length() + 2)
  for name, value in response.headers {
    headers.set(@http.CaseInsensitiveString(name), value)
  }
  if !headers.contains(header_content_type) {
    headers.set(header_content_type, file.content_type)
  }
  if !headers.contains(header_content_length) {
    headers.set(header_content_length, size.to_string())
  }
  if response.cookies.length() > 0 {
    headers.remove(header_set_cookie)
  }
  conn.send_response(
    response.status,
    status_text(response.status),
    extra_headers=headers,
    cookies=response.cookies,
  )
  if !head && size > 0L {
    conn.write_reader(handle)
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
  conn.send_response(
    response.status,
    status_text(response.status),
    extra_headers=headers,
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
  conn.send_response(
    code,
    status_text(code),
    extra_headers=Map([
      (@http.CaseInsensitiveString("Content-Type"), "text/plain; charset=utf-8"),
    ]),
  )
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
    conn.send_response(
      301,
      "Moved Permanently",
      extra_headers=Map([
        (@http.CaseInsensitiveString("Location"), location),
      ]),
    )
    conn.end_response()
    return
  }
  let size = file.size() catch {
    _ => 0L
  }
  let (mtime_secs, mtime_nanos) = match (file.mtime() catch {
    _ => (0L, 0)
  }) {
    (secs, nanos) => (secs, nanos)
  }
  let etag = "\"" +
    size.to_string() +
    "-" +
    mtime_secs.to_string() +
    "-" +
    mtime_nanos.to_string() +
    "\""
  let last_modified = format_http_date(mtime_secs)
  let etag_key = header_etag
  let last_modified_key = header_last_modified
  let cache_control_key = header_cache_control
  let not_modified = match request.headers.get(header_if_none_match) {
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
  if not_modified {
    let headers : @http.Headers = Map([
      (etag_key, etag),
      (last_modified_key, last_modified),
    ])
    if cache_control != "" {
      headers.set(cache_control_key, cache_control)
    }
    conn.send_response(304, "Not Modified", extra_headers=headers)
    conn.end_response()
    return
  }
  let range_allowed = match request.headers.get(header_if_range) {
    Some(value) =>
      value == etag ||
      (match parse_http_date(value) {
        Some(since) => mtime_secs > 0L && mtime_secs <= since
        None => false
      })
    None => true
  }
  let range = match request.headers.get(header_range) {
    Some(value) =>
      if range_allowed {
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
      conn.send_response(
        416,
        "Range Not Satisfiable",
        extra_headers=Map([
          (content_range_key, "bytes */" + size.to_string()),
          (accept_ranges_key, "bytes"),
        ]),
      )
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
      conn.send_response(206, "Partial Content", extra_headers=headers)
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
      conn.send_response(200, "OK", extra_headers=headers)
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
  (ctx.response, ctx.file_response())
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
      err => {
        ignore(err)
        send_simple(conn, 500, "500 Internal Server Error", head)
        return
      }
    }
  }
  match file {
    Some(file) => send_file_response(conn, response, file, head)
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
pub async fn Feather::serve_with(self : Feather, server : @http.Server) -> Unit {
  self.app.serve_with(server)
}
