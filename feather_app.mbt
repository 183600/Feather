///|
pub struct App {
  router : Router
  middlewares : Array[Middleware]
  state : Map[String, String]
  json_state : Map[String, Json]
  mut max_body_size : Int32
  mut timeout : Int32
  mut chain : Handler?
  mut static_chain : Handler?
  mut async_chain : Handler?
  static_mounts : Array[StaticMount]
  mount_middlewares : Array[(String, Array[Middleware])]
  mut no_route_handler : Handler?
  ws_router : Router
  ws_handlers : Map[String, WebSocketHandler]
  ws_middlewares : Map[String, Handler]
  sse_router : Router
  sse_handlers : Map[String, SseHandler]
  sse_middlewares : Map[String, Handler]
  stream_router : Router
  stream_handlers : Map[String, StreamHandler]
  stream_middlewares : Map[String, Handler]
  mut compress_enabled : Bool
  mut compress_min_size : Int32
  mut etag_enabled : Bool
  mut trust_proxy_hops : Int32
  static_lookup_cache : Map[String, (String, String, Bool, StaticMount)?]
  static_lookup_negative : Array[String]
  mut static_lookup_negative_head : Int32
  in_flight : Ref[Int32]
  mut draining : Bool
}

///|
/// Build an application with every optional feature disabled. `timeout` is the
/// per-request timeout in milliseconds; `0` disables it.
fn App::fresh(timeout : Int32) -> App {
  {
    router: create_router(),
    middlewares: [],
    state: Map([]),
    json_state: Map([]),
    max_body_size: DEFAULT_MAX_BODY_SIZE,
    timeout,
    chain: None,
    static_chain: None,
    async_chain: None,
    static_mounts: [],
    mount_middlewares: [],
    no_route_handler: None,
    ws_router: create_router(),
    ws_handlers: Map([]),
    ws_middlewares: Map([]),
    sse_router: create_router(),
    sse_handlers: Map([]),
    sse_middlewares: Map([]),
    stream_router: create_router(),
    stream_handlers: Map([]),
    stream_middlewares: Map([]),
    compress_enabled: false,
    compress_min_size: 1024,
    etag_enabled: false,
    trust_proxy_hops: 0,
    static_lookup_cache: Map([]),
    static_lookup_negative: [],
    static_lookup_negative_head: 0,
    in_flight: Ref(0),
    draining: false,
  }
}

///|
pub fn App::new() -> App {
  App::fresh(0)
}

///|
/// Set an application-scoped string value.
///
/// Application state is copied into every request context before middleware
/// runs, so handlers and middleware can read shared configuration through the
/// same `Context::get` / `Context::set` API they use for request-local state.
/// Request-local writes never modify the application copy.
pub fn App::set_state(self : App, key : String, value : String) -> App {
  self.state.set(key, value)
  self
}

///|
/// Read an application-scoped string value, or `""` when it is absent.
pub fn App::get_state(self : App, key : String) -> String {
  match self.state.get(key) {
    Some(value) => value
    None => ""
  }
}

///|
/// Remove an application-scoped string value.
pub fn App::remove_state(self : App, key : String) -> App {
  ignore(self.state.remove(key))
  self
}

///|
/// Set an application-scoped JSON value.
pub fn App::set_json_state(self : App, key : String, value : Json) -> App {
  self.json_state.set(key, value)
  self
}

///|
/// Read an application-scoped JSON value.
pub fn App::get_json_state(self : App, key : String) -> Json? {
  self.json_state.get(key)
}

///|
/// Remove an application-scoped JSON value.
pub fn App::remove_json_state(self : App, key : String) -> App {
  ignore(self.json_state.remove(key))
  self
}

///|
/// Copy application state into `ctx` without overwriting values that were
/// already set on the request.
fn App::merge_state(self : App, ctx : Context) -> Unit {
  if self.state.is_empty() && self.json_state.is_empty() {
    return
  }
  for key, value in self.state {
    if !ctx.state.contains(key) {
      ctx.state.set(key, value)
    }
  }
  for key, value in self.json_state {
    if !ctx.json_state.contains(key) {
      ctx.json_state.set(key, value)
    }
  }
}

///|
/// Build the context for an incoming request and seed it with application
/// state.
fn App::context_for_request(self : App, request : Request) -> Context {
  let ctx = Context::new(request)
  if self.trust_proxy_hops != 0 {
    ctx.state.set(TRUST_PROXY_HOPS_KEY, self.trust_proxy_hops.to_string())
  }
  self.merge_state(ctx)
  ctx
}

///|
pub fn App::use(self : App, middleware : Middleware) -> App {
  self.middlewares.push(middleware)
  self.chain = None
  self.static_chain = None
  self.async_chain = None
  for mount in self.static_mounts {
    mount.chain = None
  }
  self
}

///|
/// Install middleware that runs only when `predicate` accepts the request.
///
/// The predicate runs after the application's earlier middleware and before
/// the scoped middleware, so it can inspect request state those middleware
/// established. When it returns `false`, the scoped middleware is skipped and
/// the request continues down the chain unchanged. The middleware is composed
/// once per chain, not once per request, and installing it invalidates the
/// cached chain exactly like `App::use`.
pub fn App::use_when(
  self : App,
  predicate : (Context) -> Bool,
  middleware : Middleware,
) -> App {
  self.use(fn(next) {
    let scoped = middleware(next)
    fn(ctx) raise {
      if predicate(ctx) {
        scoped(ctx)
      } else {
        next(ctx)
      }
    }
  })
}

///|
/// Install middleware for `prefix` and everything below it.
///
/// Matching is segment-aware and case-sensitive: `/api` covers `/api`,
/// `/api/` and `/api/users`, but not `/apiary`. The query string is ignored.
/// An empty prefix or `"/"` installs the middleware application-wide. Prefixes
/// are normalized like route groups (`api//v1/` becomes `/api/v1`), and the
/// scoped middleware runs in the position where this method was called
/// relative to `App::use`. This is the path-scoped counterpart of
/// `App::use`, useful for applying authentication, CORS or cache policy to
/// part of an application without creating a separate `RouteGroup`.
pub fn App::use_prefix(
  self : App,
  prefix : String,
  middleware : Middleware,
) -> App {
  let normalized = normalize_prefix(prefix)
  self.use_when(
    fn(ctx) {
      path_is_within_prefix(
        scoped_request_path(ctx),
        normalized.view(),
      )
    },
    middleware,
  )
}

///|
pub fn App::route(
  self : App,
  meth : String,
  path : String,
  handler : Handler,
) -> App {
  self.router.add_route(meth, path, handler)
  self
}

///|
/// Register a route wrapped in route-level middleware.
///
/// The middlewares run after every application middleware (`App::use`) and
/// only for requests that match `meth path`, which makes them the right place
/// for per-route authentication, rate limiting or header decoration. They are
/// composed left to right like `apply_middleware`, see `App::group` for
/// middleware shared by a whole prefix.
pub fn App::route_with(
  self : App,
  meth : String,
  path : String,
  middlewares : Array[Middleware],
  handler : Handler,
) -> App {
  self.router.add_route_with(meth, path, middlewares, handler)
  self
}

///|
///|
/// Set a timeout in milliseconds for one registered route, overriding
/// `App::request_timeout` for that route.
///
/// A positive value applies while the request is being read and while the
/// ordinary handler builds its response. `0` removes the override and restores
/// the application-wide timeout. Re-registering the route also resets it. The
/// call is a no-op when no route matches `meth path`, and asynchronous
/// endpoints keep their documented exemption from request timeouts.
pub fn App::route_timeout(
  self : App,
  meth : String,
  path : String,
  millis : Int32,
) -> App {
  ignore(self.router.set_route_timeout(meth, path, millis))
  self
}

///|
/// Set a request-body limit in bytes for one registered route, overriding
/// `App::max_body_size` for that route.
///
/// A positive value bounds the bytes read for the request body, including the
/// decoded size of a gzip-coded body. `0` removes the override and restores
/// the application-wide limit. Re-registering the route also resets it. The
/// call is a no-op when no route matches `meth path`.
pub fn App::route_body_limit(
  self : App,
  meth : String,
  path : String,
  limit : Int32,
) -> App {
  ignore(self.router.set_route_body_limit(meth, path, limit))
  self
}

///|
pub fn App::get(self : App, path : String, handler : Handler) -> App {
  self.route("GET", path, handler)
}

///|
pub fn App::post(self : App, path : String, handler : Handler) -> App {
  self.route("POST", path, handler)
}

///|
pub fn App::put(self : App, path : String, handler : Handler) -> App {
  self.route("PUT", path, handler)
}

///|
pub fn App::patch(self : App, path : String, handler : Handler) -> App {
  self.route("PATCH", path, handler)
}

///|
pub fn App::delete(self : App, path : String, handler : Handler) -> App {
  self.route("DELETE", path, handler)
}

///|
pub fn App::head(self : App, path : String, handler : Handler) -> App {
  self.route("HEAD", path, handler)
}

///|
pub fn App::options(self : App, path : String, handler : Handler) -> App {
  self.route("OPTIONS", path, handler)
}

///|
pub fn App::connect(self : App, path : String, handler : Handler) -> App {
  self.route("CONNECT", path, handler)
}

///|
pub fn App::trace(self : App, path : String, handler : Handler) -> App {
  self.route("TRACE", path, handler)
}

///|
pub fn App::all(self : App, path : String, handler : Handler) -> App {
  for meth in standard_methods() {
    ignore(self.route(meth, path, handler))
  }
  self
}

///|
pub fn App::fallback(self : App, handler : Handler) -> App {
  self.no_route_handler = Some(handler)
  self.chain = None
  self
}

///|
pub fn App::group(self : App, prefix : String) -> RouteGroup {
  {
    router: self.router,
    prefix: normalize_prefix(prefix),
    middlewares: [],
    app: Some(self),
    timeout: 0,
    body_limit: 0,
  }
}

///|
pub fn App::websocket(
  self : App,
  path : String,
  handler : WebSocketHandler,
) -> App {
  self.websocket_with(path, [], handler)
}

///|
/// Register a websocket handler wrapped in route-level middleware.
///
/// The middlewares run after `App::use` middleware and only for the matching
/// path. Middleware that does not call through answers the request instead of
/// starting the upgrade, and that response carries its headers and cookies.
/// The `101` handshake itself is written by `moonbitlang/async`, so headers or
/// cookies set by middleware that does call through cannot be added to it.
pub fn App::websocket_with(
  self : App,
  path : String,
  middlewares : Array[Middleware],
  handler : WebSocketHandler,
) -> App {
  let clean_path = clean_route_path(path)
  self.ws_router.add_route("GET", clean_path, fn(_ctx) { () })
  self.ws_handlers.set(clean_path, handler)
  self.ws_middlewares.set(
    clean_path,
    apply_middleware(middlewares, async_chain_terminal),
  )
  self
}

///|
pub fn App::has_websocket(self : App, path : String) -> Bool {
  if self.ws_handlers.is_empty() {
    return false
  }
  self.ws_router.is_routable("GET", path)
}

///|
/// Register a server-sent events handler for `GET path`.
///
/// The handler receives a `Sse` writer after the `200 OK` header
/// (`Content-Type: text/event-stream`) has been sent and keeps the response
/// open until it returns or calls `Sse::close`. Event streams are long-lived,
/// so they are not subject to `App::request_timeout`. Application middleware
/// registered with `App::use` runs before the event stream starts, so it can
/// reject the request or add response headers/cookies; headers it sets are
/// carried into the stream and a middleware that answers without calling
/// through replaces the stream entirely. Path parameters are available through
/// `Context::param`.
pub fn App::sse(self : App, path : String, handler : SseHandler) -> App {
  self.sse_with(path, [], handler)
}

///|
/// Register a server-sent events handler wrapped in route-level middleware.
///
/// Like `App::sse`, but the given middlewares run first (after `App::use`
/// middleware) for this path only. Middleware that calls through may add
/// headers to the event-stream response; middleware that answers replaces the
/// stream entirely.
pub fn App::sse_with(
  self : App,
  path : String,
  middlewares : Array[Middleware],
  handler : SseHandler,
) -> App {
  let clean_path = clean_route_path(path)
  self.sse_router.add_route("GET", clean_path, fn(_ctx) { () })
  self.sse_handlers.set(clean_path, handler)
  self.sse_middlewares.set(
    clean_path,
    apply_middleware(middlewares, async_chain_terminal),
  )
  self
}

///|
pub fn App::has_sse(self : App, path : String) -> Bool {
  if self.sse_handlers.is_empty() {
    return false
  }
  self.sse_router.is_routable("GET", path)
}

///|
pub fn App::resolve_sse(
  self : App,
  path : String,
) -> (SseHandler, Map[String, String])? {
  match self.resolve_sse_full(path) {
    Some((handler, params, _, _)) => Some((handler, params))
    None => None
  }
}

///|
fn App::resolve_sse_full(
  self : App,
  path : String,
) -> (SseHandler, Map[String, String], Handler, String)? {
  if self.sse_handlers.is_empty() {
    return None
  }
  match self.sse_router.match_dispatch("GET", clean_path_view(path)) {
    DispatchFound(node, params, _) =>
      match self.sse_handlers.get(node.route_path) {
        Some(handler) =>
          Some(
            (
              handler,
              match params {
                Some(params) => params.copy()
                None => Map([], capacity=0)
              },
              match self.sse_middlewares.get(node.route_path) {
                Some(chain) => chain
                None => async_chain_terminal
              },
              node.route_path,
            ),
          )
        None => None
      }
    _ => None
  }
}

///|
pub fn App::resolve_websocket(
  self : App,
  path : String,
) -> (WebSocketHandler, Map[String, String])? {
  match self.resolve_websocket_full(path) {
    Some((handler, params, _, _)) => Some((handler, params))
    None => None
  }
}

///|
fn App::resolve_websocket_full(
  self : App,
  path : String,
) -> (WebSocketHandler, Map[String, String], Handler, String)? {
  if self.ws_handlers.is_empty() {
    return None
  }
  match self.ws_router.match_dispatch("GET", clean_path_view(path)) {
    DispatchFound(node, params, _) =>
      match self.ws_handlers.get(node.route_path) {
        Some(handler) =>
          Some(
            (
              handler,
              match params {
                Some(params) => params.copy()
                None => Map([], capacity=0)
              },
              match self.ws_middlewares.get(node.route_path) {
                Some(chain) => chain
                None => async_chain_terminal
              },
              node.route_path,
            ),
          )
        None => None
      }
    _ => None
  }
}

///|
/// Register a chunked streaming handler for `GET path`.
///
/// The handler runs while the response is being written and receives a
/// `Stream` it can push chunks into with `Stream::write` /
/// `Stream::write_bytes` / `Stream::write_json`. Unlike `App::get` handlers,
/// nothing is buffered up front: the header is sent on the first write, so
/// responses are delivered incrementally. Server-sent events remain the better
/// fit for one-way event feeds (`App::sse`); streaming is the general escape
/// hatch, for example for generated downloads or proxying.
///
/// Streams are long-lived, so they are not subject to `App::request_timeout`.
/// Application middleware registered with `App::use` runs before the first
/// chunk is written, so it can reject the request, choose the response status
/// or add headers/cookies; a middleware that answers without calling through
/// replaces the stream entirely. Path parameters are available through
/// `Context::param`.
pub fn App::stream(self : App, path : String, handler : StreamHandler) -> App {
  self.stream_with(path, [], handler)
}

///|
/// Register a chunked streaming handler wrapped in route-level middleware.
///
/// Like `App::stream`, but the given middlewares run first (after `App::use`
/// middleware) for this path only. Middleware that calls through may choose
/// the status or add headers before the first chunk is written; middleware
/// that answers replaces the stream entirely.
pub fn App::stream_with(
  self : App,
  path : String,
  middlewares : Array[Middleware],
  handler : StreamHandler,
) -> App {
  let clean_path = clean_route_path(path)
  self.stream_router.add_route("GET", clean_path, fn(_ctx) { () })
  self.stream_handlers.set(clean_path, handler)
  self.stream_middlewares.set(
    clean_path,
    apply_middleware(middlewares, async_chain_terminal),
  )
  self
}

///|
pub fn App::has_stream(self : App, path : String) -> Bool {
  if self.stream_handlers.is_empty() {
    return false
  }
  self.stream_router.is_routable("GET", path)
}

///|
pub fn App::resolve_stream(
  self : App,
  path : String,
) -> (StreamHandler, Map[String, String])? {
  match self.resolve_stream_full(path) {
    Some((handler, params, _, _)) => Some((handler, params))
    None => None
  }
}

///|
fn App::resolve_stream_full(
  self : App,
  path : String,
) -> (StreamHandler, Map[String, String], Handler, String)? {
  if self.stream_handlers.is_empty() {
    return None
  }
  match self.stream_router.match_dispatch("GET", clean_path_view(path)) {
    DispatchFound(node, params, _) =>
      match self.stream_handlers.get(node.route_path) {
        Some(handler) =>
          Some(
            (
              handler,
              match params {
                Some(params) => params.copy()
                None => Map([], capacity=0)
              },
              match self.stream_middlewares.get(node.route_path) {
                Some(chain) => chain
                None => async_chain_terminal
              },
              node.route_path,
            ),
          )
        None => None
      }
    _ => None
  }
}

///|
pub fn App::route_named(
  self : App,
  name : String,
  meth : String,
  path : String,
  handler : Handler,
) -> App {
  self.router.add_named_route(name, meth, path, handler)
  self
}

///|
/// Register a named route wrapped in route-level middleware. The route can be
/// generated with `App::url_for` like any other named route.
pub fn App::route_named_with(
  self : App,
  name : String,
  meth : String,
  path : String,
  middlewares : Array[Middleware],
  handler : Handler,
) -> App {
  self.router.add_named_route_with(name, meth, path, middlewares, handler)
  self
}

///|
pub fn App::url_for(
  self : App,
  name : String,
  params? : Map[String, String],
  query? : Map[String, String],
) -> String? {
  self.router.url_for(name, params?, query?)
}

///|
fn join_fs_path(root : String, relative : String) -> String {
  if relative == "" {
    return root
  }
  if root == "" {
    return relative
  }
  if root.has_suffix("/") {
    return root + relative
  }
  let builder = StringBuilder(size_hint=root.length() + 1 + relative.length())
  builder.write_string(root)
  builder.write_char('/')
  builder.write_string(relative)
  builder.to_string()
}

///|
/// Normalize a decoded relative path, returning it unchanged when it is already
/// clean.
fn clean_relative_path(relative : String) -> String? {
  let view = relative.view()
  if view.contains("\u{0}") || view.contains("\\") {
    return None
  }
  let length = view.length()
  // Control characters are not valid in a URL path and must never be turned
  // into filesystem names (or echoed into a redirect/Location header).
  let mut control_scan = 0
  while control_scan < length {
    let code = view.unsafe_get(control_scan).to_int()
    if code < 0x20 || code == 0x7F {
      return None
    }
    control_scan = control_scan + 1
  }
  let mut needs_clean = false
  let mut i = 0
  let mut at_start = true
  while i < length {
    if view.unsafe_get(i).to_int() == 47 {
      if at_start || i + 1 == length || view.unsafe_get(i - 1).to_int() == 47 {
        needs_clean = true
      }
      i = i + 1
    } else {
      at_start = false
      let end = segment_end(view, i)
      let segment = view[i:end]
      if segment == "." {
        needs_clean = true
      } else if segment == ".." {
        return None
      }
      i = end
    }
  }
  if !needs_clean {
    return Some(relative)
  }
  let segments : Array[StringView] = []
  for segment in view.split("/") {
    if segment.is_empty() || segment == "." {
      continue
    }
    if segment == ".." {
      return None
    }
    segments.push(segment)
  }
  let builder = StringBuilder(size_hint=relative.length())
  for i = 0; i < segments.length(); i = i + 1 {
    if i > 0 {
      builder.write_string("/")
    }
    builder.write_stringview(segments[i])
  }
  Some(builder.to_string())
}

