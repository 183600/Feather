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
  let (req, raw_body) = match
    request_from_http_with_timeout(app, request, body, conn) {
    Some(prepared) => prepared
    None => return
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
  ctx.response.status = 101
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
  let (req, raw_body) = match
    request_from_http_with_timeout(app, request, body, conn) {
    Some(prepared) => prepared
    None => return
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
  ctx.response.status = 200
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
  let (req, raw_body) = match
    request_from_http_with_timeout(app, request, body, conn) {
    Some(prepared) => prepared
    None => return
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
      context=ctx,
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
    context=ctx,
  )
  let mut failed = false
  handler(ctx, stream) catch {
    _ => failed = true
  }
  if failed && !stream.is_started() {
    stream.abort()
    ctx.response.status = 500
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
  // RFC 9110 §10.1.1 requires a 417 when the client asks for an expectation
  // this server does not implement. Reject before reading the body and close,
  // because the unread upload would otherwise pin the connection.
  match request.headers.get(header_expect) {
    Some(value) =>
      if !expectation_supported(value.view()) {
        send_error_and_close(conn, 417, "417 Expectation Failed", head)
        return
      }
    None => ()
  }
  let request_coding = match request.headers.get(header_content_encoding) {
    Some(value) => request_body_coding(value.view())
    None => RequestBodyIdentity
  }
  // An undecodable coding is rejected before the body limit is considered, so
  // the client learns that the representation cannot be decoded rather than
  // receiving a misleading 413 for a body the server would never hand to a
  // handler. This also avoids reading an upload whose coding is already known
  // to be unusable.
  if request_coding is RequestBodyUnsupported {
    send_error_and_close(
      conn, 415, "415 Unsupported Media Type", head,
    )
    return
  }
  // Reject a declared oversized body before the `100-continue` handshake or
  // the first read, so a client that never uploads cannot pin the connection.
  // For a gzip-coded body the declared length describes the compressed input,
  // which is allowed to exceed the decoded limit by the codec overhead.
  let declared_limit = match request_coding {
    RequestBodyGzip => gzip_body_read_limit(app.max_body_size)
    _ => app.max_body_size
  }
  if declared_body_exceeds_limit(request, declared_limit) {
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
  let response_started = Ref(false)
  let send_dynamic = () => {
    let (response, file, auto_etag, compress, compress_min_size) =
      build_response(app, request, body, conn)
    // From here on the response header may be written. A timeout racing with
    // the first write must close the connection instead of sending a second
    // response on a connection that already started framing a body.
    response_started.val = true
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
      None => {
        apply_buffered_range_http(request, response, head)
        send_response(
          conn,
          response,
          head,
          connect=request.meth is @http.Connect,
        )
      }
    }
  }
  if app.timeout > 0 {
    @async.with_timeout(app.timeout, send_dynamic) catch {
      @async.TimeoutError =>
        if response_started.val {
          conn.close()
        } else {
          send_error_and_close(conn, 504, "504 Gateway Timeout", head)
        }
      PayloadTooLarge =>
        if response_started.val {
          conn.close()
        } else {
          send_error_and_close(conn, 413, "413 Payload Too Large", head)
        }
      MalformedRequestBody =>
        if response_started.val {
          conn.close()
        } else {
          send_simple(conn, 400, "400 Bad Request", head)
        }
      UnsupportedRequestBodyCoding =>
        if response_started.val {
          conn.close()
        } else {
          send_error_and_close(
            conn, 415, "415 Unsupported Media Type", head,
          )
        }
      err => {
        ignore(err)
        if response_started.val {
          conn.close()
        } else {
          send_error_and_close(conn, 500, "500 Internal Server Error", head)
        }
      }
    }
  } else {
    let (response, file, auto_etag, compress, compress_min_size) =
      build_response(app, request, body, conn) catch {
        PayloadTooLarge => {
          send_error_and_close(conn, 413, "413 Payload Too Large", head)
          return
        }
        MalformedRequestBody => {
          send_simple(conn, 400, "400 Bad Request", head)
          return
        }
        UnsupportedRequestBodyCoding => {
          send_error_and_close(conn, 415, "415 Unsupported Media Type", head)
          return
        }
        err => {
          ignore(err)
          send_error_and_close(conn, 500, "500 Internal Server Error", head)
          return
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
      None => {
        apply_buffered_range_http(request, response, head)
        send_response(
          conn,
          response,
          head,
          connect=request.meth is @http.Connect,
        )
      }
    }
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
