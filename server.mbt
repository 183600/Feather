///|
pub suberror PayloadTooLarge

///|
async fn read_body(reader : &@io.Reader, limit : Int32) -> String {
  let buffer = @buffer.Buffer::Buffer(size_hint=limit.min(4096).max(0))
  let mut total = 0
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
async fn send_response(
  conn : @http.ServerConnection,
  response : Response,
  head : Bool,
) -> Unit {
  let headers : @http.Headers = Map([], capacity=response.headers.length())
  for name, value in response.headers {
    headers.set(@http.CaseInsensitiveString(name), value)
  }
  conn.send_response(
    response.status,
    status_text(response.status),
    extra_headers=headers,
  )
  if !head && !response.body.is_empty() {
    conn.write_string(response.body)
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
async fn serve_static_file(
  conn : @http.ServerConnection,
  file_path : String,
  head : Bool,
) -> Unit {
  let file = @fs.open(file_path, mode=@fs.ReadOnly) catch {
    _ => {
      send_simple(conn, 404, "404 Not Found", head)
      return
    }
  }
  defer file.close()
  if file.kind() is @fs.Directory {
    send_simple(conn, 404, "404 Not Found", head)
    return
  }
  conn.send_response(
    200,
    "OK",
    extra_headers=Map([
      (@http.CaseInsensitiveString("Content-Type"), mime_type_for(file_path)),
    ]),
  )
  if !head {
    conn.write_reader(file)
  }
  conn.end_response()
}

///|
async fn build_response(
  app : App,
  request : @http.Request,
  body : &@io.Reader,
  conn : @http.ServerConnection,
) -> Response {
  let req = request_from_http(request, body, app.max_body_size)
  let ctx = Context::new(req)
  ctx.state.set("remote_addr", conn.client_addr().to_string())
  app.handle(ctx) catch {
    HttpError(status, message) => error_response(ctx, status, message)
    err => internal_error(ctx, "\{err}")
  }
  ctx.response
}

///|
async fn handle_request(
  app : App,
  request : @http.Request,
  body : &@io.Reader,
  conn : @http.ServerConnection,
) -> Unit {
  let head = request.meth is @http.Head
  match app.static_file_for(request.path) {
    Some(file_path) => {
      serve_static_file(conn, file_path, head)
      return
    }
    None => ()
  }
  let response = if app.timeout > 0 {
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
  send_response(conn, response, head)
}

///|
pub async fn App::serve_with(self : App, server : @http.Server) -> Unit {
  server.run_forever((
    request : @http.Request,
    body : &@io.Reader,
    conn : @http.ServerConnection,
  ) => handle_request(self, request, body, conn))
}

///|
pub async fn App::serve(self : App, addr : @socket.Addr) -> Unit {
  self.serve_with(@http.Server(addr))
}

///|
pub async fn Feather::serve(self : Feather) -> Unit {
  let addr = @socket.Addr::parse("\{self.config.host}:\{self.config.port}")
  self.app.serve(addr)
}
