///|
/// Serve files from `root` under `url_prefix`.
///
/// When `precompressed` is enabled, a sibling `<file>.gz` is served instead of
/// the file itself to clients that accept the `gzip` coding. Responses carry
/// `Vary: Accept-Encoding` so shared caches keep the variants apart.
///
/// `cache_control` sets the exact `Cache-Control` field value and takes
/// precedence over the policy derived from `max_age`; an empty value suppresses
/// the header. An empty `index` disables directory indexes, so requests for a
/// directory fall through to the router instead of redirecting to it.
pub fn App::static_files(
  self : App,
  url_prefix : String,
  root : String,
  index~ : String = "index.html",
  max_age~ : Int32 = 0,
  precompressed~ : Bool = false,
  cache_control? : String,
) -> App {
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
/// Serve files from `root` under `url_prefix` through a mount-specific
/// middleware chain.
///
/// The middlewares run after every application middleware (`App::use`) and
/// only when a request resolves to a file below this mount, so they are the
/// natural place for static-asset authentication, access logging or
/// per-mount response headers. Registering another mount with a longer prefix
/// keeps both chains independent. A middleware that answers without calling
/// through replaces the file response entirely.
pub fn App::static_files_with(
  self : App,
  url_prefix : String,
  root : String,
  middlewares : Array[Middleware],
  index~ : String = "index.html",
  max_age~ : Int32 = 0,
  precompressed~ : Bool = false,
  cache_control? : String,
) -> App {
  let mut clean_root = root
  while clean_root.length() > 1 && clean_root.has_suffix("/") {
    clean_root = clean_root[:clean_root.length() - 1].to_owned()
  }
  let resolved_cache_control = match cache_control {
    Some(value) => value
    None =>
      if max_age > 0 {
        "public, max-age=" + max_age.to_string()
      } else {
        ""
      }
  }
  self.static_mounts.push({
    url_prefix: normalize_prefix(url_prefix),
    root: clean_root,
    index,
    max_age,
    cache_control: resolved_cache_control,
    precompressed,
    middlewares: middlewares.copy(),
    chain: None,
  })
  self.static_lookup_cache.clear()
  self.static_lookup_negative.clear()
  self.static_lookup_negative_head = 0
  invalidate_last_static_lookup()
  self
}

///|
/// Collect every registered route endpoint below `node` into
/// `(method, path, handler)` triples. Used by `App::mount`.
fn collect_route_nodes(
  node : RouteNode,
  method : String,
  out : Array[(String, String, Handler, String)],
) -> Unit {
  match node.handler {
    Some(handler) =>
      out.push((method, node.route_path, handler, node.route_name))
    None => ()
  }
  match node.static_children {
    Some(children) =>
      for _, child in children {
        collect_route_nodes(child, method, out)
      }
    None => ()
  }
  match node.param_child {
    Some(child) => collect_route_nodes(child, method, out)
    None => ()
  }
  match node.wildcard_child {
    Some(child) => collect_route_nodes(child, method, out)
    None => ()
  }
}

///|
/// Seed a mounted request with the child application's app-scoped state.
///
/// Parent state is already present on the context; mounted values only fill
/// missing keys so request-local overrides and the parent's defaults keep
/// their usual precedence.
fn mounted_state_middleware(child : App) -> Middleware {
  fn(next) {
    fn(ctx) raise {
      for key, value in child.state {
        if !ctx.state.contains(key) {
          ctx.state.set(key, value)
        }
      }
      for key, value in child.json_state {
        if !ctx.json_state.contains(key) {
          ctx.json_state.set(key, value)
        }
      }
      next(ctx)
    }
  }
}

///|
/// Record the path prefix under which a child application is mounted while its
/// middleware runs. Nested mounts combine their bases, so a child mounted at
/// `/v2` inside an application mounted at `/v1` sees `/v1/v2` and strips all of
/// it before a scoped middleware compares paths. The previous base is restored
/// on both normal return and error, so sibling routes never inherit a stale
/// mount point.
fn mount_base_middleware(local_base : String) -> Middleware {
  let base = normalize_prefix(local_base)
  fn(next) {
    fn(ctx) raise {
      if base == "" {
        next(ctx)
      } else {
        let previous = ctx.state.get(MOUNT_BASE_KEY)
        let combined = match previous {
          Some(parent) =>
            if parent == "" {
              base
            } else {
              join_paths(parent, base)
            }
          None => base
        }
        ctx.state.set(MOUNT_BASE_KEY, combined)
        defer {
          match previous {
            Some(value) => ctx.state.set(MOUNT_BASE_KEY, value)
            None => ignore(ctx.state.remove(MOUNT_BASE_KEY))
          }
        }
        next(ctx)
      }
    }
  }
}

///|
/// The middleware chain a mounted child contributes: first its app state, then
/// its mount point, then the child's own application middleware. This mirrors
/// serving the child directly, while the mount middleware stays outside both.
/// The mount point lets `App::use_prefix` inside the child keep matching
/// child-relative paths after the parent prefixes them.
fn mounted_child_middlewares(
  child : App,
  base : String,
) -> Array[Middleware] {
  let combined : Array[Middleware] = Array(
    capacity=child.middlewares.length() + 2,
  )
  combined.push(mounted_state_middleware(child))
  let mount_base = normalize_prefix(base)
  if mount_base != "" {
    combined.push(mount_base_middleware(mount_base))
  }
  combined.append(child.middlewares)
  combined
}

///|
/// Wrap an asynchronous route's pre-composed middleware chain with the outer
/// mount middleware and the middlewares of the application being mounted, once
/// at mount time. The outer middleware runs first, then the child
/// application's own middlewares, matching the order a directly registered
/// route would see.
fn mounted_route_chain(
  outer : Array[Middleware],
  child : Array[Middleware],
  route_chain : Handler,
) -> Handler {
  let wrapped = if child.length() == 0 {
    route_chain
  } else {
    apply_middleware(child, route_chain)
  }
  if outer.length() == 0 {
    wrapped
  } else {
    apply_middleware(outer, wrapped)
  }
}

///|
/// Combine the outer mount middleware, the middleware a child application
/// already attached to one of its static mounts, and the child's own
/// middleware. The outer middleware runs first, then the child's middleware,
/// then the mount-specific chain.
fn mounted_static_middlewares(
  outer : Array[Middleware],
  child : Array[Middleware],
  mount : Array[Middleware],
) -> Array[Middleware] {
  if outer.length() == 0 {
    if child.length() == 0 {
      return mount.copy()
    }
    if mount.length() == 0 {
      return child.copy()
    }
  } else if child.length() == 0 && mount.length() == 0 {
    return outer.copy()
  }
  let combined : Array[Middleware] = Array(
    capacity=outer.length() + child.length() + mount.length(),
  )
  combined.append(outer)
  combined.append(child)
  combined.append(mount)
  combined
}

///|
/// Mount another application under `prefix`, keeping its routes, middleware,
/// static mounts, named routes, websocket, server-sent events and streaming
/// handlers.
///
/// The mounted application's fallback, request timeout, body limit and
/// compression settings are not carried over; the parent application governs
/// those. Returns the parent so calls can be chained.
pub fn App::mount(self : App, prefix : String, child : App) -> App {
  self.mount_with(prefix, child, [])
}

///|
/// Mount another application under `prefix` with additional middleware that
/// wraps everything contributed by the child: ordinary routes, static mounts,
/// websocket upgrades, server-sent events and streaming handlers.
///
/// `middlewares` run before the child application's own middleware, so they
/// can authenticate or decorate the whole mounted application without
/// modifying the child. Returns the parent so calls can be chained.
pub fn App::mount_with(
  self : App,
  prefix : String,
  child : App,
  middlewares : Array[Middleware],
) -> App {
  let outer = middlewares.copy()
  let base = normalize_prefix(prefix)
  let child_middlewares = mounted_child_middlewares(child, base)
  let routes : Array[(String, String, Handler, String)] = []
  for method, root in child.router.trees {
    collect_route_nodes(root, method, routes)
  }
  for route in routes {
    let (method, path, handler, route_name) = route
    let wrapped = mounted_route_chain(outer, child_middlewares, handler)
    let mounted_path = join_paths(base, path)
    self.router.forget_route_names(method, mounted_path)
    let node = self.router.add_route_node(method, mounted_path, wrapped)
    node.route_name = route_name
  }
  for name, named in child.router.named {
    // Mounting a child whose name collides with a parent route makes the
    // child the name's target; clear the name from the parent node so
    // `Context::route_name` and `url_for` stay in agreement.
    self.router.detach_route_name(name)
    self.router.named.set(name, {
      method: named.method,
      path: join_paths(base, named.path),
    })
  }
  // Automatic `OPTIONS` / `405` responses do not run a matched route handler,
  // so remember the outer and child application middleware that must still
  // wrap them, exactly as they would when the child is served directly.
  let auto_middlewares : Array[Middleware] = Array(
    capacity=outer.length() + child_middlewares.length(),
  )
  auto_middlewares.append(outer)
  auto_middlewares.append(child_middlewares)
  self.mount_middlewares.push((base, auto_middlewares))
  // Nested mounts keep their own synthesized-response middleware. Rebase each
  // child entry onto this mount and put the parent/child layers in front so a
  // response resolved through the most specific nested mount still runs every
  // middleware a direct request to the child would run.
  for entry in child.mount_middlewares {
    let (child_prefix, child_chain) = entry
    let combined : Array[Middleware] = Array(
      capacity=auto_middlewares.length() + child_chain.length(),
    )
    combined.append(auto_middlewares)
    combined.append(child_chain)
    self.mount_middlewares.push((join_paths(base, child_prefix), combined))
  }
  for mount in child.static_mounts {
    self.static_mounts.push({
      url_prefix: if mount.url_prefix == "" {
        base
      } else {
        join_paths(base, mount.url_prefix)
      },
      root: mount.root,
      index: mount.index,
      max_age: mount.max_age,
      cache_control: mount.cache_control,
      precompressed: mount.precompressed,
      middlewares: mounted_static_middlewares(
        outer,
        child_middlewares,
        mount.middlewares,
      ),
      chain: None,
    })
  }
  self.static_lookup_cache.clear()
  self.static_lookup_negative.clear()
  self.static_lookup_negative_head = 0
  invalidate_last_static_lookup()
  for path, handler in child.ws_handlers {
    let mounted = join_paths(base, path)
    self.ws_router.add_route("GET", mounted, fn(_ctx) { () })
    self.ws_handlers.set(mounted, handler)
    self.ws_middlewares.set(
      mounted,
      mounted_route_chain(
        outer,
        child_middlewares,
        child.ws_middlewares.get(path).unwrap_or(async_chain_terminal),
      ),
    )
  }
  for path, handler in child.sse_handlers {
    let mounted = join_paths(base, path)
    self.sse_router.add_route("GET", mounted, fn(_ctx) { () })
    self.sse_handlers.set(mounted, handler)
    self.sse_middlewares.set(
      mounted,
      mounted_route_chain(
        outer,
        child_middlewares,
        child.sse_middlewares.get(path).unwrap_or(async_chain_terminal),
      ),
    )
  }
  for path, handler in child.stream_handlers {
    let mounted = join_paths(base, path)
    self.stream_router.add_route("GET", mounted, fn(_ctx) { () })
    self.stream_handlers.set(mounted, handler)
    self.stream_middlewares.set(
      mounted,
      mounted_route_chain(
        outer,
        child_middlewares,
        child.stream_middlewares.get(path).unwrap_or(async_chain_terminal),
      ),
    )
  }
  self.chain = None
  self.static_chain = None
  self
}

///|
fn Router::is_routable(self : Router, meth : String, path : String) -> Bool {
  match self.match_dispatch(normalize_method(meth), clean_path_view(path)) {
    DispatchFound(_, _, _) => true
    _ => false
  }
}

///|
pub fn App::has_route(self : App, meth : String, path : String) -> Bool {
  self.router.is_routable(meth, path)
}

///|
/// Every HTTP route registered on the application as sorted `(method, path)`
/// pairs, including routes contributed by mounted applications.
///
/// This covers ordinary handlers only. Use `App::endpoints` to include
/// WebSocket, server-sent events, streaming and static mounts as well.
pub fn App::routes(self : App) -> Array[(String, String)] {
  self.router.routes()
}

///|
/// The kind of endpoint reported by `App::endpoints`.
pub(all) enum EndpointKind {
  /// An ordinary handler registered with `get`/`post`/`route`/...
  EndpointRoute
  /// A WebSocket upgrade registered with `websocket`.
  EndpointWebSocket
  /// A server-sent events handler registered with `sse`.
  EndpointSse
  /// A chunked response handler registered with `stream`.
  EndpointStream
  /// A static file mount registered with `static_files`.
  EndpointStatic
}

///|
/// One registered endpoint, as reported by `App::endpoints`.
pub(all) struct Endpoint {
  method : String
  path : String
  kind : EndpointKind
}

///|
/// Ordering used to keep endpoints with the same method and path deterministic.
fn endpoint_kind_rank(kind : EndpointKind) -> Int {
  match kind {
    EndpointWebSocket => 0
    EndpointSse => 1
    EndpointStream => 2
    EndpointRoute => 3
    EndpointStatic => 4
  }
}

///|
/// Append the routes of one async router to `out`. These routers only accept
/// `GET`, so a mounted or registered path is reported under that method.
fn collect_async_endpoints(
  kind : EndpointKind,
  router : Router,
  out : Array[Endpoint],
) -> Unit {
  for pair in router.routes() {
    let (meth, path) = pair
    out.push({ method: meth, path, kind })
  }
}

///|
/// Every registered endpoint, sorted by method, path and kind.
///
/// Unlike `App::routes`, this includes WebSocket, server-sent events and
/// streaming handlers (all reported as `GET`) and static file mounts
/// (`EndpointStatic`, reported at their mount prefix), including those
/// contributed by `App::mount`. Useful for startup logging and generated API
/// documentation. When one method and path has several registrations, the
/// server's dispatch precedence is WebSocket, SSE, streaming, ordinary route,
/// then static mount; all registrations are still listed here.
pub fn App::endpoints(self : App) -> Array[Endpoint] {
  let out : Array[Endpoint] = []
  for pair in self.router.routes() {
    let (meth, path) = pair
    out.push({ method: meth, path, kind: EndpointRoute })
  }
  collect_async_endpoints(EndpointWebSocket, self.ws_router, out)
  collect_async_endpoints(EndpointSse, self.sse_router, out)
  collect_async_endpoints(EndpointStream, self.stream_router, out)
  for mount in self.static_mounts {
    out.push({
      method: "GET",
      path: if mount.url_prefix == "" { "/" } else { mount.url_prefix },
      kind: EndpointStatic,
    })
  }
  out.sort_by(fn(a, b) {
    let by_method = a.method.lexical_compare(b.method)
    if by_method != 0 {
      return by_method
    }
    let by_path = a.path.lexical_compare(b.path)
    if by_path != 0 {
      return by_path
    }
    endpoint_kind_rank(a.kind) - endpoint_kind_rank(b.kind)
  })
  out
}

///|
/// Result of matching a static mount prefix against a request path.
///
/// `consumed` measures the fixed part of the prefix: the path position just
/// after the matched segments, or, for a prefix ending in a wildcard, the
/// position where that wildcard starts. The captured remainder must not make a
/// wildcard mount look more specific than a mount with a longer fixed prefix,
/// so specificity comparisons use `consumed` rather than the full path length.
/// `relative_start` is where the path relative to the mount root begins. The
/// two differ for a wildcard prefix, where the captured remainder is itself
/// part of the child-relative path.
priv struct MountPrefixMatch {
  consumed : Int32
  relative_start : Int32
  params : Map[String, String]
}

///|
/// Match a static mount prefix, which uses the same segment syntax as a route
/// pattern (`:param` and a trailing `*wildcard`), against `path`.
///
/// Empty segments from repeated or leading slashes are ignored and static
/// segments are compared in their decoded spelling, so an encoded mount prefix
/// and an encoded request path resolve to the same mount. A wildcard prefix
/// captures the rest of the path; wildcards in the middle of a prefix cannot be
/// represented by the route registration model and are not matched.
fn match_mount_prefix(
  path : StringView,
  prefix : StringView,
) -> MountPrefixMatch? {
  let prefix_segments = split_segments(prefix)
  let length = path.length()
  let mut pos = 0
  let params : Map[String, String] = Map([], capacity=2)
  for index, segment in prefix_segments {
    if segment.has_prefix("*") {
      if index + 1 != prefix_segments.length() {
        return None
      }
      let start = skip_slashes(path, pos)
      let name = segment[1:].to_owned()
      if name != "" {
        params.set(name, join_wildcard(path, pos))
      }
      return Some({
        consumed: pos,
        relative_start: start,
        params,
      })
    }
    pos = skip_slashes(path, pos)
    if pos >= length {
      return None
    }
    let end = segment_end(path, pos)
    let text = path[pos:end]
    if segment.has_prefix(":") {
      let name = segment[1:].to_owned()
      if name != "" {
        params.set(name, text.to_owned())
      }
    } else if normalize_static_route_segment(text) !=
      normalize_static_route_segment(segment) {
      return None
    }
    pos = end
  }
  Some({
    consumed: pos,
    relative_start: skip_slashes(path, pos),
    params,
  })
}

///|
fn App::best_static_mount(
  self : App,
  path_view : StringView,
) -> (StaticMount, MountPrefixMatch)? {
  if self.static_mounts.length() == 0 {
    return None
  }
  let mut best : (StaticMount, MountPrefixMatch)? = None
  let mut best_consumed = -1
  let mut best_params = 2147483647
  let mut best_length = -1
  for mount in self.static_mounts {
    match match_mount_prefix(path_view, mount.url_prefix.view()) {
      Some(matched) => {
        let params = matched.params.length()
        let better = matched.consumed > best_consumed ||
          (
            matched.consumed == best_consumed &&
            (
              params < best_params ||
              (
                params == best_params &&
                mount.url_prefix.length() > best_length
              )
            )
          )
        if better {
          best = Some((mount, matched))
          best_consumed = matched.consumed
          best_params = params
          best_length = mount.url_prefix.length()
        }
      }
      None => ()
    }
  }
  best
}

///|
/// Maximum number of request paths kept by `App::static_lookup`.
const STATIC_LOOKUP_CACHE_LIMIT : Int32 = 256

///|
/// Consumed entries a negative FIFO may accumulate before it is compacted.
const STATIC_LOOKUP_COMPACT_THRESHOLD : Int32 = 64

///|
/// Drop the consumed prefix of `static_lookup_negative` so the FIFO cannot
/// grow without bound while negative entries keep being evicted and appended.
fn App::static_lookup_compact(self : App) -> Unit {
  let queued = self.static_lookup_negative
  let head = self.static_lookup_negative_head
  if head <= 0 {
    return
  }
  if head >= queued.length() {
    queued.clear()
    self.static_lookup_negative_head = 0
    return
  }
  let remaining : Array[String] = Array(capacity=queued.length() - head)
  let mut index = head
  while index < queued.length() {
    remaining.push(queued[index])
    index = index + 1
  }
  queued.clear()
  queued.append(remaining)
  self.static_lookup_negative_head = 0
}

///|
/// Drop one entry from `static_lookup_cache`. Negative results are drained from
/// the FIFO first; the FIFO is keyed independently and stale keys are skipped.
/// Falls back to evicting an arbitrary entry.
fn App::static_lookup_evict(self : App) -> Unit {
  let queued = self.static_lookup_negative
  let mut head = self.static_lookup_negative_head
  while head < queued.length() {
    let key = queued[head]
    head = head + 1
    match self.static_lookup_cache.get(key) {
      Some(None) => {
        ignore(self.static_lookup_cache.remove(key))
        self.static_lookup_negative_head = head
        if head == queued.length() {
          queued.clear()
          self.static_lookup_negative_head = 0
        } else if head >= STATIC_LOOKUP_COMPACT_THRESHOLD &&
          head * 2 >= queued.length() {
          self.static_lookup_compact()
        }
        return
      }
      _ => ()
    }
  }
  queued.clear()
  self.static_lookup_negative_head = 0
  match self.static_lookup_cache.keys().next() {
    Some(oldest) => ignore(self.static_lookup_cache.remove(oldest))
    None => ()
  }
}

///|
fn App::static_lookup_remember(
  self : App,
  clean : StringView,
  result : (String, String, Bool, StaticMount)?,
) -> Unit {
  if self.static_lookup_cache.length() >= STATIC_LOOKUP_CACHE_LIMIT {
    self.static_lookup_evict()
  }
  let key = clean.to_owned()
  if result is None {
    self.static_lookup_negative.push(key)
  }
  self.static_lookup_cache.set(key, result)
}

///|
/// Most recent raw static request path and its result.
let last_static_cache : Ref[Map[String, (String, String, Bool, StaticMount)?]?] = Ref(
  None,
)

///|
let last_static_path : Ref[String] = Ref("")

///|
let last_static_result : Ref[(String, String, Bool, StaticMount)?] = Ref(None)

///|
fn invalidate_last_static_lookup() -> Unit {
  last_static_cache.val = None
  last_static_path.val = ""
  last_static_result.val = None
}

///|
/// Resolve a static file request to its filesystem path, `Cache-Control` value
/// and precompressed-serving flag.
fn App::static_lookup(
  self : App,
  path : String,
) -> (String, String, Bool, StaticMount)? {
  match last_static_cache.val {
    Some(cache) =>
      if physical_equal(cache, self.static_lookup_cache) &&
        (
          physical_equal(last_static_path.val, path) ||
          last_static_path.val == path
        ) {
        return last_static_result.val
      }
    None => ()
  }
  let clean = clean_path_view(path)
  match self.static_lookup_cache.get_from_string(clean) {
    Some(cached) => cached
    None => {
      // Resolve the mount before looking up the file.
      let mount = self.best_static_mount(clean)
      let result = match mount {
        Some((mount, matched)) =>
          static_lookup_uncached(clean, mount, matched.relative_start)
        None => None
      }
      // Paths that match no mount at all are dynamic routes, so they are not
      // cached as static misses.
      if clean.length() <= PARSE_CACHE_MAX_KEY &&
        (result is Some(_) || mount is Some(_)) {
        self.static_lookup_remember(clean, result)
      }
      last_static_cache.val = Some(self.static_lookup_cache)
      last_static_path.val = path
      last_static_result.val = result
      result
    }
  }
}

///|
/// Whether `path` names the root of `mount` without the trailing slash that
/// directory indexes need. The file is only redirected once it is known to
/// exist, so a mount whose index is missing still reports 404.
fn static_root_needs_slash(path : String, mount : StaticMount) -> Bool {
  let clean = clean_path_view(path)
  if mount.index.is_empty() || mount.url_prefix == "" {
    return false
  }
  match match_mount_prefix(clean, mount.url_prefix.view()) {
    Some(matched) => matched.relative_start == clean.length()
    None => false
  }
}

///|
/// Resolve a static file request to its filesystem path, `Cache-Control` value
/// and precompressed-serving flag.
fn static_lookup_uncached(
  path_view : StringView,
  mount : StaticMount,
  relative_start : Int32,
) -> (String, String, Bool, StaticMount)? {
  let relative : StringView = path_view[relative_start:]
  let decoded = decode_url_path(relative)
  let decoded_ends_with_slash = decoded.has_suffix("/") ||
    decoded == "." ||
    decoded.has_suffix("/.")
  let clean = match clean_relative_path(decoded) {
    Some(clean) => clean
    None => return None
  }
  let needs_index = clean.is_empty() || decoded_ends_with_slash
  if needs_index && mount.index.is_empty() {
    return None
  }
  let file_path = if needs_index {
    join_fs_path(join_fs_path(mount.root, clean), mount.index)
  } else {
    join_fs_path(mount.root, clean)
  }
  Some((file_path, mount.cache_control, mount.precompressed, mount))
}

///|
/// Bind the parameters captured by a dynamic static mount prefix, so
/// `Context::param` works in the mount middleware and in the file-serving
/// pipeline exactly as it does for a dynamic route.
fn bind_static_mount_params(
  ctx : Context,
  path : String,
  mount : StaticMount,
) -> Unit {
  match match_mount_prefix(clean_path_view(path), mount.url_prefix.view()) {
    Some(matched) =>
      for name, value in matched.params {
        ctx.state.set(param_state_key(name), value)
      }
    None => ()
  }
}

///|
pub fn App::static_file_for(self : App, path : String) -> String? {
  match self.static_lookup(path) {
    Some((file_path, _, _, _)) => Some(file_path)
    None => None
  }
}

///|
pub fn App::static_cache_control_for(self : App, path : String) -> String {
  match self.static_lookup(path) {
    Some((_, cache_control, _, _)) => cache_control
    None => ""
  }
}

