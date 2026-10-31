///|
/// Request state key holding the path prefix under which the current
/// application is mounted. It is set while a mounted child's middleware runs,
/// so `App::use_prefix` on that child can match paths relative to the child
/// rather than to the parent.
const MOUNT_BASE_KEY : String = "__feather_mount_base"

///|
/// The request path relative to the current application's mount point.
///
/// Unmounted applications see the whole path. A mounted child sees its own
/// subtree, which keeps a child's `use_prefix` scope stable regardless of
/// where the parent mounted it. An exact match for the mount point yields an
/// empty path (not `/`), which no non-root prefix matches.
fn scoped_request_path(ctx : Context) -> StringView {
  let path = clean_path_view(ctx.request.path)
  match ctx.state.get(MOUNT_BASE_KEY) {
    Some(base) =>
      if base == "" {
        path
      } else {
        // Mount prefixes are route patterns, so resolve them with the same
        // segment matcher the router uses. That keeps `:param` and a trailing
        // `*wildcard` mount usable: the child-relative path starts where the
        // matched prefix ends (or where the wildcard remainder begins), rather
        // than at the literal pattern spelling.
        match match_mount_prefix(path, base.view()) {
          Some(matched) => path[matched.relative_start:]
          None => path
        }
      }
    None => path
  }
}

///|
fn join_paths(prefix : String, path : String) -> String {
  let base = normalize_prefix(prefix)
  if path == "" || path == "/" {
    return if base == "" { "/" } else { base }
  }
  let suffix = if path.has_prefix("/") { path } else { "/" + path }
  base + suffix
}

///|
pub struct RouteGroup {
  router : Router
  prefix : String
  middlewares : Array[Middleware]
  app : App?
  mut timeout : Int32
  mut body_limit : Int32
}

///|
pub fn Router::group(self : Router, prefix : String) -> RouteGroup {
  {
    router: self,
    prefix: normalize_prefix(prefix),
    middlewares: [],
    app: None,
    timeout: 0,
    body_limit: 0,
  }
}

///|
pub fn RouteGroup::group(self : RouteGroup, prefix : String) -> RouteGroup {
  {
    router: self.router,
    prefix: normalize_prefix(join_paths(self.prefix, prefix)),
    middlewares: self.middlewares.copy(),
    app: self.app,
    timeout: self.timeout,
    body_limit: self.body_limit,
  }
}

///|
/// Compose this group's middleware outside additional route-level middleware.
fn RouteGroup::route_middlewares(
  self : RouteGroup,
  extra : Array[Middleware],
) -> Array[Middleware] {
  if self.middlewares.length() == 0 {
    return extra.copy()
  }
  if extra.length() == 0 {
    return self.middlewares.copy()
  }
  let combined : Array[Middleware] = Array(
    capacity=self.middlewares.length() + extra.length(),
  )
  combined.append(self.middlewares)
  combined.append(extra)
  combined
}

///|
pub fn RouteGroup::use(
  self : RouteGroup,
  middleware : Middleware,
) -> RouteGroup {
  self.middlewares.push(middleware)
  self
}

///|
/// Set a default timeout for routes registered through this group afterwards.
///
/// A positive value applies to each ordinary route added after this call, as
/// if `RouteGroup::route_timeout` had been called for it, and nested groups
/// inherit the default. `0` removes the default; routes already registered are
/// unchanged. `RouteGroup::route_timeout` can still override an individual
/// route, including resetting it to the application-wide timeout with `0`.
pub fn RouteGroup::timeout(
  self : RouteGroup,
  millis : Int32,
) -> RouteGroup {
  self.timeout = if millis < 0 { 0 } else { millis }
  self
}

///|
/// Set a default request-body limit for routes registered through this group
/// afterwards.
///
/// A positive value applies to each ordinary route added after this call, as
/// if `RouteGroup::route_body_limit` had been called for it, and nested groups
/// inherit the default. `0` removes the default; routes already registered are
/// unchanged. `RouteGroup::route_body_limit` can still override an individual
/// route, including resetting it to the application-wide limit with `0`.
pub fn RouteGroup::body_limit(
  self : RouteGroup,
  limit : Int32,
) -> RouteGroup {
  self.body_limit = if limit < 0 { 0 } else { limit }
  self
}

///|
/// Apply this group's default timeout and body limit to a route that was just
/// registered under its joined path.
fn RouteGroup::apply_route_limits(
  self : RouteGroup,
  meth : String,
  path : String,
) -> Unit {
  if self.timeout > 0 {
    ignore(self.router.set_route_timeout(meth, path, self.timeout))
  }
  if self.body_limit > 0 {
    ignore(self.router.set_route_body_limit(meth, path, self.body_limit))
  }
}

///|
fn RouteGroup::wrap(self : RouteGroup, handler : Handler) -> Handler {
  if self.middlewares.length() == 0 {
    handler
  } else {
    apply_middleware(self.middlewares, handler)
  }
}

///|
pub fn RouteGroup::route(
  self : RouteGroup,
  meth : String,
  path : String,
  handler : Handler,
) -> RouteGroup {
  let path = join_paths(self.prefix, path)
  self.router.add_route(meth, path, self.wrap(handler))
  self.apply_route_limits(meth, path)
  self
}

///|
/// Register a group route with additional route-level middleware.
///
/// The group middlewares (`RouteGroup::use`) wrap the route middlewares, which
/// in turn wrap the handler, so the execution order is group, route, handler.
pub fn RouteGroup::route_with(
  self : RouteGroup,
  meth : String,
  path : String,
  middlewares : Array[Middleware],
  handler : Handler,
) -> RouteGroup {
  let path = join_paths(self.prefix, path)
  self.router.add_route(
    meth,
    path,
    self.wrap(apply_middleware(middlewares, handler)),
  )
  self.apply_route_limits(meth, path)
  self
}

///|
///|
/// Set a timeout for a route previously registered through this group. The
/// path is joined with the group prefix exactly like `RouteGroup::route`.
pub fn RouteGroup::route_timeout(
  self : RouteGroup,
  meth : String,
  path : String,
  millis : Int32,
) -> RouteGroup {
  ignore(
    self.router.set_route_timeout(meth, join_paths(self.prefix, path), millis),
  )
  self
}

///|
/// Set a request-body limit for a route previously registered through this
/// group. The path is joined with the group prefix exactly like
/// `RouteGroup::route`.
pub fn RouteGroup::route_body_limit(
  self : RouteGroup,
  meth : String,
  path : String,
  limit : Int32,
) -> RouteGroup {
  ignore(
    self.router.set_route_body_limit(meth, join_paths(self.prefix, path), limit),
  )
  self
}

///|
pub fn RouteGroup::route_named(
  self : RouteGroup,
  name : String,
  meth : String,
  path : String,
  handler : Handler,
) -> RouteGroup {
  let path = join_paths(self.prefix, path)
  self.router.add_named_route(
    name,
    meth,
    path,
    self.wrap(handler),
  )
  self.apply_route_limits(meth, path)
  self
}

///|
/// Register a named group route with additional route-level middleware. Group
/// middlewares stay outermost, mirroring `RouteGroup::route_with`.
pub fn RouteGroup::route_named_with(
  self : RouteGroup,
  name : String,
  meth : String,
  path : String,
  middlewares : Array[Middleware],
  handler : Handler,
) -> RouteGroup {
  let path = join_paths(self.prefix, path)
  self.router.add_named_route(
    name,
    meth,
    path,
    self.wrap(apply_middleware(middlewares, handler)),
  )
  self.apply_route_limits(meth, path)
  self
}

///|
pub fn RouteGroup::get(
  self : RouteGroup,
  path : String,
  handler : Handler,
) -> RouteGroup {
  self.route("GET", path, handler)
}

///|
pub fn RouteGroup::post(
  self : RouteGroup,
  path : String,
  handler : Handler,
) -> RouteGroup {
  self.route("POST", path, handler)
}

///|
pub fn RouteGroup::put(
  self : RouteGroup,
  path : String,
  handler : Handler,
) -> RouteGroup {
  self.route("PUT", path, handler)
}

///|
pub fn RouteGroup::patch(
  self : RouteGroup,
  path : String,
  handler : Handler,
) -> RouteGroup {
  self.route("PATCH", path, handler)
}

///|
pub fn RouteGroup::delete(
  self : RouteGroup,
  path : String,
  handler : Handler,
) -> RouteGroup {
  self.route("DELETE", path, handler)
}

///|
pub fn RouteGroup::head(
  self : RouteGroup,
  path : String,
  handler : Handler,
) -> RouteGroup {
  self.route("HEAD", path, handler)
}

///|
pub fn RouteGroup::options(
  self : RouteGroup,
  path : String,
  handler : Handler,
) -> RouteGroup {
  self.route("OPTIONS", path, handler)
}

///|
pub fn RouteGroup::connect(
  self : RouteGroup,
  path : String,
  handler : Handler,
) -> RouteGroup {
  self.route("CONNECT", path, handler)
}

///|
pub fn RouteGroup::trace(
  self : RouteGroup,
  path : String,
  handler : Handler,
) -> RouteGroup {
  self.route("TRACE", path, handler)
}

///|
pub fn RouteGroup::all(
  self : RouteGroup,
  path : String,
  handler : Handler,
) -> RouteGroup {
  for meth in standard_methods() {
    ignore(self.route(meth, path, handler))
  }
  self
}

///|
pub fn RouteGroup::url_for(
  self : RouteGroup,
  name : String,
  params? : Map[String, String],
  query? : Map[String, String],
) -> String? {
  self.router.url_for(name, params?, query?)
}

///|
/// Register a WebSocket endpoint under this group's prefix.
///
/// Group middleware runs before the upgrade is attempted, so it can reject a
/// connection by answering the handshake request. Groups created with
/// `Router::group` have no application to attach the endpoint to and ignore
/// this method; use `App::group` or `Feather::group` instead.
pub fn RouteGroup::websocket(
  self : RouteGroup,
  path : String,
  handler : WebSocketHandler,
) -> RouteGroup {
  self.websocket_with(path, [], handler)
}

///|
/// Register a prefixed WebSocket endpoint with additional route middleware.
/// Group middleware stays outermost, matching `RouteGroup::route_with`.
pub fn RouteGroup::websocket_with(
  self : RouteGroup,
  path : String,
  middlewares : Array[Middleware],
  handler : WebSocketHandler,
) -> RouteGroup {
  match self.app {
    Some(app) =>
      ignore(
        app.websocket_with(
          join_paths(self.prefix, path),
          self.route_middlewares(middlewares),
          handler,
        ),
      )
    None => ()
  }
  self
}

///|
/// Register a server-sent events endpoint under this group's prefix.
pub fn RouteGroup::sse(
  self : RouteGroup,
  path : String,
  handler : SseHandler,
) -> RouteGroup {
  self.sse_with(path, [], handler)
}

///|
/// Register a prefixed server-sent events endpoint with additional route
/// middleware. Group middleware stays outermost, matching
/// `RouteGroup::route_with`.
pub fn RouteGroup::sse_with(
  self : RouteGroup,
  path : String,
  middlewares : Array[Middleware],
  handler : SseHandler,
) -> RouteGroup {
  match self.app {
    Some(app) =>
      ignore(
        app.sse_with(
          join_paths(self.prefix, path),
          self.route_middlewares(middlewares),
          handler,
        ),
      )
    None => ()
  }
  self
}

///|
/// Register a chunked streaming endpoint under this group's prefix.
pub fn RouteGroup::stream(
  self : RouteGroup,
  path : String,
  handler : StreamHandler,
) -> RouteGroup {
  self.stream_with(path, [], handler)
}

///|
/// Register a prefixed streaming endpoint with additional route middleware.
/// Group middleware stays outermost, matching `RouteGroup::route_with`.
pub fn RouteGroup::stream_with(
  self : RouteGroup,
  path : String,
  middlewares : Array[Middleware],
  handler : StreamHandler,
) -> RouteGroup {
  match self.app {
    Some(app) =>
      ignore(
        app.stream_with(
          join_paths(self.prefix, path),
          self.route_middlewares(middlewares),
          handler,
        ),
      )
    None => ()
  }
  self
}

///|
/// Serve files under `url_prefix`, itself nested below the group prefix.
pub fn RouteGroup::static_files(
  self : RouteGroup,
  url_prefix : String,
  root : String,
  index~ : String = "index.html",
  max_age~ : Int32 = 0,
  precompressed~ : Bool = false,
  cache_control? : String,
) -> RouteGroup {
  self.static_files_with(
    url_prefix,
    root,
    [],
    index~,
    max_age~,
    precompressed~,
    cache_control?,
  )
}

///|
/// Serve files through a mount-specific middleware chain that runs inside this
/// group's middleware.
pub fn RouteGroup::static_files_with(
  self : RouteGroup,
  url_prefix : String,
  root : String,
  middlewares : Array[Middleware],
  index~ : String = "index.html",
  max_age~ : Int32 = 0,
  precompressed~ : Bool = false,
  cache_control? : String,
) -> RouteGroup {
  match self.app {
    Some(app) =>
      ignore(
        app.static_files_with(
          join_paths(self.prefix, url_prefix),
          root,
          self.route_middlewares(middlewares),
          index~,
          max_age~,
          precompressed~,
          cache_control?,
        ),
      )
    None => ()
  }
  self
}

///|
/// Mount another application below this group's prefix, with the group
/// middleware wrapping every route, static mount and asynchronous endpoint
/// contributed by the child.
pub fn RouteGroup::mount(
  self : RouteGroup,
  prefix : String,
  child : App,
) -> RouteGroup {
  self.mount_with(prefix, child, [])
}

///|
/// Mount another application below this group's prefix with additional
/// middleware that wraps everything contributed by the child.
///
/// The group middleware stays outermost, then the extra `middlewares`, then
/// the child application's own middleware, matching `RouteGroup::route_with`
/// and `App::mount_with`.
pub fn RouteGroup::mount_with(
  self : RouteGroup,
  prefix : String,
  child : App,
  middlewares : Array[Middleware],
) -> RouteGroup {
  match self.app {
    Some(app) =>
      ignore(
        app.mount_with(
          join_paths(self.prefix, prefix),
          child,
          self.route_middlewares(middlewares),
        ),
      )
    None => ()
  }
  self
}

///|
pub(all) struct StaticMount {
  url_prefix : String
  root : String
  index : String
  max_age : Int32
  cache_control : String
  precompressed : Bool
  middlewares : Array[Middleware]
  mut chain : Handler?
}

