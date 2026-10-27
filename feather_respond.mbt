///|
pub fn App::max_body_size(self : App, size : Int32) -> App {
  self.max_body_size = size
  self
}

///|
/// Declare how many proxies in front of the application may be trusted when
/// the client address is derived from the forwarded headers.
///
/// `hops` counts the trusted proxies, starting at the one closest to the
/// application: with one trusted proxy, `Context::ip` reports the address
/// that proxy recorded for the client, and with two it reports the address the
/// outer proxy recorded. A negative `hops` trusts the whole forwarded chain
/// and reports the original client. `0`, the default, trusts no proxy at all,
/// so `Context::ip` keeps reporting the peer address.
///
/// The chain is read from the RFC 7239 `Forwarded` header when it carries
/// `for=` parameters, and from `X-Forwarded-For` otherwise. Both list the
/// client first, so the chain is walked from the closest proxy backwards.
/// Nodes that record no address remain in the chain, and selecting one reports
/// the peer address rather than an earlier, potentially spoofed entry.
pub fn App::trust_proxy(self : App, hops : Int32) -> App {
  self.trust_proxy_hops = hops
  self
}

///|
pub fn App::request_timeout(self : App, millis : Int32) -> App {
  self.timeout = millis
  self
}

///|
/// Methods an asynchronous endpoint on `path` can answer. WebSocket endpoints
/// only accept `GET` (an upgrade cannot be described by `HEAD`), while SSE and
/// streaming endpoints also support the bodyless `HEAD` description.
fn App::async_allowed_methods(
  self : App,
  path : StringView,
) -> Array[String] {
  let text = path.to_owned()
  let methods : Array[String] = []
  if !self.ws_handlers.is_empty() && self.ws_router.is_routable("GET", text) {
    methods.push("GET")
  } else if
    (!self.sse_handlers.is_empty() &&
      self.sse_router.is_routable("GET", text)) ||
    (!self.stream_handlers.is_empty() &&
      self.stream_router.is_routable("GET", text)) {
    methods.push("GET")
    methods.push("HEAD")
  }
  methods
}

///|
/// `Allow` methods for a path combining ordinary routes and asynchronous
/// endpoints. An ordinary `GET` route still implies `HEAD`, while a WebSocket
/// endpoint does not.
fn App::allowed_methods_with_async(
  self : App,
  path : StringView,
  async_methods : Array[String],
) -> Array[String] {
  let allowed = self.router.allowed_methods(path)
  if allowed.contains("GET") && !allowed.contains("HEAD") {
    allowed.push("HEAD")
  }
  for method in async_methods {
    if !allowed.contains(method) {
      allowed.push(method)
    }
  }
  // A WebSocket endpoint shadows ordinary GET/HEAD handling at the same path
  // and rejects HEAD, so an implicit or explicit HEAD must not be advertised.
  if async_methods.contains("GET") && !async_methods.contains("HEAD") {
    let without_head : Array[String] = []
    for method in allowed {
      if method != "HEAD" {
        without_head.push(method)
      }
    }
    allowed.clear()
    allowed.append(without_head)
  }
  allowed.sort()
  allowed
}

///|
/// Mount middleware and captured prefix parameters for the most specific
/// mounted application whose prefix contains `path`, or `None` when no mounted
/// application matches.
fn App::auto_mount_chain(
  self : App,
  path : StringView,
) -> (Array[Middleware], Map[String, String])? {
  let mut best : (Array[Middleware], Map[String, String])? = None
  let mut best_consumed = -1
  let mut best_params = 2147483647
  let mut best_length = -1
  for entry in self.mount_middlewares {
    let (prefix, middlewares) = entry
    match match_mount_prefix(path, prefix.view()) {
      Some(matched) => {
        let params = matched.params.length()
        let better = matched.consumed > best_consumed ||
          (
            matched.consumed == best_consumed &&
            (
              params < best_params ||
              (
                params == best_params &&
                prefix.length() >= best_length
              )
            )
          )
        if better {
          best = Some((middlewares, matched.params))
          best_consumed = matched.consumed
          best_params = params
          best_length = prefix.length()
        }
      }
      None => ()
    }
  }
  best
}

///|
/// Answer a synthesized method response under the mounted application's
/// middleware chain. Without this, CORS, authentication and security headers
/// installed on the child (or on `mount_with`) would be bypassed for automatic
/// `OPTIONS` and `405` responses.
fn App::run_mounted_method_response(
  self : App,
  ctx : Context,
  path : StringView,
  allow : String,
) -> Unit raise {
  let respond : Handler = fn(ctx) raise {
    if normalize_method(ctx.request.method) == "OPTIONS" {
      respond_options_with_allow(ctx, allow)
    } else {
      method_not_allowed_with_allow(ctx, allow)
    }
  }
  match self.auto_mount_chain(path) {
    Some((middlewares, params)) => {
      for name, value in params {
        ctx.state.set(param_state_key(name), value)
      }
      apply_middleware(middlewares, respond)(ctx)
    }
    None => respond(ctx)
  }
}

///|
pub fn App::handle(self : App, ctx : Context) -> Unit raise {
  self.merge_state(ctx)
  let chain = match self.chain {
    Some(chain) => chain
    None => {
      let router = self.router
      let terminal : Handler = fn(ctx) raise {
        let meth = normalize_method(ctx.request.method)
        let clean_path = clean_path_view(ctx.request.path)
        if meth == "OPTIONS" && clean_path == "*" {
          respond_app_server_options(ctx, self)
        } else {
          // Asynchronous endpoints live in their own routers, so the ordinary
          // dispatcher would report an existing path as missing for OPTIONS.
          // Answer that request from the combined method set, while an
          // explicit ordinary OPTIONS route still takes precedence below.
          // Other methods keep falling through to the ordinary router, which
          // is also where their fallback and 404 handling lives.
          let async_methods = self.async_allowed_methods(clean_path)
          if meth == "OPTIONS" &&
            !async_methods.is_empty() &&
            self.router.find_node_raw(meth, clean_path) is None {
            let allowed = self.allowed_methods_with_async(
              clean_path, async_methods,
            )
            self.run_mounted_method_response(
              ctx, clean_path, allowed.join(", "),
            )
            return
          }
          let synthesized = fn(ctx, allow) raise {
            self.run_mounted_method_response(ctx, clean_path, allow)
          }
          router.dispatch_with_synthesized(
            ctx, self.no_route_handler, Some(synthesized),
          )
        }
      }
      let chain = apply_middleware(self.middlewares, terminal)
      self.chain = Some(chain)
      chain
    }
  }
  errdefer ctx.run_cleanups()
  chain(ctx)
  ctx.run_cleanups()
}

///|
/// Drop the buffered body of a `HEAD` response while keeping its framing: a
/// non-empty body leaves its byte length in `Content-Length`, an empty body
/// advertises a zero length like the matching `GET`, and a status that forbids
/// a body drops any seeded length. `App::respond` and `App::respond_async` call
/// this so offline replies match the wire format produced by `send_response`.
fn strip_head_body(response : Response) -> Unit {
  let body_allowed = response.status >= 200 &&
    response.status != 204 &&
    response.status != 205 &&
    response.status != 304
  let body_length = match response.data {
    Some(data) => if data.length() > 0 { Some(data.length()) } else { None }
    None => if response.body.is_empty() {
      None
    } else {
      Some(utf8_byte_length_lossy(response.body.view()))
    }
  }
  if body_allowed {
    match body_length {
      Some(length) =>
        set_header_ignore_case(
          response.headers,
          "Content-Length",
          length.to_string(),
        )
      None =>
        set_header_ignore_case(response.headers, "Content-Length", "0")
    }
  } else if response.status == 205 {
    // `205 Reset Content` must advertise a zero-length body, matching the
    // server framing for both GET and HEAD.
    set_header_ignore_case(response.headers, "Content-Length", "0")
  } else {
    ignore(remove_header_ignore_case(response.headers, "Content-Length"))
  }
  response.body = ""
  response.data = None
}

///|
/// Whether an HTTP status allows a message body. `1xx`, `204`, `205` and `304`
/// responses must not carry one.
fn status_allows_body(status : Int32) -> Bool {
  status >= 200 && status != 204 && status != 205 && status != 304
}

///|
/// Drop any prepared body from a response whose status forbids one, keeping the
/// headers a handler or middleware set so the offline facade matches what the
/// server would put on the wire.
fn strip_forbidden_body(response : Response) -> Unit {
  if !status_allows_body(response.status) {
    response.body = ""
    response.data = None
    ignore(remove_header_ignore_case(response.headers, "Content-Length"))
    ignore(remove_header_ignore_case(response.headers, "Content-Type"))
    ignore(remove_header_ignore_case(response.headers, "Content-Range"))
    // A 304 keeps its validators and coding: they describe the selected
    // representation. `1xx`, `204` and `205` have no representation at all.
    if response.status != 304 {
      clear_replaced_representation_headers(response.headers)
      ignore(remove_header_ignore_case(response.headers, "Content-Encoding"))
      if response.status == 205 {
        // The server frames `205 Reset Content` as an empty body with an
        // explicit zero length; the offline facade should report the same.
        set_header_ignore_case(response.headers, "Content-Length", "0")
      }
    } else {
      ignore(remove_header_ignore_case(response.headers, "Content-Disposition"))
    }
  }
}

///|
/// Drop hop-by-hop framing headers that belong to a single connection rather
/// than to the response representation. The server filters the same fields
/// before handing headers to the HTTP runtime, so the offline facade must not
/// expose them either.
fn strip_offline_framing_headers(response : Response) -> Unit {
  ignore(remove_header_ignore_case(response.headers, "Transfer-Encoding"))
  ignore(remove_header_ignore_case(response.headers, "Connection"))
}

///|
/// Run a request through the application without a server and return the
/// response.
///
/// This is the offline counterpart of the server: the middleware chain, the
/// routing and the error handling are the same, but the response is not
/// compressed, because compressing needs the asynchronous gzip encoder. Use
/// `App::respond_async` to see the response the server would send, gzip
/// included.
pub fn App::respond(self : App, request : Request) -> Response {
  let ctx = self.context_for_request(request)
  self.handle(ctx) catch {
    HttpError(status, message) => error_response(ctx, status, message)
    HttpErrorPayload(status, message, payload) =>
      error_response_with_payload(ctx, status, message, payload)
    HttpProblem(status, type_name, title, detail, instance) =>
      problem_response(ctx, status, type_name, title, detail, instance)
    err => internal_error(ctx, "\{err}")
  }
  if ctx.file_response() is None {
    // Without request headers there can be no precondition.
    if ctx.request.headers.is_empty() {
      ignore(negotiate_existing_encoding(None, ctx.response))
      if response_etag_enabled(self, ctx) {
        apply_etag(ctx.response)
      }
    } else {
      let (input, allows_not_modified) = precondition_input_facade(ctx.request)
      let (failed, remaining) = precheck_preconditions(
        input,
        allows_not_modified,
        ctx.response,
      )
      if !failed {
        let accept_encoding = get_header_ignore_case(
          ctx.request.headers,
          "Accept-Encoding",
        )
        if !negotiate_existing_encoding(accept_encoding, ctx.response) {
          let (compress, _) = compression_settings(self, ctx)
          // This facade cannot encode a body; when the application would not
          // compress either, an explicit identity refusal leaves no acceptable
          // representation. Leave the documented inability to compress alone
          // when the application has compression enabled.
          if !compress {
            reject_unacceptable_identity(accept_encoding, ctx.response)
          }
        }
        finish_response(
          self, ctx, ctx.response, remaining, allows_not_modified,
        )
      }
    }
    // A 304 has no body to encode, but when compression is enabled the
    // selected representation still depends on `Accept-Encoding`; the async
    // facade and the server add this in `compress_response`. Mirror it here so
    // a cached revalidation from either facade carries the same key.
    if ctx.response.status == 304 {
      let (compress, _) = compression_settings(self, ctx)
      if compress {
        add_vary_accept_encoding(ctx.response)
      }
    }
    apply_buffered_range(ctx.request, ctx.response, false)
  }
  strip_forbidden_body(ctx.response)
  if ctx.request.method.view().equal_ignore_ascii_case("HEAD".view()) &&
    ctx.file_response() is None {
    strip_head_body(ctx.response)
  }
  strip_offline_framing_headers(ctx.response)
  ctx.response
}

///|
/// Run a request through the application without a server and return the
/// response, compressing it when the application compresses responses and the
/// request accepts gzip.
///
/// This is the offline counterpart of the server: the middleware chain, the
/// routing, the error handling, the compression and the cache validators are
/// the same, so the response matches the one the server sends.
pub async fn App::respond_async(
  self : App,
  request : Request,
) -> Response {
  let ctx = self.context_for_request(request)
  self.handle(ctx) catch {
    HttpError(status, message) => error_response(ctx, status, message)
    HttpErrorPayload(status, message, payload) =>
      error_response_with_payload(ctx, status, message, payload)
    HttpProblem(status, type_name, title, detail, instance) =>
      problem_response(ctx, status, type_name, title, detail, instance)
    err => internal_error(ctx, "\{err}")
  }
  if ctx.file_response() is None {
    // Without request headers there can be no precondition.
    if ctx.request.headers.is_empty() {
      if !negotiate_existing_encoding(None, ctx.response) {
        let (compress, min_size) = compression_settings(self, ctx)
        if compress {
          compress_response(None, ctx.response, min_size)
        } else {
          reject_unacceptable_identity(None, ctx.response)
        }
      }
      if response_etag_enabled(self, ctx) {
        apply_etag(ctx.response)
      }
    } else {
      let (input, allows_not_modified) = precondition_input_facade(ctx.request)
      let (failed, remaining) = precheck_preconditions(
        input,
        allows_not_modified,
        ctx.response,
      )
      if !failed {
        let accept_encoding = get_header_ignore_case(
          ctx.request.headers,
          "Accept-Encoding",
        )
        if !negotiate_existing_encoding(accept_encoding, ctx.response) {
          let (compress, min_size) = compression_settings(self, ctx)
          if compress {
            compress_response(accept_encoding, ctx.response, min_size)
          } else {
            reject_unacceptable_identity(accept_encoding, ctx.response)
          }
        }
        finish_response(
          self, ctx, ctx.response, remaining, allows_not_modified,
        )
      }
    }
    apply_buffered_range(ctx.request, ctx.response, false)
  }
  strip_forbidden_body(ctx.response)
  if ctx.request.method.view().equal_ignore_ascii_case("HEAD".view()) &&
    ctx.file_response() is None {
    strip_head_body(ctx.response)
  }
  strip_offline_framing_headers(ctx.response)
  ctx.response
}

