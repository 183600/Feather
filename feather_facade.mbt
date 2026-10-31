///|
pub(all) struct Feather {
  config : Config
  app : App
}

///|
pub fn create_feather(config : Config) -> Feather {
  { config, app: App::fresh(config.timeout), }
}

///|
pub fn Feather::use(self : Feather, middleware : Middleware) -> Feather {
  ignore(self.app.use(middleware))
  self
}

///|
/// Install predicate-scoped middleware on the wrapped application. See
/// `App::use_when`.
pub fn Feather::use_when(
  self : Feather,
  predicate : (Context) -> Bool,
  middleware : Middleware,
) -> Feather {
  ignore(self.app.use_when(predicate, middleware))
  self
}

///|
/// Install prefix-scoped middleware on the wrapped application. See
/// `App::use_prefix`.
pub fn Feather::use_prefix(
  self : Feather,
  prefix : String,
  middleware : Middleware,
) -> Feather {
  ignore(self.app.use_prefix(prefix, middleware))
  self
}

///|
/// Set an application-scoped string value on the wrapped application.
pub fn Feather::set_state(
  self : Feather,
  key : String,
  value : String,
) -> Feather {
  ignore(self.app.set_state(key, value))
  self
}

///|
/// Read an application-scoped string value from the wrapped application.
pub fn Feather::get_state(self : Feather, key : String) -> String {
  self.app.get_state(key)
}

///|
/// Remove an application-scoped string value from the wrapped application.
pub fn Feather::remove_state(self : Feather, key : String) -> Feather {
  ignore(self.app.remove_state(key))
  self
}

///|
/// Set an application-scoped JSON value on the wrapped application.
pub fn Feather::set_json_state(
  self : Feather,
  key : String,
  value : Json,
) -> Feather {
  ignore(self.app.set_json_state(key, value))
  self
}

///|
/// Read an application-scoped JSON value from the wrapped application.
pub fn Feather::get_json_state(self : Feather, key : String) -> Json? {
  self.app.get_json_state(key)
}

///|
/// Remove an application-scoped JSON value from the wrapped application.
pub fn Feather::remove_json_state(self : Feather, key : String) -> Feather {
  ignore(self.app.remove_json_state(key))
  self
}

///|
pub fn Feather::route(
  self : Feather,
  meth : String,
  path : String,
  handler : Handler,
) -> Feather {
  ignore(self.app.route(meth, path, handler))
  self
}

///|
pub fn Feather::get(
  self : Feather,
  path : String,
  handler : Handler,
) -> Feather {
  self.route("GET", path, handler)
}

///|
pub fn Feather::post(
  self : Feather,
  path : String,
  handler : Handler,
) -> Feather {
  self.route("POST", path, handler)
}

///|
pub fn Feather::put(
  self : Feather,
  path : String,
  handler : Handler,
) -> Feather {
  self.route("PUT", path, handler)
}

///|
pub fn Feather::patch(
  self : Feather,
  path : String,
  handler : Handler,
) -> Feather {
  self.route("PATCH", path, handler)
}

///|
pub fn Feather::delete(
  self : Feather,
  path : String,
  handler : Handler,
) -> Feather {
  self.route("DELETE", path, handler)
}

///|
pub fn Feather::head(
  self : Feather,
  path : String,
  handler : Handler,
) -> Feather {
  self.route("HEAD", path, handler)
}

///|
pub fn Feather::options(
  self : Feather,
  path : String,
  handler : Handler,
) -> Feather {
  self.route("OPTIONS", path, handler)
}

///|
pub fn Feather::connect(
  self : Feather,
  path : String,
  handler : Handler,
) -> Feather {
  self.route("CONNECT", path, handler)
}

///|
pub fn Feather::trace(
  self : Feather,
  path : String,
  handler : Handler,
) -> Feather {
  self.route("TRACE", path, handler)
}

///|
pub fn Feather::all(
  self : Feather,
  path : String,
  handler : Handler,
) -> Feather {
  for meth in standard_methods() {
    ignore(self.route(meth, path, handler))
  }
  self
}

///|
pub fn Feather::fallback(self : Feather, handler : Handler) -> Feather {
  ignore(self.app.fallback(handler))
  self
}

///|
pub fn Feather::max_body_size(self : Feather, size : Int32) -> Feather {
  ignore(self.app.max_body_size(size))
  self
}

///|
pub fn Feather::request_timeout(self : Feather, millis : Int32) -> Feather {
  ignore(self.app.request_timeout(millis))
  self
}

///|
/// Set a timeout for one registered route on the wrapped application. See
/// `App::route_timeout`.
pub fn Feather::route_timeout(
  self : Feather,
  meth : String,
  path : String,
  millis : Int32,
) -> Feather {
  ignore(self.app.route_timeout(meth, path, millis))
  self
}

///|
/// Set a request-body limit for one registered route on the wrapped
/// application. See `App::route_body_limit`.
pub fn Feather::route_body_limit(
  self : Feather,
  meth : String,
  path : String,
  limit : Int32,
) -> Feather {
  ignore(self.app.route_body_limit(meth, path, limit))
  self
}

///|
/// Declare how many proxies in front of the application may be trusted when
/// the client address is derived from the forwarded headers. See
/// `App::trust_proxy` for the details.
pub fn Feather::trust_proxy(self : Feather, hops : Int32) -> Feather {
  ignore(self.app.trust_proxy(hops))
  self
}

///|
pub fn Feather::route_with(
  self : Feather,
  meth : String,
  path : String,
  middlewares : Array[Middleware],
  handler : Handler,
) -> Feather {
  ignore(self.app.route_with(meth, path, middlewares, handler))
  self
}

///|
pub fn Feather::websocket(
  self : Feather,
  path : String,
  handler : WebSocketHandler,
) -> Feather {
  ignore(self.app.websocket(path, handler))
  self
}

///|
pub fn Feather::websocket_with(
  self : Feather,
  path : String,
  middlewares : Array[Middleware],
  handler : WebSocketHandler,
) -> Feather {
  ignore(self.app.websocket_with(path, middlewares, handler))
  self
}

///|
pub fn Feather::mount(
  self : Feather,
  prefix : String,
  child : Feather,
) -> Feather {
  ignore(self.app.mount(prefix, child.app))
  self
}

///|
/// Mount another Feather application with additional outer middleware.
pub fn Feather::mount_with(
  self : Feather,
  prefix : String,
  child : Feather,
  middlewares : Array[Middleware],
) -> Feather {
  ignore(self.app.mount_with(prefix, child.app, middlewares))
  self
}

///|
pub fn Feather::sse(
  self : Feather,
  path : String,
  handler : SseHandler,
) -> Feather {
  ignore(self.app.sse(path, handler))
  self
}

///|
pub fn Feather::sse_with(
  self : Feather,
  path : String,
  middlewares : Array[Middleware],
  handler : SseHandler,
) -> Feather {
  ignore(self.app.sse_with(path, middlewares, handler))
  self
}

///|
pub fn Feather::stream(
  self : Feather,
  path : String,
  handler : StreamHandler,
) -> Feather {
  ignore(self.app.stream(path, handler))
  self
}

///|
pub fn Feather::stream_with(
  self : Feather,
  path : String,
  middlewares : Array[Middleware],
  handler : StreamHandler,
) -> Feather {
  ignore(self.app.stream_with(path, middlewares, handler))
  self
}

///|
pub fn Feather::group(self : Feather, prefix : String) -> RouteGroup {
  self.app.group(prefix)
}

///|
pub fn Feather::route_named(
  self : Feather,
  name : String,
  meth : String,
  path : String,
  handler : Handler,
) -> Feather {
  ignore(self.app.route_named(name, meth, path, handler))
  self
}

///|
pub fn Feather::route_named_with(
  self : Feather,
  name : String,
  meth : String,
  path : String,
  middlewares : Array[Middleware],
  handler : Handler,
) -> Feather {
  ignore(self.app.route_named_with(name, meth, path, middlewares, handler))
  self
}

///|
pub fn Feather::url_for(
  self : Feather,
  name : String,
  params? : Map[String, String],
  query? : Map[String, String],
) -> String? {
  self.app.url_for(name, params?, query?)
}

///|
pub fn Feather::static_files(
  self : Feather,
  url_prefix : String,
  root : String,
  index~ : String = "index.html",
  max_age~ : Int32 = 0,
  precompressed~ : Bool = false,
  cache_control? : String,
) -> Feather {
  ignore(
    self.app.static_files(
      url_prefix,
      root,
      index~,
      max_age~,
      precompressed~,
      cache_control?,
    ),
  )
  self
}

///|
pub fn Feather::static_files_with(
  self : Feather,
  url_prefix : String,
  root : String,
  middlewares : Array[Middleware],
  index~ : String = "index.html",
  max_age~ : Int32 = 0,
  precompressed~ : Bool = false,
  cache_control? : String,
) -> Feather {
  ignore(
    self.app.static_files_with(
      url_prefix,
      root,
      middlewares,
      index~,
      max_age~,
      precompressed~,
      cache_control?,
    ),
  )
  self
}

///|
pub fn Feather::handle(self : Feather, request : Request) -> Response {
  self.app.respond(request)
}

///|
/// Run a request through the application without a server and return the
/// response, compressing it when the application compresses responses and the
/// request accepts gzip. See `App::respond_async` for the details.
pub async fn Feather::handle_async(
  self : Feather,
  request : Request,
) -> Response {
  self.app.respond_async(request)
}

///|
/// Every HTTP route registered on the application as sorted `(method, path)`
/// pairs, including routes contributed by mounted applications.
pub fn Feather::routes(self : Feather) -> Array[(String, String)] {
  self.app.routes()
}

///|
/// Every endpoint on the wrapped application, including asynchronous handlers
/// and static mounts. See `App::endpoints`.
pub fn Feather::endpoints(self : Feather) -> Array[Endpoint] {
  self.app.endpoints()
}

///|
/// Whether an ordinary HTTP route matches `method` and `path`.
pub fn Feather::has_route(self : Feather, meth : String, path : String) -> Bool {
  self.app.has_route(meth, path)
}

///|
/// Whether a WebSocket endpoint is registered for `path`.
pub fn Feather::has_websocket(self : Feather, path : String) -> Bool {
  self.app.has_websocket(path)
}

///|
/// Whether a server-sent events endpoint is registered for `path`.
pub fn Feather::has_sse(self : Feather, path : String) -> Bool {
  self.app.has_sse(path)
}

///|
/// Whether a streaming endpoint is registered for `path`.
pub fn Feather::has_stream(self : Feather, path : String) -> Bool {
  self.app.has_stream(path)
}

///|
/// Resolve a request path through the static mounts, returning the file on
/// disk that would be served.
pub fn Feather::static_file_for(self : Feather, path : String) -> String? {
  self.app.static_file_for(path)
}

///|
/// The `Cache-Control` value configured for the static mount that serves
/// `path`, or `""` when no mount matches.
pub fn Feather::static_cache_control_for(
  self : Feather,
  path : String,
) -> String {
  self.app.static_cache_control_for(path)
}

///|
pub fn Feather::validate_body_size(self : Feather, body : String) -> Bool {
  utf8_byte_length_lossy(body.view()) <= self.app.max_body_size
}
