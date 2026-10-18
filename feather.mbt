///|
pub const DEFAULT_MAX_BODY_SIZE : Int32 = 1000

///|
pub const PARAM_PREFIX : String = "param:"

///|
pub(all) suberror HttpError {
  HttpError(Int32, String)
}

///|
pub(all) suberror HttpErrorPayload {
  HttpErrorPayload(Int32, String, Json)
}

///|
pub(all) struct Config {
  host : String
  port : Int32
  timeout : Int32
}

///|
pub(all) struct Request {
  mut method : String
  path : String
  headers : Map[String, String]
  body : String
}

///|
pub(all) struct FileResponse {
  path : String
  content_type : String
}

///|
pub(all) struct Response {
  mut status : Int32
  headers : Map[String, String]
  mut body : String
  mut data : Bytes?
  cookies : Array[@http.Cookie]
}

///|
pub(all) struct Context {
  request : Request
  response : Response
  state : Map[String, String]
  json_state : Map[String, Json]
  cleanups : Array[() -> Unit raise]
  mut file : FileResponse?
  mut session : Session?
}

///|
pub type Handler = (Context) -> Unit raise

///|
pub type Middleware = (Handler) -> Handler

///|
pub type WebSocketHandler = async (Context, @websocket.Conn) -> Unit raise

///|
pub type SseHandler = async (Context, Sse) -> Unit raise

///|
pub type StreamHandler = async (Context, Stream) -> Unit raise

///|
pub(all) struct Route {
  path : String
  method : String
  params : Map[String, String]
  wildcard : String
  wildcard_name : String
  handler : Handler?
}

///|
pub struct RouteNode {
  mut handler : Handler?
  mut route_path : String
  mut static_children : Map[String, RouteNode]?
  mut param_child : RouteNode?
  mut wildcard_child : RouteNode?
  mut has_dynamic : Bool
  mut param_names : Array[String]
  mut param_keys : Array[String]
  mut pattern_kinds : Array[Int]
  mut route_wildcard_name : String
  mut route_wildcard_key : String
  mut exact_cache : Map[String, RouteNode]?
  mut cached_path : String
  mut cached_values : Array[String]
  mut cached_wildcard : String
}

///|
pub(all) struct NamedRoute {
  method : String
  path : String
}

///|
pub(all) struct Router {
  routes : Array[Route]
  trees : Map[String, RouteNode]
  named : Map[String, NamedRoute]
  dynamic_caches : Map[String, Map[String, (RouteNode, Int32)]]
  miss_caches : Map[String, Map[String, Array[String]]]
}

///|
pub(all) enum RouteOutcome {
  RouteFound(Route)
  RouteMethodNotAllowed(Array[String])
  RouteNotFound
}

///|
pub fn create_server(config : Config) -> Config {
  config
}

///|
fn RouteNode::new() -> RouteNode {
  {
    handler: None,
    route_path: "",
    static_children: None,
    param_child: None,
    wildcard_child: None,
    has_dynamic: false,
    param_names: [],
    param_keys: [],
    pattern_kinds: [],
    route_wildcard_name: "",
    route_wildcard_key: "",
    exact_cache: None,
    cached_path: "",
    cached_values: [],
    cached_wildcard: "",
  }
}

///|
pub fn create_router() -> Router {
  {
    routes: [],
    trees: Map([]),
    named: Map([]),
    dynamic_caches: Map([]),
    miss_caches: Map([]),
  }
}

///|
pub fn Context::new(request : Request) -> Context {
  {
    request,
    response: {
      status: 200,
      headers: Map([], capacity=4),
      body: "",
      data: None,
      cookies: [],
    },
    state: Map([], capacity=4),
    json_state: Map([], capacity=0),
    cleanups: [],
    file: None,
    session: None,
  }
}

///|
pub fn create_context() -> Context {
  Context::new({ method: "GET", path: "/", headers: Map([]), body: "", })
}

///|
pub fn compose_middleware(handlers : Array[(Context) -> Unit]) -> Handler? {
  Some(fn(ctx) {
    for handler in handlers {
      handler(ctx)
    }
  })
}

///|
pub fn apply_middleware(
  middlewares : Array[Middleware],
  last : Handler,
) -> Handler {
  let mut handler = last
  for i = middlewares.length() - 1; i >= 0; i = i - 1 {
    handler = middlewares[i](handler)
  }
  handler
}

///|
fn clean_path_view(path : String) -> StringView {
  match path.find("?") {
    Some(index) => path[:index]
    None => path.view()
  }
}

///|
fn split_segments(path : StringView) -> Array[StringView] {
  let segments : Array[StringView] = Array(capacity=4)
  for segment in path.split("/") {
    if !segment.is_empty() {
      segments.push(segment)
    }
  }
  segments
}

///|
fn join_wildcard(path : StringView, start : Int32) -> String {
  let length = path.length()
  let hint = length - start
  let builder = StringBuilder(size_hint=if hint > 0 { hint } else { 0 })
  let mut i = skip_slashes(path, start)
  let mut written = false
  while i < length {
    if written {
      builder.write_char('/')
    }
    let end = segment_end(path, i)
    builder.write_stringview(path[i:end])
    written = true
    i = skip_slashes(path, end)
  }
  builder.to_string()
}

///|
fn skip_slashes(path : StringView, pos : Int32) -> Int32 {
  let length = path.length()
  let mut start = pos
  while start < length && path.unsafe_get(start) == ('/' : UInt16) {
    start = start + 1
  }
  start
}

///|
fn segment_end(path : StringView, start : Int32) -> Int32 {
  let length = path.length()
  let mut i = start
  while i < length {
    if path.unsafe_get(i) == ('/' : UInt16) {
      return i
    }
    i = i + 1
  }
  length
}

///|
priv struct MatchOutcome {
  node : RouteNode
  wildcard_start : Int32
}

///|
fn match_dynamic_node(
  node : RouteNode,
  path : StringView,
  pos : Int32,
) -> MatchOutcome? {
  let start = skip_slashes(path, pos)
  if start >= path.length() {
    if node.handler is Some(_) {
      return Some({ node, wildcard_start: -1 })
    }
    return match node.wildcard_child {
      Some(child) => Some({ node: child, wildcard_start: pos })
      None => None
    }
  }
  let end = segment_end(path, start)
  match node.static_children {
    Some(children) =>
      match children.get_from_string(path[start:end]) {
        Some(child) =>
          match match_dynamic_node(child, path, end + 1) {
            Some(outcome) => return Some(outcome)
            None => ()
          }
        None => ()
      }
    None => ()
  }
  match node.param_child {
    Some(child) =>
      match match_dynamic_node(child, path, end + 1) {
        Some(outcome) => return Some(outcome)
        None => ()
      }
    None => ()
  }
  match node.wildcard_child {
    Some(child) => Some({ node: child, wildcard_start: pos })
    None => None
  }
}

///|
/// Extract the per-path bindings for `node`.
fn RouteNode::bound_values(
  self : RouteNode,
  path : StringView,
) -> (Array[String], String) {
  if self.cached_path != "" && self.cached_path.view() == path {
    return (self.cached_values, self.cached_wildcard)
  }
  let values : Array[String] = Array(capacity=self.param_names.length())
  let mut wildcard_value = ""
  let mut path_pos = skip_slashes(path, 0)
  for kind in self.pattern_kinds {
    if kind == 1 {
      let path_end = segment_end(path, path_pos)
      values.push(path[path_pos:path_end].to_owned())
      path_pos = skip_slashes(path, path_end + 1)
    } else if kind == 0 {
      path_pos = skip_slashes(path, segment_end(path, path_pos) + 1)
    } else {
      wildcard_value = join_wildcard(path, path_pos)
      break
    }
  }
  self.cached_path = path.to_owned()
  self.cached_values = values
  self.cached_wildcard = wildcard_value
  (values, wildcard_value)
}

///|
fn extract_route_params(
  node : RouteNode,
  path : StringView,
) -> (Map[String, String], String) {
  let names = node.param_names
  let (values, wildcard_value) = node.bound_values(path)
  let params : Map[String, String] = Map([], capacity=names.length() + 1)
  for i = 0; i < names.length(); i = i + 1 {
    params.set(names[i], values[i])
  }
  if node.route_wildcard_name != "" {
    params.set(node.route_wildcard_name, wildcard_value)
  }
  (params, wildcard_value)
}

///|
fn match_static_node(
  node : RouteNode,
  path : StringView,
  pos : Int32,
) -> RouteNode? {
  let start = skip_slashes(path, pos)
  if start >= path.length() {
    if node.handler is Some(_) {
      return Some(node)
    }
    return None
  }
  let end = segment_end(path, start)
  match node.static_children {
    Some(children) =>
      match children.get_from_string(path[start:end]) {
        Some(child) => match_static_node(child, path, end + 1)
        None => None
      }
    None => None
  }
}

///|
fn clean_route_path(path : String) -> String {
  match path.find("?") {
    Some(index) => path[:index].to_owned()
    None => path
  }
}

///|
fn has_ascii_lower(view : StringView) -> Bool {
  let length = view.length()
  let mut i = 0
  while i < length {
    let value = view.unsafe_get(i)
    if value >= ('a' : UInt16) && value <= ('z' : UInt16) {
      return true
    }
    i = i + 1
  }
  false
}

///|
/// HTTP methods are case-sensitive tokens (RFC 9110 §9.1), so registration
/// and lookup both canonicalize to upper case. This makes `"get"` match both
/// a `"GET"` route and a real `GET` request.
fn normalize_method(meth : String) -> String {
  if has_ascii_lower(meth.view()) {
    meth.to_upper()
  } else {
    meth
  }
}

///|
pub fn Router::add_route(
  self : Router,
  meth : String,
  path : String,
  handler : Handler,
) -> Unit {
  let clean_path = clean_route_path(path)
  let method_key = normalize_method(meth)
  let mut node = match self.trees.get(method_key) {
    Some(root) => root
    None => {
      let root = RouteNode::new()
      self.trees.set(method_key, root)
      root
    }
  }
  let root = node
  let param_names : Array[String] = []
  let param_keys : Array[String] = []
  let pattern_kinds : Array[Int] = []
  let mut route_wildcard_name = ""
  let mut route_wildcard_key = ""
  let mut is_static = true
  for segment in split_segments(clean_path) {
    if segment.has_prefix(":") {
      is_static = false
      let name = segment[1:].to_owned()
      param_names.push(name)
      param_keys.push(PARAM_PREFIX + name)
      pattern_kinds.push(1)
      let child = match node.param_child {
        Some(child) => child
        None => {
          let child = RouteNode::new()
          node.param_child = Some(child)
          child
        }
      }
      root.has_dynamic = true
      node = child
    } else if segment.has_prefix("*") {
      is_static = false
      let name = segment[1:].to_owned()
      route_wildcard_name = name
      route_wildcard_key = if name == "" { "" } else { PARAM_PREFIX + name }
      pattern_kinds.push(2)
      let child = match node.wildcard_child {
        Some(child) => child
        None => {
          let child = RouteNode::new()
          node.wildcard_child = Some(child)
          child
        }
      }
      root.has_dynamic = true
      node = child
      break
    } else {
      pattern_kinds.push(0)
      let key = segment.to_owned()
      let child = match node.static_children {
        Some(children) =>
          match children.get(key) {
            Some(child) => child
            None => {
              let child = RouteNode::new()
              children.set(key, child)
              child
            }
          }
        None => {
          let children : Map[String, RouteNode] = Map([], capacity=2)
          let child = RouteNode::new()
          children.set(key, child)
          node.static_children = Some(children)
          child
        }
      }
      node = child
    }
  }
  node.handler = Some(handler)
  node.route_path = clean_path
  node.param_names = param_names
  node.param_keys = param_keys
  node.pattern_kinds = pattern_kinds
  node.route_wildcard_name = route_wildcard_name
  node.route_wildcard_key = route_wildcard_key
  if is_static {
    match root.exact_cache {
      Some(cache) => cache.set(clean_path, node)
      None => {
        let cache : Map[String, RouteNode] = Map([], capacity=4)
        cache.set(clean_path, node)
        root.exact_cache = Some(cache)
      }
    }
  }
  self.dynamic_caches.remove(method_key)
  self.miss_caches.clear()
  self.routes.push({
    path: clean_path,
    method: method_key,
    params: Map([]),
    wildcard: "",
    wildcard_name: "",
    handler: Some(handler),
  })
}

///|
pub fn Router::add_named_route(
  self : Router,
  name : String,
  meth : String,
  path : String,
  handler : Handler,
) -> Unit {
  let clean_path = clean_route_path(path)
  self.add_route(meth, clean_path, handler)
  self.named.set(name, { method: normalize_method(meth), path: clean_path, })
}

///|
pub fn Router::route_name(self : Router, name : String) -> NamedRoute? {
  self.named.get(name)
}

///|
/// Percent-encode a wildcard capture for URL generation. Empty segments are
/// dropped and the rest joined with a single `/`, mirroring how route matching
/// reads a wildcard back (`join_wildcard`), so `url_for` round-trips.
fn encode_wildcard_path(value : String) -> String {
  let builder = StringBuilder(size_hint=value.length())
  let mut written = false
  for segment in value.view().split("/") {
    if segment.is_empty() {
      continue
    }
    if written {
      builder.write_char('/')
    }
    builder.write_string(url_encode(segment.to_owned()))
    written = true
  }
  builder.to_string()
}

///|
fn encode_query_string(query : Map[String, String]) -> String {
  if query.length() == 0 {
    return ""
  }
  let keys : Array[String] = []
  for key, _ in query {
    keys.push(key)
  }
  keys.sort_by(fn(a, b) { a.lexical_compare(b) })
  let builder = StringBuilder(size_hint=query.length() * 8)
  let mut first = true
  for key in keys {
    if first {
      builder.write_char('?')
      first = false
    } else {
      builder.write_char('&')
    }
    builder.write_string(url_encode(key))
    builder.write_char('=')
    match query.get(key) {
      Some(value) => builder.write_string(url_encode(value))
      None => ()
    }
  }
  builder.to_string()
}

///|
pub fn Router::url_for(
  self : Router,
  name : String,
  params? : Map[String, String],
  query? : Map[String, String],
) -> String? {
  let named = match self.named.get(name) {
    Some(route) => route
    None => return None
  }
  let values = match params {
    Some(params) => params
    None => Map([])
  }
  let path = named.path.view()
  let length = path.length()
  let mut i = skip_slashes(path, 0)
  let builder = StringBuilder(size_hint=length)
  let mut has_segment = false
  while i < length {
    has_segment = true
    builder.write_char('/')
    let end = segment_end(path, i)
    let segment = path[i:end]
    if segment.has_prefix(":") {
      match values.get_from_string(segment[1:]) {
        Some(value) =>
          if value.is_empty() {
            return None
          } else {
            builder.write_string(url_encode(value))
          }
        None => return None
      }
    } else if segment.has_prefix("*") {
      let wildcard_name = segment[1:]
      if !wildcard_name.is_empty() {
        match values.get_from_string(wildcard_name) {
          Some(value) => builder.write_string(encode_wildcard_path(value))
          None => return None
        }
      }
      // Registration stops at `*`, so segments after it never match; do not
      // render them into a URL that would bind different parameters.
      break
    } else {
      builder.write_stringview(segment)
    }
    i = skip_slashes(path, end)
  }
  let mut result = if has_segment { builder.to_string() } else { "/" }
  match query {
    Some(query) => result = result + encode_query_string(query)
    None => ()
  }
  Some(result)
}

///|
fn Router::allowed_methods(self : Router, path : StringView) -> Array[String] {
  let allowed : Array[String] = []
  for meth, root in self.trees {
    let matched = if root.has_dynamic {
      match_dynamic_node(root, path, 0) is Some(_)
    } else {
      match_static_node(root, path, 0) is Some(_)
    }
    if matched {
      allowed.push(meth)
    }
  }
  allowed.sort()
  allowed
}

///|
/// Render an `Allow` header value. `HEAD` is implicit whenever `GET` is
/// allowed (RFC 9110 §9.3.2), so it is listed even when no HEAD route exists.
fn allow_header_value(allowed : Array[String]) -> String {
  if allowed.contains("GET") && !allowed.contains("HEAD") {
    if allowed.is_sorted() {
      let builder = StringBuilder(size_hint=64)
      let mut first = true
      let mut inserted = false
      for method in allowed {
        if !inserted && method.compare("HEAD") > 0 {
          if !first {
            builder.write_string(", ")
          }
          builder.write_string("HEAD")
          first = false
          inserted = true
        }
        if !first {
          builder.write_string(", ")
        }
        builder.write_string(method)
        first = false
      }
      if !inserted {
        builder.write_string(", HEAD")
      }
      return builder.to_string()
    }
    let with_head = allowed.copy()
    with_head.push("HEAD")
    with_head.sort()
    with_head.join(", ")
  } else {
    allowed.join(", ")
  }
}

///|
priv enum RouteMatch {
  MatchFound(RouteNode, Map[String, String]?, String)
  MatchMethods(Array[String])
  MatchMissing
}

///|
fn Router::find_node_raw(
  self : Router,
  tree_key : String,
  clean_path : StringView,
) -> (RouteNode, Int32)? {
  let root = match self.trees.get(tree_key) {
    Some(root) => root
    None => return None
  }
  if !root.has_dynamic {
    match root.exact_cache {
      Some(cache) =>
        match cache.get_from_string(clean_path) {
          Some(node) => return Some((node, -1))
          None => ()
        }
      None => ()
    }
    return match match_static_node(root, clean_path, 0) {
      Some(node) => Some((node, -1))
      None => None
    }
  }
  // Dynamic trees resolve every path, static or not, through the per-method
  // dispatch cache.
  let cache = match self.dynamic_caches.get(tree_key) {
    Some(cache) => cache
    None => {
      let cache : Map[String, (RouteNode, Int32)] = Map([], capacity=32)
      self.dynamic_caches.set(tree_key, cache)
      cache
    }
  }
  match cache.get_from_string(clean_path) {
    Some(hit) => return Some(hit)
    None => ()
  }
  match root.exact_cache {
    Some(exact) =>
      match exact.get_from_string(clean_path) {
        Some(node) => {
          let hit = (node, -1)
          if cache.length() < 128 {
            cache.set(clean_path.to_owned(), hit)
          }
          return Some(hit)
        }
        None => ()
      }
    None => ()
  }
  match match_dynamic_node(root, clean_path, 0) {
    Some(outcome) => {
      let hit = (outcome.node, outcome.wildcard_start)
      if cache.length() < 128 {
        cache.set(clean_path.to_owned(), hit)
      }
      Some(hit)
    }
    None => None
  }
}

///|
fn Router::find_node(
  self : Router,
  tree_key : String,
  clean_path : StringView,
) -> (RouteNode, Map[String, String]?, String)? {
  match self.find_node_raw(tree_key, clean_path) {
    Some(hit) => {
      let (node, wildcard_start) = hit
      if wildcard_start < 0 && node.param_names.length() == 0 {
        Some((node, None, ""))
      } else {
        let (params, wildcard_value) = extract_route_params(node, clean_path)
        Some((node, Some(params), wildcard_value))
      }
    }
    None => None
  }
}

///|
fn bind_route_params(node : RouteNode, path : StringView, ctx : Context) -> Unit {
  let keys = node.param_keys
  if keys.length() == 0 && node.route_wildcard_key == "" {
    return
  }
  let (values, wildcard_value) = node.bound_values(path)
  for i = 0; i < keys.length(); i = i + 1 {
    ctx.state.set(keys[i], values[i])
  }
  if node.route_wildcard_key != "" {
    ctx.state.set(node.route_wildcard_key, wildcard_value)
  }
}

///|
priv enum DispatchMatch {
  DispatchFound(RouteNode)
  DispatchMethods(Array[String])
  DispatchMissing
}

///|
fn Router::find_miss_cache(
  self : Router,
  meth : String,
  clean_path : StringView,
) -> Array[String]? {
  match self.miss_caches.get(meth) {
    Some(cache) => cache.get_from_string(clean_path)
    None => None
  }
}

///|
fn Router::remember_miss(
  self : Router,
  meth : String,
  clean_path : StringView,
  allowed : Array[String],
) -> Unit {
  let cache = match self.miss_caches.get(meth) {
    Some(cache) => cache
    None => {
      let cache : Map[String, Array[String]] = Map([], capacity=16)
      self.miss_caches.set(meth, cache)
      cache
    }
  }
  if cache.length() < 128 {
    cache.set(clean_path.to_owned(), allowed)
  }
}

///|
fn Router::match_dispatch(
  self : Router,
  meth : String,
  clean_path : StringView,
) -> DispatchMatch {
  match self.find_node_raw(meth, clean_path) {
    Some(hit) => DispatchFound(hit.0)
    None =>
      match self.find_miss_cache(meth, clean_path) {
        Some(allowed) =>
          if allowed.length() > 0 {
            DispatchMethods(allowed)
          } else {
            DispatchMissing
          }
        None => {
          let allowed = if meth == "HEAD" {
            match self.find_node_raw("GET", clean_path) {
              Some(hit) => return DispatchFound(hit.0)
              None => self.allowed_methods(clean_path)
            }
          } else {
            self.allowed_methods(clean_path)
          }
          self.remember_miss(meth, clean_path, allowed)
          if allowed.length() > 0 {
            DispatchMethods(allowed)
          } else {
            DispatchMissing
          }
        }
      }
  }
}

///|
fn Router::match_route(
  self : Router,
  meth : String,
  clean_path : StringView,
) -> RouteMatch {
  match self.find_node(meth, clean_path) {
    Some(hit) => MatchFound(hit.0, hit.1, hit.2)
    None =>
      if meth == "HEAD" {
        match self.find_node("GET", clean_path) {
          Some(hit) => MatchFound(hit.0, hit.1, hit.2)
          None => {
            let allowed = self.allowed_methods(clean_path)
            if allowed.length() > 0 {
              MatchMethods(allowed)
            } else {
              MatchMissing
            }
          }
        }
      } else {
        let allowed = self.allowed_methods(clean_path)
        if allowed.length() > 0 {
          MatchMethods(allowed)
        } else {
          MatchMissing
        }
      }
  }
}

///|
pub fn Router::route(
  self : Router,
  meth : String,
  path : String,
) -> RouteOutcome {
  let clean_path = clean_path_view(path)
  let meth = normalize_method(meth)
  match self.match_route(meth, clean_path) {
    MatchFound(node, params, wildcard) =>
      RouteFound({
        path: node.route_path,
        method: meth,
        params: match params {
          Some(params) => params
          None => Map([], capacity=0)
        },
        wildcard,
        wildcard_name: node.route_wildcard_name,
        handler: node.handler,
      })
    MatchMethods(methods) => RouteMethodNotAllowed(methods)
    MatchMissing => RouteNotFound
  }
}

///|
pub fn Router::matching(self : Router, meth : String, path : String) -> Route? {
  if self.routes.length() == 0 {
    return Some({
      path,
      method: normalize_method(meth),
      params: Map([], capacity=0),
      wildcard: "",
      wildcard_name: "",
      handler: None,
    })
  }
  match self.route(meth, path) {
    RouteFound(route) => Some(route)
    _ => None
  }
}

///|
pub fn Router::dispatch(self : Router, ctx : Context) -> Unit raise {
  self.dispatch_with(ctx, None)
}

///|
pub fn Router::dispatch_with(
  self : Router,
  ctx : Context,
  fallback : Handler?,
) -> Unit raise {
  let clean_path = clean_path_view(ctx.request.path)
  let meth = normalize_method(ctx.request.method)
  match self.match_dispatch(meth, clean_path) {
    DispatchFound(node) => {
      bind_route_params(node, clean_path, ctx)
      match node.handler {
        Some(handler) => handler(ctx)
        None => not_found(ctx)
      }
    }
    DispatchMethods(methods) =>
      if meth == "OPTIONS" {
        respond_options(ctx, methods)
      } else {
        method_not_allowed(ctx, methods)
      }
    DispatchMissing =>
      match fallback {
        Some(handler) => handler(ctx)
        None => not_found(ctx)
      }
  }
}

///|
pub fn not_found(ctx : Context) -> Unit {
  ctx.file = None
  ctx.response.status = 404
  ctx.response.headers.set("Content-Type", "text/plain; charset=utf-8")
  ctx.response.data = None
  ctx.response.body = "404 Not Found"
}

///|
pub fn method_not_allowed(ctx : Context, allowed : Array[String]) -> Unit {
  ctx.file = None
  ctx.response.status = 405
  ctx.response.headers.set("Allow", allow_header_value(allowed))
  ctx.response.headers.set("Content-Type", "text/plain; charset=utf-8")
  ctx.response.data = None
  ctx.response.body = "405 Method Not Allowed"
}

///|
/// Answer an `OPTIONS` request for a path that exists under other methods with
/// `204 No Content` and an `Allow` header, without running any handler.
pub fn respond_options(ctx : Context, allowed : Array[String]) -> Unit {
  ctx.file = None
  ctx.response.status = 204
  ctx.response.headers.set("Allow", allow_header_value(allowed))
  ctx.response.data = None
  ctx.response.body = ""
}

///|
pub fn internal_error(ctx : Context, detail : String) -> Unit {
  ctx.file = None
  ctx.state.set("error", detail)
  ctx.response.status = 500
  ctx.response.headers.set("Content-Type", "text/plain; charset=utf-8")
  ctx.response.data = None
  ctx.response.body = "Internal Server Error"
}

///|
let error_body_cache : Map[Int32, Map[String, String]] = Map([])

///|
fn cached_error_body(status : Int32, message : String) -> String {
  let by_message = match error_body_cache.get(status) {
    Some(by_message) => by_message
    None => {
      let by_message : Map[String, String] = Map([], capacity=4)
      if error_body_cache.length() < 32 {
        error_body_cache.set(status, by_message)
      }
      by_message
    }
  }
  match by_message.get(message) {
    Some(body) => body
    None => {
      let payload : Map[String, Json] = Map([], capacity=2)
      payload.set("status", Json::number(status.to_double()))
      payload.set("error", Json::string(message))
      let body = Json::object(payload).stringify()
      if by_message.length() < 8 {
        by_message.set(message, body)
      }
      body
    }
  }
}

///|
pub fn error_response(ctx : Context, status : Int32, message : String) -> Unit {
  ctx.file = None
  ctx.response.status = status
  ctx.response.headers.set("Content-Type", "application/json; charset=utf-8")
  ctx.response.data = None
  ctx.response.body = cached_error_body(status, message)
}

///|
pub fn error_response_with_payload(
  ctx : Context,
  status : Int32,
  message : String,
  payload : Json,
) -> Unit {
  ctx.file = None
  let body : Map[String, Json] = Map([], capacity=4)
  body.set("status", Json::number(status.to_double()))
  body.set("error", Json::string(message))
  match payload {
    Json::Object(extra) =>
      for key, value in extra {
        body.set(key, value)
      }
    _ => body.set("detail", payload)
  }
  ctx.response.status = status
  ctx.response.headers.set("Content-Type", "application/json; charset=utf-8")
  ctx.response.data = None
  ctx.response.body = Json::object(body).stringify()
}



///|
pub fn Context::fail(
  self : Context,
  status : Int32,
  message : String,
) -> Unit raise HttpError {
  ignore(self)
  raise HttpError(status, message)
}

///|
pub fn Context::fail_with(
  self : Context,
  status : Int32,
  message : String,
  payload : Json,
) -> Unit raise HttpErrorPayload {
  ignore(self)
  raise HttpErrorPayload(status, message, payload)
}

///|
pub fn Context::json_body(self : Context) -> Json raise HttpError {
  @json.parse(self.request.body) catch {
    _ => raise HttpError(400, "invalid JSON body")
  }
}

///|
pub fn[T : @json.FromJson] Context::json_as(
  self : Context,
) -> T raise HttpError {
  @json.from_json(self.json_body()) catch {
    _ => raise HttpError(400, "invalid JSON body")
  }
}

///|
pub fn Context::set(self : Context, key : String, value : String) -> Unit {
  self.state.set(key, value)
}

///|
pub fn Context::get(self : Context, key : String) -> String {
  match self.state.get(key) {
    Some(value) => value
    None => ""
  }
}

///|
/// Parameter names mapped to their `param:`-prefixed state keys.
let param_key_cache : Map[String, String] = Map([])

///|
fn param_state_key(name : String) -> String {
  match param_key_cache.get(name) {
    Some(key) => key
    None => {
      let key = PARAM_PREFIX + name
      if param_key_cache.length() < PARSE_CACHE_LIMIT {
        param_key_cache.set(name, key)
      }
      key
    }
  }
}

///|
pub fn Context::param(self : Context, name : String) -> String {
  if self.state.is_empty() {
    return ""
  }
  match self.state.get(param_state_key(name)) {
    Some(value) => value
    None => ""
  }
}

///|
/// Like `Context::param`, but percent-decodes the captured segment.
///
/// Route matching keeps the raw text (so `%2F` cannot act as another path
/// separator), which means `Context::param` returns whatever the client
/// typed. Use this accessor for slugs and ids that should be decoded before
/// display or lookup; `+` is kept as-is because it has no special meaning in a
/// path segment.
pub fn Context::param_decoded(self : Context, name : String) -> String {
  let raw = self.param(name)
  if raw == "" {
    return ""
  }
  decode_url_path(raw.view())
}

///|
pub fn Context::params(self : Context) -> Map[String, String] {
  let result : Map[String, String] = Map([], capacity=4)
  let prefix_length = PARAM_PREFIX.length()
  for key, value in self.state {
    if key.has_prefix(PARAM_PREFIX) {
      result.set(key[prefix_length:].to_owned(), value)
    }
  }
  result
}

///|
pub fn Context::status(self : Context, code : Int32) -> Unit {
  self.response.status = code
}

///|
pub fn Context::set_header(
  self : Context,
  key : String,
  value : String,
) -> Unit {
  self.response.headers.set(key, value)
}

///|
pub fn Context::text(self : Context, status : Int32, body : String) -> Unit {
  self.file = None
  self.response.status = status
  self.response.headers.set("Content-Type", "text/plain; charset=utf-8")
  self.response.data = None
  self.response.body = body
}

///|
pub fn Context::bytes(
  self : Context,
  status : Int32,
  data : Bytes,
  content_type~ : String = "application/octet-stream",
) -> Unit {
  self.file = None
  self.response.status = status
  self.response.headers.set("Content-Type", content_type)
  self.response.body = ""
  self.response.data = Some(data)
}

///|
pub fn Context::html(self : Context, status : Int32, body : String) -> Unit {
  self.file = None
  self.response.status = status
  self.response.headers.set("Content-Type", "text/html; charset=utf-8")
  self.response.data = None
  self.response.body = body
}

///|
pub fn json_object(data : Map[String, String]) -> Json {
  let object : Map[String, Json] = Map([], capacity=data.length())
  for key, value in data {
    object.set(key, Json::string(value))
  }
  Json::object(object)
}

///|
pub fn Context::json_value(self : Context, status : Int32, data : Json) -> Unit {
  self.file = None
  self.response.status = status
  self.response.headers.set("Content-Type", "application/json; charset=utf-8")
  self.response.data = None
  self.response.body = match data {
    Json::Object(members) if members.is_empty() => "{}"
    Json::Array(items) if items.is_empty() => "[]"
    _ => data.stringify()
  }
}

///|
pub fn Context::json(
  self : Context,
  status : Int32,
  data : Map[String, String],
) -> Unit {
  self.json_value(status, json_object(data))
}

///|
pub fn[T : @json.ToJson] Context::json_of(
  self : Context,
  status : Int32,
  value : T,
) -> Unit {
  self.json_value(status, @json.to_json(value))
}

///|
pub fn Context::redirect(
  self : Context,
  status : Int32,
  location : String,
) -> Unit {
  self.file = None
  self.response.status = status
  self.response.headers.set("Location", location)
  self.response.data = None
  self.response.body = ""
}

///|
pub fn Context::no_content(self : Context) -> Unit {
  self.file = None
  self.response.status = 204
  self.response.body = ""
  self.response.data = None
  self.response.headers.remove("Content-Type")
}

///|
pub fn Context::get_method(self : Context) -> String {
  self.request.method
}

///|
pub fn Context::get_path(self : Context) -> String {
  self.request.path
}

///|
pub fn Context::header(self : Context, key : String) -> String {
  match self.request.headers.get(key) {
    Some(value) => value
    None => {
      let target = key.view()
      let target_length = target.length()
      for name, value in self.request.headers {
        if name.length() == target_length &&
          name.view().equal_ignore_ascii_case(target) {
          return value
        }
      }
      ""
    }
  }
}

///|
/// The host name from the `Host` header, without the port.
pub fn Context::host(self : Context) -> String {
  let authority = trim_ascii_space(self.header("Host").view())
  if authority == "" {
    return ""
  }
  if authority.unsafe_get(0) == ('[' : UInt16) {
    match authority.find("]") {
      Some(index) => return authority[:index + 1].to_owned()
      None => return authority.to_owned()
    }
  }
  match authority.find(":") {
    Some(index) => authority[:index].to_owned()
    None => authority.to_owned()
  }
}

///|
/// The URL scheme of the request, honoring `X-Forwarded-Proto` when present.
pub fn Context::protocol(self : Context) -> String {
  let forwarded = trim_ascii_space(self.header("X-Forwarded-Proto").view())
  if forwarded != "" {
    let value = match forwarded.find(",") {
      Some(index) => trim_ascii_space(forwarded[:index])
      None => forwarded
    }
    if !value.is_empty() {
      return value.to_owned()
    }
  }
  "http"
}

///|
/// Whether the request is considered to arrive over HTTPS.
pub fn Context::is_secure(self : Context) -> Bool {
  self.protocol().view().equal_ignore_ascii_case("https".view())
}

///|
/// The full URL of the request, for example `https://example.com/users/1?q=x`.
pub fn Context::full_url(self : Context) -> String {
  let scheme = self.protocol()
  let authority = trim_ascii_space(self.header("Host").view()).to_owned()
  if authority == "" {
    return self.request.path
  }
  scheme + "://" + authority + self.request.path
}

///|
/// Address of the client that opened the connection, without the ephemeral
/// port. When the request is served by `App::serve` this is the peer IP
/// recorded by the server; contexts built by hand report `"127.0.0.1"` unless
/// `remote_addr` was set in the state.
pub fn Context::ip(self : Context) -> String {
  match self.state.get("remote_addr") {
    Some(value) => value
    None => "127.0.0.1"
  }
}

///|
pub fn Context::forwarded_ip(self : Context) -> String {
  let forwarded = self.header("X-Forwarded-For")
  if forwarded != "" {
    return match forwarded.find(",") {
      Some(index) => trim_ascii_space(forwarded[:index]).to_owned()
      None => trim_ascii_space(forwarded).to_owned()
    }
  }
  let real_ip = self.header("X-Real-IP")
  if real_ip != "" {
    return trim_ascii_space(real_ip.view()).to_owned()
  }
  self.ip()
}

///|
fn is_cookie_whitespace(code : UInt16) -> Bool {
  code == (' ' : UInt16) ||
  code == ('\t' : UInt16) ||
  code == ('\n' : UInt16) ||
  code == ('\r' : UInt16)
}

///|
fn parse_cookie_map(header : StringView) -> Map[String, String] {
  let cookies : Map[String, String] = Map([], capacity=8)
  let length = header.length()
  let mut pos = 0
  while pos <= length {
    let mut end = pos
    while end < length && header.unsafe_get(end) != (';' : UInt16) {
      end = end + 1
    }
    let mut start = pos
    while start < end && is_cookie_whitespace(header.unsafe_get(start)) {
      start = start + 1
    }
    let mut stop = end
    while stop > start && is_cookie_whitespace(header.unsafe_get(stop - 1)) {
      stop = stop - 1
    }
    if start < stop {
      let mut eq = start
      while eq < stop && header.unsafe_get(eq) != ('=' : UInt16) {
        eq = eq + 1
      }
      if eq < stop {
        let mut name_end = eq
        while name_end > start && is_cookie_whitespace(header.unsafe_get(name_end - 1)) {
          name_end = name_end - 1
        }
        if name_end > start {
          let name = header[start:name_end].to_owned()
          let mut raw_start = eq + 1
          while raw_start < stop &&
            is_cookie_whitespace(header.unsafe_get(raw_start)) {
            raw_start = raw_start + 1
          }
          let value = if stop - raw_start >= 2 &&
            header.unsafe_get(raw_start) == ('"' : UInt16) &&
            header.unsafe_get(stop - 1) == ('"' : UInt16) {
            header[raw_start + 1:stop - 1].to_owned()
          } else {
            header[raw_start:stop].to_owned()
          }
          cookies.set(name, value)
        }
      }
    }
    if end >= length {
      break
    }
    pos = end + 1
  }
  cookies
}

///|
/// Maximum number of entries kept in the parse caches.
const PARSE_CACHE_LIMIT : Int = 128

///|
/// Maximum key length stored in the parse caches.
const PARSE_CACHE_MAX_KEY : Int = 4096

///|
fn[K : Hash + Eq, V] parse_cache_set(
  cache : Map[K, V],
  key : K,
  value : V,
) -> Unit {
  if cache.length() >= PARSE_CACHE_LIMIT {
    match cache.keys().next() {
      Some(oldest) => ignore(cache.remove(oldest))
      None => ()
    }
  }
  cache.set(key, value)
}

///|
/// Last parsed `Cookie` header, keyed by its raw value.
let cookies_cache : Map[String, Map[String, String]] = Map([])

///|
/// Last parsed query strings, keyed by the raw text after `?`.
let queries_cache : Map[StringView, Map[String, String]] = Map([])

///|
/// Most recently resolved `Cookie` header and its parsed map.
let last_cookie_header : Ref[String?] = Ref(None)
let last_cookie_map : Ref[Map[String, String]?] = Ref(None)

///|
fn cookie_map_lookup(header : String) -> Map[String, String] {
  match last_cookie_header.val {
    Some(cached_header) =>
      if physical_equal(cached_header, header) {
        match last_cookie_map.val {
          Some(cached_map) => return cached_map
          None => ()
        }
      }
    None => ()
  }
  let parsed = match cookies_cache.get(header) {
    Some(cached) => cached
    None => {
      let parsed = parse_cookie_map(header.view())
      if header.length() <= PARSE_CACHE_MAX_KEY {
        parse_cache_set(cookies_cache, header, parsed)
      }
      parsed
    }
  }
  last_cookie_header.val = Some(header)
  last_cookie_map.val = Some(parsed)
  parsed
}

///|
/// Most recently resolved query string and its parsed map.
let last_query_path : Ref[String?] = Ref(None)
let last_query_start : Ref[Int] = Ref(-1)
let last_query_map : Ref[Map[String, String]?] = Ref(None)

///|
fn query_map_lookup(path : String, index : Int) -> Map[String, String] {
  match last_query_path.val {
    Some(cached_path) =>
      if physical_equal(cached_path, path) && last_query_start.val == index {
        match last_query_map.val {
          Some(cached_map) => return cached_map
          None => ()
        }
      }
    None => ()
  }
  let source = path.view()[index + 1:]
  let parsed = match queries_cache.get(source) {
    Some(cached) => cached
    None => {
      let parsed = parse_urlencoded_view(source)
      if source.length() <= PARSE_CACHE_MAX_KEY {
        parse_cache_set(queries_cache, source, parsed)
      }
      parsed
    }
  }
  last_query_path.val = Some(path)
  last_query_start.val = index
  last_query_map.val = Some(parsed)
  parsed
}

///|
/// Most recently resolved multi-value query string and its parsed map.
let last_query_multi_path : Ref[String?] = Ref(None)
let last_query_multi_start : Ref[Int] = Ref(-1)
let last_query_multi_map : Ref[Map[String, Array[String]]?] = Ref(None)

///|
/// Parsed multi-value query strings, keyed by the raw text after `?`.
let queries_multi_cache : Map[StringView, Map[String, Array[String]]] = Map([])

///|
fn query_multi_lookup(path : String, index : Int) -> Map[String, Array[String]] {
  match last_query_multi_path.val {
    Some(cached_path) =>
      if physical_equal(cached_path, path) && last_query_multi_start.val == index {
        match last_query_multi_map.val {
          Some(cached_map) => return cached_map
          None => ()
        }
      }
    None => ()
  }
  let source = path.view()[index + 1:]
  let parsed = match queries_multi_cache.get(source) {
    Some(cached) => cached
    None => {
      let parsed = parse_urlencoded_multi(source)
      if source.length() <= PARSE_CACHE_MAX_KEY {
        parse_cache_set(queries_multi_cache, source, parsed)
      }
      parsed
    }
  }
  last_query_multi_path.val = Some(path)
  last_query_multi_start.val = index
  last_query_multi_map.val = Some(parsed)
  parsed
}

///|
/// Most recently resolved url-encoded form body and its parsed map.
let last_form_body : Ref[String?] = Ref(None)
let last_form_map : Ref[Map[String, String]?] = Ref(None)

///|
/// Parsed url-encoded form bodies, keyed by the raw body text.
let forms_cache : Map[String, Map[String, String]] = Map([])

///|
fn form_map_lookup(body : String) -> Map[String, String] {
  match last_form_body.val {
    Some(cached_body) =>
      if physical_equal(cached_body, body) {
        match last_form_map.val {
          Some(cached_map) => return cached_map
          None => ()
        }
      }
    None => ()
  }
  let parsed = match forms_cache.get(body) {
    Some(cached) => cached
    None => {
      let parsed = parse_urlencoded_view(body.view())
      if body.length() <= PARSE_CACHE_MAX_KEY {
        parse_cache_set(forms_cache, body, parsed)
      }
      parsed
    }
  }
  last_form_body.val = Some(body)
  last_form_map.val = Some(parsed)
  parsed
}

///|
/// Most recently resolved multi-value url-encoded form body and its parsed map.
let last_form_values_body : Ref[String?] = Ref(None)
let last_form_values_map : Ref[Map[String, Array[String]]?] = Ref(None)

///|
/// Parsed multi-value url-encoded form bodies, keyed by the raw body text.
let forms_multi_cache : Map[String, Map[String, Array[String]]] = Map([])

///|
fn form_values_lookup(body : String) -> Map[String, Array[String]] {
  match last_form_values_body.val {
    Some(cached_body) =>
      if physical_equal(cached_body, body) {
        match last_form_values_map.val {
          Some(cached_map) => return cached_map
          None => ()
        }
      }
    None => ()
  }
  let parsed = match forms_multi_cache.get(body) {
    Some(cached) => cached
    None => {
      let parsed = parse_urlencoded_multi(body.view())
      if body.length() <= PARSE_CACHE_MAX_KEY {
        parse_cache_set(forms_multi_cache, body, parsed)
      }
      parsed
    }
  }
  last_form_values_body.val = Some(body)
  last_form_values_map.val = Some(parsed)
  parsed
}

///|
/// Most recently resolved multipart body and its parsed parts.
let last_multipart_body : Ref[String?] = Ref(None)
let last_multipart_content_type : Ref[String?] = Ref(None)
let last_multipart_parts : Ref[Array[MultipartPart]?] = Ref(None)

///|
/// Parsed multipart bodies, keyed by the raw body text; the stored content
/// type guards against a changed boundary for the same body.
let multipart_cache : Map[String, (String, Array[MultipartPart])] = Map([])

///|
/// Copy a parsed multipart result so callers get their own array and header
/// maps.
fn copy_multipart_parts(parts : Array[MultipartPart]) -> Array[MultipartPart] {
  let copy : Array[MultipartPart] = Array(capacity=parts.length())
  for part in parts {
    copy.push({
      name: part.name,
      filename: part.filename,
      content_type: part.content_type,
      headers: part.headers.copy(),
      data: part.data,
    })
  }
  copy
}

///|
fn multipart_parts_lookup(
  body : String,
  content_type : String,
) -> Array[MultipartPart]? {
  match last_multipart_body.val {
    Some(cached_body) =>
      if physical_equal(cached_body, body) &&
        last_multipart_content_type.val is Some(cached_type) &&
        cached_type == content_type {
        match last_multipart_parts.val {
          Some(cached) => return Some(cached)
          None => ()
        }
      }
    None => ()
  }
  let parsed = match multipart_cache.get(body) {
    Some((cached_type, parts)) =>
      if cached_type == content_type {
        Some(parts)
      } else {
        None
      }
    None => None
  }
  let parsed = match parsed {
    Some(parts) => Some(parts)
    None => {
      let result = parse_multipart(body, content_type)
      match result {
        Some(parts) =>
          if body.length() <= PARSE_CACHE_MAX_KEY {
            parse_cache_set(multipart_cache, body, (content_type, parts))
          }
        None => ()
      }
      result
    }
  }
  match parsed {
    Some(parts) => {
      last_multipart_body.val = Some(body)
      last_multipart_content_type.val = Some(content_type)
      last_multipart_parts.val = Some(parts)
    }
    None => ()
  }
  parsed
}

///|
pub fn Context::cookies(self : Context) -> Map[String, String] {
  let header = self.header("Cookie")
  if header == "" {
    return Map([], capacity=8)
  }
  cookie_map_lookup(header).copy()
}

///|
pub fn Context::cookie(self : Context, name : String) -> String? {
  if name == "" {
    return None
  }
  let header = self.header("Cookie")
  if header == "" {
    return None
  }
  match last_cookie_header.val {
    Some(cached_header) =>
      if physical_equal(cached_header, header) {
        match last_cookie_map.val {
          Some(cached_map) => return cached_map.get(name)
          None => ()
        }
      }
    None => ()
  }
  match cookies_cache.get(header) {
    Some(cached) => {
      last_cookie_header.val = Some(header)
      last_cookie_map.val = Some(cached)
      cached.get(name)
    }
    None => {
      let parsed = parse_cookie_map(header.view())
      if header.length() <= PARSE_CACHE_MAX_KEY {
        parse_cache_set(cookies_cache, header, parsed)
      }
      last_cookie_header.val = Some(header)
      last_cookie_map.val = Some(parsed)
      parsed.get(name)
    }
  }
}

///|
fn strip_control_characters(value : String) -> String {
  let view = value.view()
  let length = view.length()
  let mut i = 0
  let mut needs_clean = false
  while i < length {
    let code = view.unsafe_get(i).to_int()
    if code < 0x20 || code == 0x7F {
      needs_clean = true
      break
    }
    i = i + 1
  }
  if !needs_clean {
    return value
  }
  let builder = StringBuilder(size_hint=length)
  let mut index = 0
  while index < length {
    let code = view.unsafe_get(index).to_int()
    if code >= 0x20 && code != 0x7F {
      builder.write_char(code.unsafe_to_char())
    }
    index = index + 1
  }
  builder.to_string()
}

///|
pub fn Context::add_cookie(
  self : Context,
  name : String,
  value : String,
  path? : String,
  max_age? : Int64,
  domain? : String,
  same_site? : String,
  http_only~ : Bool = false,
  secure~ : Bool = false,
) -> Unit {
  let clean_path = match path {
    Some(value) => Some(strip_control_characters(value))
    None => None
  }
  let clean_domain = match domain {
    Some(value) => Some(strip_control_characters(value))
    None => None
  }
  self.response.cookies.push(
    @http.Cookie(
      strip_control_characters(name),
      strip_control_characters(value),
      path?=clean_path,
      max_age?=max_age,
      domain?=clean_domain,
      http_only=http_only,
      secure=secure,
      extensions=match same_site {
        Some(value) => ["SameSite=" + strip_control_characters(value)]
        None => []
      },
    ),
  )
}

///|
fn render_cookie(cookie : @http.Cookie) -> String {
  let builder = StringBuilder(
    size_hint=(cookie.name.length() + cookie.value.length() + 64) * 2,
  )
  builder.write_string(cookie.name)
  builder.write_char('=')
  builder.write_string(cookie.value)
  match cookie.path {
    Some(path) => {
      builder.write_string("; Path=")
      builder.write_string(path)
    }
    None => ()
  }
  match cookie.max_age {
    Some(max_age) => {
      builder.write_string("; Max-Age=")
      builder.write_string(max_age.to_string())
    }
    None => ()
  }
  match cookie.domain {
    Some(domain) => {
      builder.write_string("; Domain=")
      builder.write_string(domain)
    }
    None => ()
  }
  if cookie.http_only {
    builder.write_string("; HttpOnly")
  }
  if cookie.secure {
    builder.write_string("; Secure")
  }
  for extension in cookie.extensions {
    builder.write_string("; ")
    builder.write_string(extension)
  }
  builder.to_string()
}

///|
pub fn Context::set_cookie(
  self : Context,
  name : String,
  value : String,
  path? : String,
  max_age? : Int64,
  domain? : String,
  same_site? : String,
  http_only~ : Bool = false,
  secure~ : Bool = false,
) -> Unit {
  let clean_path = match path {
    Some(value) => Some(strip_control_characters(value))
    None => None
  }
  let clean_domain = match domain {
    Some(value) => Some(strip_control_characters(value))
    None => None
  }
  let cookie = @http.Cookie(
    strip_control_characters(name),
    strip_control_characters(value),
    path?=clean_path,
    max_age?=max_age,
    domain?=clean_domain,
    http_only=http_only,
    secure=secure,
    extensions=match same_site {
      Some(value) => ["SameSite=" + strip_control_characters(value)]
      None => []
    },
  )
  self.response.headers.set("Set-Cookie", render_cookie(cookie))
  self.response.cookies.push(cookie)
}

///|
pub fn Context::clear_cookie(
  self : Context,
  name : String,
  path? : String,
  domain? : String,
) -> Unit {
  self.set_cookie(name, "", path?, max_age=0L, domain?)
}

///|
pub fn Context::bearer_token(self : Context) -> String? {
  let authorization = self.header("Authorization")
  let view = authorization.view()
  if starts_with_ignore_ascii_case(view, "Bearer ".view()) {
    Some(trim_ascii_space(view[7:]).to_owned())
  } else {
    None
  }
}

///|
/// Parse an `Authorization: Basic ...` header into a `(username, password)`
/// pair. Returns `None` when the header is missing or malformed.
pub fn Context::basic_auth(self : Context) -> (String, String)? {
  let authorization = self.header("Authorization")
  let view = authorization.view()
  if !starts_with_ignore_ascii_case(view, "Basic ".view()) {
    return None
  }
  let encoded = trim_ascii_space(view[6:])
  let decoded = match base64_decode_view(encoded) {
    Some(decoded) => @utf8.decode_lossy(decoded)
    None => return None
  }
  match decoded.find(":") {
    Some(index) =>
      Some((decoded[:index].to_owned(), decoded[index + 1:].to_owned()))
    None => Some((decoded, ""))
  }
}

///|
pub fn Context::request_id(self : Context) -> String {
  match self.state.get("request_id") {
    Some(value) => value
    None => ""
  }
}

///|
fn parse_int_value(value : StringView) -> Int? {
  let length = value.length()
  if length == 0 {
    return None
  }
  let mut index = 0
  let mut negative = false
  let first = value.unsafe_get(0)
  if first == ('-' : UInt16) {
    negative = true
    index = 1
  } else if first == ('+' : UInt16) {
    index = 1
  }
  if index >= length {
    return None
  }
  let mut result = 0L
  while index < length {
    let digit = value.unsafe_get(index).to_int() - 48
    if digit < 0 || digit > 9 {
      return None
    }
    result = result * 10L + digit.to_int64()
    if result > 2147483648L {
      return None
    }
    index = index + 1
  }
  let signed = if negative { -result } else { result }
  if signed > 2147483647L || signed < -2147483648L {
    return None
  }
  Some(signed.to_int())
}

///|
fn parse_bool_value(value : StringView) -> Bool? {
  if value == "true" || value == "1" {
    Some(true)
  } else if value == "false" || value == "0" {
    Some(false)
  } else {
    None
  }
}

///|
pub fn Context::param_int(self : Context, name : String) -> Int? {
  parse_int_value(self.param(name).view())
}

///|
pub fn Context::param_bool(self : Context, name : String) -> Bool? {
  parse_bool_value(self.param(name).view())
}

///|
pub fn Context::query_int(self : Context, name : String) -> Int? {
  parse_int_value(self.query(name).view())
}

///|
pub fn Context::query_bool(self : Context, name : String) -> Bool? {
  parse_bool_value(self.query(name).view())
}

///|
pub fn Context::set_json(self : Context, key : String, value : Json) -> Unit {
  self.json_state.set(key, value)
}

///|
pub fn Context::get_json(self : Context, key : String) -> Json? {
  self.json_state.get(key)
}

///|
/// Register `cleanup` to run when the request finishes, whether the handler
/// succeeded or failed. Cleanups run in reverse registration order and are
/// best-effort: a cleanup that raises does not stop the others.
pub fn Context::defer_cleanup(self : Context, cleanup : () -> Unit raise) -> Unit {
  self.cleanups.push(cleanup)
}

///|
/// Build a `Content-Disposition` field value with `disposition` (`attachment`
/// or `inline`) and the given file name, quoting and escaping the ASCII form
/// and appending an RFC 6266 `filename*` parameter for non-ASCII names.
fn content_disposition_value(disposition : String, name : String) -> String {
  let clean = strip_control_characters(name)
  let view = clean.view()
  let length = view.length()
  let escaped = StringBuilder(size_hint=length + 8)
  let mut has_non_ascii = false
  let mut i = 0
  while i < length {
    let code = view.unsafe_get(i).to_int()
    if code < 0x80 {
      if code == 34 {
        escaped.write_string("\\\"")
      } else if code == 92 {
        escaped.write_string("\\\\")
      } else {
        escaped.write_char(code.unsafe_to_char())
      }
    } else {
      has_non_ascii = true
      escaped.write_char('_')
    }
    i = i + 1
  }
  if has_non_ascii {
    disposition +
    "; filename=\"" +
    escaped.to_string() +
    "\"; filename*=UTF-8''" +
    url_encode(clean)
  } else {
    disposition + "; filename=\"" + escaped.to_string() + "\""
  }
}

///|
fn content_disposition_attachment(name : String) -> String {
  content_disposition_value("attachment", name)
}

///|
/// Run the cleanups registered with `Context::defer_cleanup`, last
/// registered first. A cleanup that raises does not prevent the remaining
/// cleanups from running: the error is swallowed and the loop continues, so
/// resource release is best-effort and never masks the request outcome.
pub fn Context::run_cleanups(self : Context) -> Unit {
  while self.cleanups.length() > 0 {
    match self.cleanups.pop() {
      Some(cleanup) => cleanup() catch {
        _ => ()
      }
      None => ()
    }
  }
}

///|
pub fn Context::file(
  self : Context,
  status : Int32,
  path : String,
  content_type? : String,
  download_name? : String,
) -> Unit {
  let resolved_type = match content_type {
    Some(content_type) => content_type
    None => mime_type_for(path)
  }
  self.response.status = status
  self.response.body = ""
  self.response.data = None
  self.response.headers.set("Content-Type", resolved_type)
  match download_name {
    Some(name) =>
      self.response.headers.set(
        "Content-Disposition",
        content_disposition_attachment(name),
      )
    None => ()
  }
  self.file = Some({ path, content_type: resolved_type, })
}

///|
pub fn Context::file_response(self : Context) -> FileResponse? {
  self.file
}

///|
/// Set `Content-Disposition: attachment` with `filename`, so browsers download
/// the response body instead of rendering it. The header can accompany any
/// body set through `Context::file`, `Context::text`, `Context::bytes` or
/// `Context::json`. The name is quoted and escaped, and non-ASCII names also
/// receive an RFC 6266 `filename*` parameter.
pub fn Context::attachment(self : Context, filename : String) -> Unit {
  self.response.headers.set(
    "Content-Disposition",
    content_disposition_value("attachment", filename),
  )
}

///|
/// Set `Content-Disposition: inline` with `filename`, keeping the response
/// eligible for in-place rendering (for example an image or PDF) while still
/// naming the payload. Escaping and non-ASCII handling follow
/// `Context::attachment`.
pub fn Context::inline(self : Context, filename : String) -> Unit {
  self.response.headers.set(
    "Content-Disposition",
    content_disposition_value("inline", filename),
  )
}

///|
fn owned_trimmed(view : StringView) -> String {
  let length = view.length()
  let mut start = 0
  while start < length {
    let code = view.unsafe_get(start)
    if code > (' ' : UInt16) {
      break
    }
    if code != (' ' : UInt16) &&
      code != ('\t' : UInt16) &&
      code != ('\n' : UInt16) &&
      code != ('\r' : UInt16) {
      break
    }
    start = start + 1
  }
  let mut end = length
  while end > start {
    let code = view.unsafe_get(end - 1)
    if code > (' ' : UInt16) {
      break
    }
    if code != (' ' : UInt16) &&
      code != ('\t' : UInt16) &&
      code != ('\n' : UInt16) &&
      code != ('\r' : UInt16) {
      break
    }
    end = end - 1
  }
  let offset = view.start_offset()
  view.data().unsafe_substring(start=offset + start, end=offset + end)
}

///|
fn trim_ascii_space(view : StringView) -> StringView {
  let length = view.length()
  let mut start = 0
  while start < length {
    let code = view.unsafe_get(start)
    if code > (' ' : UInt16) {
      break
    }
    if code != (' ' : UInt16) &&
      code != ('\t' : UInt16) &&
      code != ('\n' : UInt16) &&
      code != ('\r' : UInt16) {
      break
    }
    start = start + 1
  }
  let mut end = length
  while end > start {
    let code = view.unsafe_get(end - 1)
    if code > (' ' : UInt16) {
      break
    }
    if code != (' ' : UInt16) &&
      code != ('\t' : UInt16) &&
      code != ('\n' : UInt16) &&
      code != ('\r' : UInt16) {
      break
    }
    end = end - 1
  }
  view[start:end]
}

///|
fn hex_digit(value : Int) -> Int {
  if value >= 48 && value <= 57 {
    value - 48
  } else if value >= 65 && value <= 70 {
    value - 55
  } else if value >= 97 && value <= 102 {
    value - 87
  } else {
    -1
  }
}

///|
fn decode_url_bytes(bytes : BytesView, plus_as_space : Bool) -> String {
  let length = bytes.length()
  let out = FixedArray::make(length, b' ')
  let mut out_index = 0
  let mut i = 0
  while i < length {
    let byte = bytes[i].to_int()
    if byte == 37 && i + 2 < length {
      let high = hex_digit(bytes[i + 1].to_int())
      let low = hex_digit(bytes[i + 2].to_int())
      if high >= 0 && low >= 0 {
        out[out_index] = (high * 16 + low).to_byte()
        out_index = out_index + 1
        i = i + 3
        continue
      }
    } else if byte == 43 && plus_as_space {
      out[out_index] = b' '
      out_index = out_index + 1
      i = i + 1
      continue
    }
    out[out_index] = byte.to_byte()
    out_index = out_index + 1
    i = i + 1
  }
  @utf8.decode_lossy(out.unsafe_reinterpret_as_bytes()[:out_index])
}

///|
fn decode_url_impl(source : StringView, plus_as_space : Bool) -> String {
  let length = source.length()
  let mut ascii_only = true
  let mut needs_decoding = false
  let mut i = 0
  while i < length {
    let value = source.unsafe_get(i).to_int()
    if value > 127 {
      ascii_only = false
    } else if value == 37 || (value == 43 && plus_as_space) {
      needs_decoding = true
      break
    }
    i = i + 1
  }
  if !needs_decoding {
    return source.to_owned()
  }
  if !ascii_only {
    return decode_url_bytes(@utf8.encode(source), plus_as_space)
  }
  let out = FixedArray::make(length, b' ')
  let mut out_index = 0
  let mut j = 0
  while j < length {
    let code = source.unsafe_get(j).to_int()
    if code == 37 && j + 2 < length {
      let high = hex_digit(source.unsafe_get(j + 1).to_int())
      let low = hex_digit(source.unsafe_get(j + 2).to_int())
      if high >= 0 && low >= 0 {
        out[out_index] = (high * 16 + low).to_byte()
        out_index = out_index + 1
        j = j + 3
        continue
      }
    } else if code == 43 && plus_as_space {
      out[out_index] = b' '
      out_index = out_index + 1
      j = j + 1
      continue
    } else if code > 127 {
      return decode_url_bytes(@utf8.encode(source), plus_as_space)
    }
    out[out_index] = code.to_byte()
    out_index = out_index + 1
    j = j + 1
  }
  @utf8.decode_lossy(out.unsafe_reinterpret_as_bytes()[:out_index])
}

///|
fn decode_url(source : StringView) -> String {
  decode_url_impl(source, true)
}

///|
fn decode_url_path(source : StringView) -> String {
  decode_url_impl(source, false)
}

///|
pub fn url_decode(source : String) -> String {
  decode_url(source)
}

///|
fn is_url_unreserved(value : Int32) -> Bool {
  (value >= 48 && value <= 57) ||
  (value >= 65 && value <= 90) ||
  (value >= 97 && value <= 122) ||
  value == 45 ||
  value == 46 ||
  value == 95 ||
  value == 126
}

///|
fn percent_hex_byte(value : Int) -> Byte {
  if value < 10 {
    (b'0'.to_int() + value).to_byte()
  } else {
    (b'A'.to_int() + (value - 10)).to_byte()
  }
}

///|
fn write_percent_to(out : FixedArray[Byte], offset : Int, value : Int) -> Unit {
  out[offset] = b'%'
  out[offset + 1] = percent_hex_byte(value / 16)
  out[offset + 2] = percent_hex_byte(value % 16)
}

///|
pub fn url_encode(source : String) -> String {
  let view = source.view()
  let length = view.length()
  let mut start = 0
  while start < length && is_url_unreserved(view.unsafe_get(start).to_int()) {
    start = start + 1
  }
  if start == length {
    return source
  }
  let mut out_len = start
  let mut i = start
  while i < length {
    let code = view.unsafe_get(i).to_int()
    if code < 0x80 {
      out_len = out_len + (if is_url_unreserved(code) { 1 } else { 3 })
    } else if code < 0x800 {
      out_len = out_len + 6
    } else if code >= 0xD800 && code <= 0xDBFF && i + 1 < length {
      let low = view.unsafe_get(i + 1).to_int()
      if low >= 0xDC00 && low <= 0xDFFF {
        out_len = out_len + 12
        i = i + 2
        continue
      }
      out_len = out_len + 9
    } else {
      out_len = out_len + 9
    }
    i = i + 1
  }
  let out = FixedArray::make(out_len, b' ')
  let mut p = 0
  while p < start {
    out[p] = view.unsafe_get(p).to_int().to_byte()
    p = p + 1
  }
  let mut out_index = start
  let mut j = start
  while j < length {
    let code = view.unsafe_get(j).to_int()
    if code < 0x80 {
      if is_url_unreserved(code) {
        out[out_index] = code.to_byte()
        out_index = out_index + 1
      } else {
        write_percent_to(out, out_index, code)
        out_index = out_index + 3
      }
    } else if code < 0x800 {
      write_percent_to(out, out_index, 0xC0 | (code >> 6))
      write_percent_to(out, out_index + 3, 0x80 | (code & 0x3F))
      out_index = out_index + 6
    } else if code >= 0xD800 && code <= 0xDBFF {
      if j + 1 < length {
        let low = view.unsafe_get(j + 1).to_int()
        if low >= 0xDC00 && low <= 0xDFFF {
          let scalar = ((code - 0xD800) << 10) + (low - 0xDC00) + 0x10000
          write_percent_to(out, out_index, 0xF0 | (scalar >> 18))
          write_percent_to(out, out_index + 3, 0x80 | ((scalar >> 12) & 0x3F))
          write_percent_to(out, out_index + 6, 0x80 | ((scalar >> 6) & 0x3F))
          write_percent_to(out, out_index + 9, 0x80 | (scalar & 0x3F))
          out_index = out_index + 12
          j = j + 2
          continue
        }
      }
      write_percent_to(out, out_index, 0xEF)
      write_percent_to(out, out_index + 3, 0xBF)
      write_percent_to(out, out_index + 6, 0xBD)
      out_index = out_index + 9
    } else if code >= 0xDC00 && code <= 0xDFFF {
      write_percent_to(out, out_index, 0xEF)
      write_percent_to(out, out_index + 3, 0xBF)
      write_percent_to(out, out_index + 6, 0xBD)
      out_index = out_index + 9
    } else {
      write_percent_to(out, out_index, 0xE0 | (code >> 12))
      write_percent_to(out, out_index + 3, 0x80 | ((code >> 6) & 0x3F))
      write_percent_to(out, out_index + 6, 0x80 | (code & 0x3F))
      out_index = out_index + 9
    }
    j = j + 1
  }
  @utf8.decode_lossy(out.unsafe_reinterpret_as_bytes()[:out_index])
}

///|
let base64_alphabet : Bytes = b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"

///|
fn base64_value(value : UInt16) -> Int {
  let code = value.to_int()
  if code >= 65 && code <= 90 {
    code - 65
  } else if code >= 97 && code <= 122 {
    code - 71
  } else if code >= 48 && code <= 57 {
    code + 4
  } else if code == 43 {
    62
  } else if code == 47 {
    63
  } else {
    -1
  }
}

///|
/// Encode bytes with the standard base64 alphabet, including padding.
pub fn base64_encode(data : Bytes) -> String {
  let length = data.length()
  if length == 0 {
    return ""
  }
  let alphabet = base64_alphabet
  let out = FixedArray::make((length + 2) / 3 * 4, b'=')
  let mut i = 0
  let mut out_index = 0
  while i + 3 <= length {
    let value = (data[i].to_int() << 16) |
      (data[i + 1].to_int() << 8) |
      data[i + 2].to_int()
    out[out_index] = alphabet[(value >> 18) & 63]
    out[out_index + 1] = alphabet[(value >> 12) & 63]
    out[out_index + 2] = alphabet[(value >> 6) & 63]
    out[out_index + 3] = alphabet[value & 63]
    i = i + 3
    out_index = out_index + 4
  }
  let remaining = length - i
  if remaining == 1 {
    let value = data[i].to_int() << 16
    out[out_index] = alphabet[(value >> 18) & 63]
    out[out_index + 1] = alphabet[(value >> 12) & 63]
  } else if remaining == 2 {
    let value = (data[i].to_int() << 16) | (data[i + 1].to_int() << 8)
    out[out_index] = alphabet[(value >> 18) & 63]
    out[out_index + 1] = alphabet[(value >> 12) & 63]
    out[out_index + 2] = alphabet[(value >> 6) & 63]
  }
  @utf8.decode_lossy(out.unsafe_reinterpret_as_bytes())
}

///|
/// Hand `length` leading bytes of `out` over as an owned `Bytes`.
fn own_bytes_prefix(out : FixedArray[Byte], length : Int) -> Bytes {
  if length == out.length() {
    out.unsafe_reinterpret_as_bytes()
  } else {
    Bytes::from_array(out[:length])
  }
}

///|
/// Decode standard base64 text. Returns `None` for malformed input.
///
/// Padding may be omitted, but a stray `=` in the middle of the text is
/// rejected.
pub fn base64_decode(text : String) -> Bytes? {
  base64_decode_view(text.view())
}

///|
/// `base64_decode` for a `StringView`.
fn base64_decode_view(view : StringView) -> Bytes? {
  let length = view.length()
  if length == 0 {
    return Some(b"")
  }
  if length % 4 == 1 {
    return None
  }
  let full_groups = length / 4
  let remainder = length % 4
  let mut out_len = full_groups * 3
  if remainder == 2 {
    out_len = out_len + 1
  } else if remainder == 3 {
    out_len = out_len + 2
  } else if view.unsafe_get(length - 1) == ('=' : UInt16) {
    out_len = out_len - 1
    if view.unsafe_get(length - 2) == ('=' : UInt16) {
      out_len = out_len - 1
    }
  }
  let out = FixedArray::make(out_len, b' ')
  let mut i = 0
  let mut out_index = 0
  while i < length {
    let remaining = length - i
    let first = base64_value(view.unsafe_get(i))
    let second = if remaining >= 2 {
      base64_value(view.unsafe_get(i + 1))
    } else {
      -1
    }
    if first < 0 || second < 0 {
      return None
    }
    out[out_index] = ((first << 2) | (second >> 4)).to_byte()
    out_index = out_index + 1
    if remaining <= 2 {
      return Some(own_bytes_prefix(out, out_index))
    }
    let third_raw = view.unsafe_get(i + 2)
    if remaining == 3 {
      if third_raw == ('=' : UInt16) {
        return None
      }
      let third = base64_value(third_raw)
      if third < 0 {
        return None
      }
      out[out_index] = (((second & 15) << 4) | (third >> 2)).to_byte()
      out_index = out_index + 1
      return Some(own_bytes_prefix(out, out_index))
    }
    if third_raw == ('=' : UInt16) {
      if view.unsafe_get(i + 3) != ('=' : UInt16) || remaining != 4 {
        return None
      }
      return Some(own_bytes_prefix(out, out_index))
    }
    let third = base64_value(third_raw)
    if third < 0 {
      return None
    }
    out[out_index] = (((second & 15) << 4) | (third >> 2)).to_byte()
    out_index = out_index + 1
    let fourth_raw = view.unsafe_get(i + 3)
    if fourth_raw == ('=' : UInt16) {
      if remaining != 4 {
        return None
      }
      return Some(own_bytes_prefix(out, out_index))
    }
    let fourth = base64_value(fourth_raw)
    if fourth < 0 {
      return None
    }
    out[out_index] = (((third & 3) << 6) | fourth).to_byte()
    out_index = out_index + 1
    i = i + 4
  }
  Some(own_bytes_prefix(out, out_index))
}

///|
fn has_ascii_upper(view : StringView) -> Bool {
  let length = view.length()
  let mut i = 0
  while i < length {
    let value = view.unsafe_get(i)
    if value >= ('A' : UInt16) && value <= ('Z' : UInt16) {
      return true
    }
    i = i + 1
  }
  false
}

///|
fn starts_with_ignore_ascii_case(
  view : StringView,
  prefix : StringView,
) -> Bool {
  let length = prefix.length()
  if view.length() < length {
    return false
  }
  let mut i = 0
  while i < length {
    let left = view.unsafe_get(i)
    let right = prefix.unsafe_get(i)
    if left != right {
      let mut left_code = left.to_int()
      let mut right_code = right.to_int()
      if left_code >= 65 && left_code <= 90 {
        left_code = left_code + 32
      }
      if right_code >= 65 && right_code <= 90 {
        right_code = right_code + 32
      }
      if left_code != right_code {
        return false
      }
    }
    i = i + 1
  }
  true
}

///|
let mime_table : Map[String, String] = Map([
  ("html", "text/html; charset=utf-8"),
  ("htm", "text/html; charset=utf-8"),
  ("css", "text/css; charset=utf-8"),
  ("js", "text/javascript; charset=utf-8"),
  ("mjs", "text/javascript; charset=utf-8"),
  ("json", "application/json; charset=utf-8"),
  ("map", "application/json; charset=utf-8"),
  ("webmanifest", "application/manifest+json; charset=utf-8"),
  ("yaml", "application/yaml; charset=utf-8"),
  ("yml", "application/yaml; charset=utf-8"),
  ("toml", "application/toml; charset=utf-8"),
  ("txt", "text/plain; charset=utf-8"),
  ("text", "text/plain; charset=utf-8"),
  ("log", "text/plain; charset=utf-8"),
  ("md", "text/markdown; charset=utf-8"),
  ("markdown", "text/markdown; charset=utf-8"),
  ("csv", "text/csv; charset=utf-8"),
  ("xml", "application/xml"),
  ("svg", "image/svg+xml"),
  ("png", "image/png"),
  ("jpg", "image/jpeg"),
  ("jpeg", "image/jpeg"),
  ("gif", "image/gif"),
  ("webp", "image/webp"),
  ("avif", "image/avif"),
  ("bmp", "image/bmp"),
  ("ico", "image/x-icon"),
  ("wasm", "application/wasm"),
  ("pdf", "application/pdf"),
  ("zip", "application/zip"),
  ("gz", "application/gzip"),
  ("mp3", "audio/mpeg"),
  ("wav", "audio/wav"),
  ("ogg", "audio/ogg"),
  ("mp4", "video/mp4"),
  ("webm", "video/webm"),
  ("mov", "video/quicktime"),
  ("woff", "font/woff"),
  ("woff2", "font/woff2"),
  ("ttf", "font/ttf"),
  ("otf", "font/otf"),
  ("eot", "application/vnd.ms-fontobject"),
  ("tif", "image/tiff"),
  ("tiff", "image/tiff"),
  ("heic", "image/heic"),
  ("heif", "image/heif"),
  ("apng", "image/apng"),
  ("psd", "image/vnd.adobe.photoshop"),
  ("aac", "audio/aac"),
  ("flac", "audio/flac"),
  ("m4a", "audio/mp4"),
  ("opus", "audio/ogg"),
  ("mid", "audio/midi"),
  ("midi", "audio/midi"),
  ("mpeg", "video/mpeg"),
  ("mpg", "video/mpeg"),
  ("avi", "video/x-msvideo"),
  ("mkv", "video/x-matroska"),
  ("3gp", "video/3gpp"),
  ("ts", "video/mp2t"),
  ("m3u8", "application/vnd.apple.mpegurl"),
  ("xhtml", "application/xhtml+xml"),
  ("rss", "application/rss+xml"),
  ("atom", "application/atom+xml"),
  ("epub", "application/epub+zip"),
  ("doc", "application/msword"),
  (
    "docx",
    "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
  ),
  ("xls", "application/vnd.ms-excel"),
  (
    "xlsx",
    "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
  ),
  ("ppt", "application/vnd.ms-powerpoint"),
  (
    "pptx",
    "application/vnd.openxmlformats-officedocument.presentationml.presentation",
  ),
  ("odt", "application/vnd.oasis.opendocument.text"),
  ("ods", "application/vnd.oasis.opendocument.spreadsheet"),
  ("odp", "application/vnd.oasis.opendocument.presentation"),
  ("rtf", "application/rtf"),
  ("7z", "application/x-7z-compressed"),
  ("rar", "application/vnd.rar"),
  ("tar", "application/x-tar"),
  ("xz", "application/x-xz"),
  ("bz2", "application/x-bzip2"),
  ("zst", "application/zstd"),
  ("ics", "text/calendar"),
  ("vtt", "text/vtt"),
  ("sh", "application/x-sh"),
  ("sql", "application/sql"),
  ("ini", "text/plain; charset=utf-8"),
  ("conf", "text/plain; charset=utf-8"),
])

///|
fn mime_for_extension(extension : StringView) -> String {
  match mime_table.get_from_string(extension) {
    Some(value) => value
    None => "application/octet-stream"
  }
}

///|
pub fn mime_type_for(path : String) -> String {
  let view = path.view()
  let mut dot = -1
  let mut i = view.length() - 1
  while i >= 0 {
    let code = view.unsafe_get(i)
    if code == ('.' : UInt16) {
      dot = i
      break
    }
    if code == ('/' : UInt16) {
      break
    }
    i = i - 1
  }
  if dot >= 0 {
    let extension = view[dot + 1:]
    if has_ascii_upper(extension) {
      mime_for_extension(extension.to_lower().view())
    } else {
      mime_for_extension(extension)
    }
  } else {
    mime_for_extension("")
  }
}

///|
/// Estimated capacity for a url-encoded result map, based on the source length.
fn urlencoded_capacity(source : StringView) -> Int {
  let estimate = source.length() >> 3
  if estimate < 4 {
    4
  } else if estimate > 8 {
    8
  } else {
    estimate
  }
}

///|
fn parse_urlencoded_view(source : StringView) -> Map[String, String] {
  let result : Map[String, String] = Map([], capacity=urlencoded_capacity(source))
  let length = source.length()
  let mut pos = 0
  while pos <= length {
    let mut end = pos
    let mut eq = -1
    while end < length {
      let code = source.unsafe_get(end)
      if code == ('&' : UInt16) {
        break
      }
      if code == ('=' : UInt16) && eq < 0 {
        eq = end
      }
      end = end + 1
    }
    if end > pos {
      if eq >= 0 {
        let key = decode_url(source[pos:eq])
        let value = decode_url(source[eq + 1:end])
        result.set(key, value)
      } else {
        result.set(decode_url(source[pos:end]), "")
      }
    }
    if end >= length {
      break
    }
    pos = end + 1
  }
  result
}

///|
pub fn parse_urlencoded(source : String) -> Map[String, String] {
  parse_urlencoded_view(source)
}

///|
/// Parse a url-encoded source into every value of each key, preserving the
/// order in which the pairs appear.
fn parse_urlencoded_multi(source : StringView) -> Map[String, Array[String]] {
  let result : Map[String, Array[String]] = Map(
    [],
    capacity=urlencoded_capacity(source),
  )
  let length = source.length()
  let mut pos = 0
  while pos <= length {
    let mut end = pos
    let mut eq = -1
    while end < length {
      let code = source.unsafe_get(end)
      if code == ('&' : UInt16) {
        break
      }
      if code == ('=' : UInt16) && eq < 0 {
        eq = end
      }
      end = end + 1
    }
    if end > pos {
      let key = if eq >= 0 {
        decode_url(source[pos:eq])
      } else {
        decode_url(source[pos:end])
      }
      let value = if eq >= 0 { decode_url(source[eq + 1:end]) } else { "" }
      match result.get(key) {
        Some(values) => values.push(value)
        None => result.set(key, [value])
      }
    }
    if end >= length {
      break
    }
    pos = end + 1
  }
  result
}

///|
fn query_key_matches(
  source : StringView,
  start : Int,
  end : Int,
  name : StringView,
) -> Bool {
  let name_length = name.length()
  if end - start == name_length {
    let mut i = start
    let mut j = 0
    let mut equal = true
    while j < name_length {
      if source.unsafe_get(i) != name.unsafe_get(j) {
        equal = false
        break
      }
      i = i + 1
      j = j + 1
    }
    if equal {
      return true
    }
  }
  let key = source[start:end]
  if !key.contains("%") && !key.contains("+") {
    return false
  }
  name.equal_to_string(decode_url(key))
}

///|
/// Whether a parameter name contains a character (`%` or `+`) whose spelling
/// changes between the raw key text and the decoded key. Names without one can
/// be looked up in the parsed map directly; names with one must also be
/// compared against the raw key text, which is what `query_param_opt` does.
fn name_needs_raw(name : StringView) -> Bool {
  let length = name.length()
  let mut i = 0
  while i < length {
    let code = name.unsafe_get(i)
    if code == ('%' : UInt16) || code == ('+' : UInt16) {
      return true
    }
    i = i + 1
  }
  false
}

///|
/// Find the value of `name` in the raw query or form source, comparing each
/// key against both its raw and its decoded spelling. The last matching pair
/// wins, mirroring `parse_urlencoded_view`. Returns `None` when no pair
/// carries the parameter.
fn query_param_opt(source : StringView, name : String) -> String? {
  let name_view = name.view()
  let mut found : StringView? = None
  let length = source.length()
  let mut pos = 0
  while pos < length {
    let pair_start = pos
    let mut eq = -1
    let mut end = pos
    while end < length {
      let code = source.unsafe_get(end)
      if code == ('&' : UInt16) {
        break
      }
      if code == ('=' : UInt16) && eq < 0 {
        eq = end
      }
      end = end + 1
    }
    if end > pair_start {
      let key_end = if eq >= 0 { eq } else { end }
      if query_key_matches(source, pair_start, key_end, name_view) {
        if eq >= 0 {
          found = Some(source[eq + 1:end])
        } else {
          found = Some("")
        }
      }
    }
    pos = end + 1
  }
  match found {
    Some(value) => Some(decode_url(value))
    None => None
  }
}

///|
fn query_param(source : StringView, name : String) -> String {
  match query_param_opt(source, name) {
    Some(value) => value
    None => ""
  }
}

///|
pub fn Context::query(self : Context, name : String) -> String {
  let path = self.request.path
  match path.find("?") {
    Some(index) =>
      if name_needs_raw(name.view()) {
        query_param(path.view()[index + 1:], name)
      } else {
        match query_map_lookup(path, index).get(name) {
          Some(value) => value
          None => ""
        }
      }
    None => ""
  }
}

///|
/// Look up the query parameter `name`, returning `default` when the query
/// string does not carry the parameter. Name matching follows `Context::query`,
/// so names containing `%` or `+` also match the raw key spelling. Unlike
/// `Context::query`, a parameter that is present with an empty value is
/// returned as-is instead of being replaced by `default`.
pub fn Context::query_default(
  self : Context,
  name : String,
  default : String,
) -> String {
  match self.request.path.find("?") {
    Some(index) =>
      if name_needs_raw(name.view()) {
        match query_param_opt(self.request.path.view()[index + 1:], name) {
          Some(value) => value
          None => default
        }
      } else {
        match query_map_lookup(self.request.path, index).get(name) {
          Some(value) => value
          None => default
        }
      }
    None => default
  }
}

///|
pub fn Context::form(self : Context, name : String) -> String {
  if !self.is_form() {
    return ""
  }
  if name_needs_raw(name.view()) {
    query_param(self.request.body.view(), name)
  } else {
    match form_map_lookup(self.request.body).get(name) {
      Some(value) => value
      None => ""
    }
  }
}

///|
/// Look up the url-encoded form field `name`, returning `default` when the
/// request body is not a form or does not carry the field. Name matching
/// follows `Context::form`, so names containing `%` or `+` also match the raw
/// key spelling. A field that is present with an empty value is returned as-is
/// instead of being replaced by `default`.
pub fn Context::form_default(
  self : Context,
  name : String,
  default : String,
) -> String {
  if !self.is_form() {
    return default
  }
  if name_needs_raw(name.view()) {
    match query_param_opt(self.request.body.view(), name) {
      Some(value) => value
      None => default
    }
  } else {
    match form_map_lookup(self.request.body).get(name) {
      Some(value) => value
      None => default
    }
  }
}

///|
pub fn Context::queries(self : Context) -> Map[String, String] {
  let path = self.request.path
  match path.find("?") {
    Some(index) => query_map_lookup(path, index).copy()
    None => Map([], capacity=0)
  }
}

///|
fn collect_values(source : StringView, name : String) -> Array[String] {
  let values : Array[String] = []
  let name_view = name.view()
  let length = source.length()
  let mut pos = 0
  while pos < length {
    let pair_start = pos
    let mut eq = -1
    let mut end = pos
    while end < length {
      let code = source.unsafe_get(end)
      if code == ('&' : UInt16) {
        break
      }
      if code == ('=' : UInt16) && eq < 0 {
        eq = end
      }
      end = end + 1
    }
    if end > pair_start {
      let key_end = if eq >= 0 { eq } else { end }
      if query_key_matches(source, pair_start, key_end, name_view) {
        if eq >= 0 {
          values.push(decode_url(source[eq + 1:end]))
        } else {
          values.push("")
        }
      }
    }
    pos = end + 1
  }
  values
}

///|
/// Collect every value of a possibly repeated query parameter, in the order
/// they appear in the query string.
pub fn Context::query_values(self : Context, name : String) -> Array[String] {
  match self.request.path.find("?") {
    Some(index) =>
      if name_needs_raw(name.view()) {
        collect_values(self.request.path[index + 1:].view(), name)
      } else {
        match query_multi_lookup(self.request.path, index).get(name) {
          Some(values) => values.copy()
          None => []
        }
      }
    None => []
  }
}

///|
/// Collect every value of a possibly repeated url-encoded form field, in the
/// order they appear in the request body.
///
/// Returns an empty array when the body is not
/// `application/x-www-form-urlencoded`.
pub fn Context::form_values(self : Context, name : String) -> Array[String] {
  if !self.is_form() {
    return []
  }
  if name_needs_raw(name.view()) {
    collect_values(self.request.body.view(), name)
  } else {
    match form_values_lookup(self.request.body).get(name) {
      Some(values) => values.copy()
      None => []
    }
  }
}

///|
pub fn Context::form_map(self : Context) -> Map[String, String] {
  if !self.is_form() {
    return Map([], capacity=0)
  }
  form_map_lookup(self.request.body).copy()
}

///|
/// Most recently normalized `Content-Type` header value.
let last_content_type_header : Ref[String?] = Ref(None)
let last_content_type_value : Ref[String] = Ref("")

///|
fn parsed_content_type(header : String) -> String {
  match last_content_type_header.val {
    Some(cached_header) =>
      if physical_equal(cached_header, header) {
        return last_content_type_value.val
      }
    None => ()
  }
  let view = header.view()
  let end = match view.find(";") {
    Some(index) => index
    None => view.length()
  }
  let value = trim_ascii_space(view[:end])
  let result = if has_ascii_upper(value) {
    value.to_lower().to_owned()
  } else {
    value.to_owned()
  }
  last_content_type_header.val = Some(header)
  last_content_type_value.val = result
  result
}

///|
/// The media type of the request body, lowercased and stripped of parameters:
/// `"application/json; charset=utf-8"` becomes `"application/json"`. Returns
/// `""` when the request has no `Content-Type`.
pub fn Context::content_type(self : Context) -> String {
  parsed_content_type(self.header("Content-Type"))
}

///|
/// Whether the request body is JSON, including `+json` structured suffixes
/// such as `application/problem+json`.
pub fn Context::is_json(self : Context) -> Bool {
  let media_type = self.content_type()
  media_type == "application/json" || media_type.has_suffix("+json")
}

///|
/// Whether the request body is `application/x-www-form-urlencoded`.
pub fn Context::is_form(self : Context) -> Bool {
  self.content_type() == "application/x-www-form-urlencoded"
}

///|
/// Whether the request body is `multipart/form-data`.
pub fn Context::is_multipart(self : Context) -> Bool {
  self.content_type() == "multipart/form-data"
}

///|
pub(all) struct MultipartPart {
  name : String
  filename : String
  content_type : String
  headers : Map[String, String]
  data : String
}

///|
pub impl Eq for MultipartPart with fn equal(x, y) {
  x.name == y.name &&
  x.filename == y.filename &&
  x.content_type == y.content_type &&
  x.data == y.data
}

///|
pub impl Show for MultipartPart with fn to_string(self) {
  "@feather.MultipartPart(\{self.name}, \{self.filename}, \{self.content_type}, \{self.data})"
}

///|
pub impl Debug for MultipartPart with fn to_repr(self) {
  Repr::record({
    "name": Repr::string(self.name),
    "filename": Repr::string(self.filename),
    "content_type": Repr::string(self.content_type),
    "data": Repr::string(self.data),
  })
}

///|
pub extend MultipartPart with Eq::{not_equal, equal}

///|
pub extend MultipartPart with Show::{output, to_string}

///|
pub extend MultipartPart with Debug::{to_repr}

///|
fn find_view_from(
  haystack : StringView,
  needle : StringView,
  start : Int32,
) -> Int32? {
  let length = needle.length()
  if length == 0 {
    return Some(start)
  }
  if start > haystack.length() - length {
    return None
  }
  match haystack[start:].find(needle) {
    Some(offset) => Some(start + offset)
    None => None
  }
}

///|
/// First index at or after `start` where a part header block ends with a blank
/// line, using either CRLF or bare LF line endings: the earliest position of
/// `\r\n\r\n` or `\n\n`.
fn find_header_end(view : StringView, start : Int32) -> Int32? {
  let length = view.length()
  let mut i = start
  while i + 1 < length {
    if view.unsafe_get(i) == ('\n' : UInt16) {
      if view.unsafe_get(i + 1) == ('\n' : UInt16) {
        return Some(i)
      }
      if i > start &&
        view.unsafe_get(i - 1) == ('\r' : UInt16) &&
        view.unsafe_get(i + 1) == ('\r' : UInt16) &&
        i + 2 < length &&
        view.unsafe_get(i + 2) == ('\n' : UInt16) {
        return Some(i - 1)
      }
    }
    i = i + 1
  }
  None
}

///|
fn delimiter_is_terminated(view : StringView, after : Int32) -> Bool {
  let length = view.length()
  let mut index = after
  while index < length &&
    (view.unsafe_get(index) == (' ' : UInt16) ||
      view.unsafe_get(index) == ('\t' : UInt16)) {
    index = index + 1
  }
  if index >= length {
    return true
  }
  let code = view.unsafe_get(index)
  if code == ('\r' : UInt16) || code == ('\n' : UInt16) {
    return true
  }
  if code == ('-' : UInt16) {
    return index + 1 < length && view.unsafe_get(index + 1) == ('-' : UInt16)
  }
  false
}

///|
fn find_terminated_delimiter(
  view : StringView,
  needle : StringView,
  start : Int32,
) -> Int32? {
  let needle_length = needle.length()
  let mut search = start
  while search <= view.length() - needle_length {
    let index = match find_view_from(view, needle, search) {
      Some(index) => index
      None => return None
    }
    if delimiter_is_terminated(view, index + needle_length) {
      return Some(index)
    }
    search = index + 1
  }
  None
}

///|
fn find_view_ignore_ascii_case(
  haystack : StringView,
  needle : StringView,
  start : Int32,
) -> Int32? {
  let length = needle.length()
  if length == 0 {
    return Some(start)
  }
  let last = haystack.length() - length
  let first = needle.unsafe_get(0).to_int()
  let lower_first = if first >= 65 && first <= 90 {
    first + 32
  } else {
    first
  }
  let mut i = start
  while i <= last {
    let value = haystack.unsafe_get(i).to_int()
    let first_matches = if value == first {
      true
    } else {
      let lower_value = if value >= 65 && value <= 90 {
        value + 32
      } else {
        value
      }
      lower_value == lower_first
    }
    if first_matches {
      let mut j = 1
      let mut matched = true
      while j < length {
        let left = haystack.unsafe_get(i + j).to_int()
        let right = needle.unsafe_get(j).to_int()
        if left != right {
          let lower_left = if left >= 65 && left <= 90 { left + 32 } else { left }
          let lower_right = if right >= 65 && right <= 90 {
            right + 32
          } else {
            right
          }
          if lower_left != lower_right {
            matched = false
            break
          }
        }
        j = j + 1
      }
      if matched {
        return Some(i)
      }
    }
    i = i + 1
  }
  None
}

///|
fn is_parameter_boundary(value : UInt16) -> Bool {
  value == (' ' : UInt16) ||
  value == (';' : UInt16) ||
  value == ('\t' : UInt16)
}

///|
fn header_parameter(value : StringView, name : String) -> String? {
  let target = name.view()
  let name_length = name.length()
  let length = value.length()
  let mut start = 0
  let mut result : String? = None
  let mut done = false
  while !done {
    let index = match find_view_ignore_ascii_case(value, target, start) {
      Some(index) => index
      None => {
        done = true
        continue
      }
    }
    let after = index + name_length
    let at_boundary = index == 0 ||
      is_parameter_boundary(value.unsafe_get(index - 1))
    if at_boundary &&
      after < length &&
      value.unsafe_get(after) == ('=' : UInt16) {
      let mut pos = after + 1
      while pos < length && value.unsafe_get(pos) == (' ' : UInt16) {
        pos = pos + 1
      }
      if pos < length && value.unsafe_get(pos) == ('"' : UInt16) {
        let quoted_start = pos + 1
        let mut end = quoted_start
        while end < length && value.unsafe_get(end) != ('"' : UInt16) {
          end = end + 1
        }
        result = Some(value[quoted_start:end].to_owned())
      } else {
        let mut end = pos
        while end < length && value.unsafe_get(end) != (';' : UInt16) {
          end = end + 1
        }
        result = Some(trim_ascii_space(value[pos:end]).to_owned())
      }
      done = true
    } else {
      start = index + 1
    }
  }
  result
}

///|
/// Look up an extended parameter such as `filename*` (RFC 8187) in a header
/// value and decode its `charset'language'value` form.
///
/// Only the `UTF-8` charset is accepted; other charsets, missing separators
/// and malformed percent escapes yield `None` so the caller can fall back to
/// the plain parameter.
fn header_ext_parameter(value : StringView, name : String) -> String? {
  if find_view_from(value, "*".view(), 0) is None {
    return None
  }
  let raw = match header_parameter(value, name + "*") {
    Some(raw) => raw
    None => return None
  }
  let view = raw.view()
  let first = match view.find("'") {
    Some(index) => index
    None => return None
  }
  if !view[:first].equal_ignore_ascii_case("utf-8".view()) {
    return None
  }
  let rest = view[first + 1:]
  let second = match rest.find("'") {
    Some(index) => index
    None => return None
  }
  Some(decode_url_path(rest[second + 1:]))
}

///|
pub fn multipart_boundary(content_type : String) -> String? {
  let view = content_type.view()
  let is_multipart = starts_with_ignore_ascii_case(
    view,
    "multipart/form-data".view(),
  ) ||
    find_view_ignore_ascii_case(view, "multipart/form-data".view(), 0) is Some(_)
  if is_multipart {
    header_parameter(view, "boundary")
  } else {
    None
  }
}

///|
fn get_header_ignore_case(
  headers : Map[String, String],
  name : String,
) -> String? {
  match headers.get(name) {
    Some(value) => return Some(value)
    None => ()
  }
  let target = name.view()
  let target_length = target.length()
  for key, value in headers {
    if key.length() == target_length &&
      key.view().equal_ignore_ascii_case(target) {
      return Some(value)
    }
  }
  None
}

///|
/// Set a header under its canonical spelling, dropping any existing entry whose
/// name differs only by case so the outgoing response has exactly one of it.
fn set_header_ignore_case(
  headers : Map[String, String],
  name : String,
  value : String,
) -> Unit {
  let target = name.view()
  let target_length = target.length()
  let mut stale : String? = None
  if !headers.contains(name) {
    for key in headers.keys() {
      if key.length() == target_length &&
        key.view().equal_ignore_ascii_case(target) {
        stale = Some(key)
        break
      }
    }
  }
  match stale {
    Some(key) => ignore(headers.remove(key))
    None => ()
  }
  headers.set(name, value)
}

///|
/// Remove a header by name regardless of case. Returns whether one was found.
fn remove_header_ignore_case(
  headers : Map[String, String],
  name : String,
) -> Bool {
  if headers.remove_and_get(name) is Some(_) {
    return true
  }
  let target = name.view()
  let target_length = target.length()
  let mut stale : String? = None
  for key in headers.keys() {
    if key.length() == target_length &&
      key.view().equal_ignore_ascii_case(target) {
      stale = Some(key)
      break
    }
  }
  match stale {
    Some(key) => {
      ignore(headers.remove(key))
      true
    }
    None => false
  }
}

///|
fn parse_part_headers(
  header_text : StringView,
) -> (Map[String, String], String?, Int, String?, Int) {
  let headers : Map[String, String] = Map([], capacity=4)
  let mut disposition : String? = None
  let mut disposition_matches = 0
  let mut content_type : String? = None
  let mut content_type_matches = 0
  let length = header_text.length()
  let mut pos = 0
  while pos <= length {
    let mut end = pos
    while end < length && header_text.unsafe_get(end) != ('\n' : UInt16) {
      end = end + 1
    }
    let line_end = if end > pos &&
      header_text.unsafe_get(end - 1) == ('\r' : UInt16) {
      end - 1
    } else {
      end
    }
    let mut colon = pos
    while colon < line_end && header_text.unsafe_get(colon) != (':' : UInt16) {
      colon = colon + 1
    }
    if line_end > pos && colon < line_end {
      let name = owned_trimmed(header_text[pos:colon])
      let value = owned_trimmed(header_text[colon + 1:line_end])
      if name != "" {
        headers.set(name, value)
        if name.view().equal_ignore_ascii_case("Content-Disposition".view()) {
          disposition = Some(value)
          disposition_matches = disposition_matches + 1
        } else if name.view().equal_ignore_ascii_case("Content-Type".view()) {
          content_type = Some(value)
          content_type_matches = content_type_matches + 1
        }
      }
    }
    if end >= length {
      break
    }
    pos = end + 1
  }
  (
    headers,
    disposition,
    disposition_matches,
    content_type,
    content_type_matches,
  )
}

///|
fn skip_line_break(view : StringView, pos : Int32) -> Int32 {
  let length = view.length()
  let mut index = pos
  while index < length &&
    (view.unsafe_get(index) == (' ' : UInt16) ||
      view.unsafe_get(index) == ('\t' : UInt16)) {
    index = index + 1
  }
  if index + 1 < length &&
    view.unsafe_get(index) == ('\r' : UInt16) &&
    view.unsafe_get(index + 1) == ('\n' : UInt16) {
    index + 2
  } else if index < length && view.unsafe_get(index) == ('\n' : UInt16) {
    index + 1
  } else {
    pos
  }
}

///|
pub fn parse_multipart(
  body : String,
  content_type : String,
) -> Array[MultipartPart]? {
  let boundary = match multipart_boundary(content_type) {
    Some(boundary) if boundary != "" => boundary
    _ => return None
  }
  let delimiter = "--" + boundary
  let delimiter_view = delimiter.view()
  let delimiter_length = delimiter.length()
  let crlf_delimiter = "\r\n" + delimiter
  let crlf_delimiter_view = crlf_delimiter.view()
  let lf_delimiter = "\n" + delimiter
  let lf_delimiter_view = lf_delimiter.view()
  let view = body.view()
  let mut pos = match find_terminated_delimiter(view, delimiter_view, 0) {
    Some(index) => index + delimiter_length
    None => return Some([])
  }
  let estimate = body.length() / (crlf_delimiter.length() + 8)
  let parts : Array[MultipartPart] = Array(
    capacity=if estimate > 64 { 64 } else { estimate + 1 },
  )
  while pos <= view.length() {
    if pos + 1 < view.length() &&
      view.unsafe_get(pos) == ('-' : UInt16) &&
      view.unsafe_get(pos + 1) == ('-' : UInt16) {
      break
    }
    pos = skip_line_break(view, pos)
    let data_end = match find_terminated_delimiter(view, crlf_delimiter_view, pos) {
      Some(index) => index
      None =>
        match find_terminated_delimiter(view, lf_delimiter_view, pos) {
          Some(index) => index
          None => break
        }
    }
    // A part may carry no headers at all, in which case its blank line comes
    // immediately after the delimiter line.
    let (header_end, separator_length) = if pos + 1 < view.length() &&
      view.unsafe_get(pos) == ('\r' : UInt16) &&
      view.unsafe_get(pos + 1) == ('\n' : UInt16) {
      (pos, 2)
    } else if pos < view.length() &&
      view.unsafe_get(pos) == ('\n' : UInt16) {
      (pos, 1)
    } else {
      match find_header_end(view, pos) {
        Some(index) =>
          if view.unsafe_get(index) == ('\r' : UInt16) {
            (index, 4)
          } else {
            (index, 2)
          }
        None => break
      }
    }
    if header_end + separator_length > data_end {
      break
    }
    let (
      headers,
      tracked_disposition,
      disposition_matches,
      tracked_content_type,
      content_type_matches,
    ) = parse_part_headers(view[pos:header_end])
    let data = view[header_end + separator_length:data_end]
    let disposition = if disposition_matches == 1 {
      tracked_disposition
    } else if disposition_matches == 0 {
      None
    } else {
      get_header_ignore_case(headers, "Content-Disposition")
    }
    let name = match disposition {
      Some(disposition) => header_parameter(disposition.view(), "name").unwrap_or("")
      None => ""
    }
    let filename = match disposition {
      Some(disposition) =>
        match header_ext_parameter(disposition.view(), "filename") {
          Some(filename) => filename
          None => header_parameter(disposition.view(), "filename").unwrap_or("")
        }
      None => ""
    }
    let part_content_type = if content_type_matches == 1 {
      tracked_content_type.unwrap_or("")
    } else if content_type_matches == 0 {
      ""
    } else {
      get_header_ignore_case(headers, "Content-Type").unwrap_or("")
    }
    parts.push({
      name,
      filename,
      content_type: part_content_type,
      headers,
      data: data.to_owned(),
    })
    pos = skip_line_break(view, data_end) + delimiter_length
  }
  Some(parts)
}

///|
pub fn Context::multipart(self : Context) -> Array[MultipartPart] {
  if !self.is_multipart() {
    return []
  }
  match multipart_parts_lookup(self.request.body, self.header("Content-Type")) {
    Some(parts) => copy_multipart_parts(parts)
    None => []
  }
}

///|
pub fn Context::multipart_value(self : Context, name : String) -> String {
  if !self.is_multipart() {
    return ""
  }
  match multipart_parts_lookup(self.request.body, self.header("Content-Type")) {
    Some(parts) => {
      for part in parts {
        if part.filename == "" && part.name == name {
          return part.data
        }
      }
      ""
    }
    None => ""
  }
}

///|
pub fn Context::multipart_file(self : Context, name : String) -> MultipartPart? {
  for part in self.multipart() {
    if part.name == name && part.filename != "" {
      return Some(part)
    }
  }
  None
}

///|
pub fn status_text(code : Int32) -> String {
  match code {
    100 => "Continue"
    101 => "Switching Protocols"
    102 => "Processing"
    103 => "Early Hints"
    200 => "OK"
    201 => "Created"
    202 => "Accepted"
    203 => "Non-Authoritative Information"
    204 => "No Content"
    205 => "Reset Content"
    206 => "Partial Content"
    207 => "Multi-Status"
    208 => "Already Reported"
    226 => "IM Used"
    300 => "Multiple Choices"
    301 => "Moved Permanently"
    302 => "Found"
    303 => "See Other"
    304 => "Not Modified"
    305 => "Use Proxy"
    307 => "Temporary Redirect"
    308 => "Permanent Redirect"
    400 => "Bad Request"
    401 => "Unauthorized"
    402 => "Payment Required"
    403 => "Forbidden"
    404 => "Not Found"
    405 => "Method Not Allowed"
    406 => "Not Acceptable"
    407 => "Proxy Authentication Required"
    408 => "Request Timeout"
    409 => "Conflict"
    410 => "Gone"
    411 => "Length Required"
    412 => "Precondition Failed"
    413 => "Payload Too Large"
    414 => "URI Too Long"
    415 => "Unsupported Media Type"
    416 => "Range Not Satisfiable"
    417 => "Expectation Failed"
    418 => "I'm a Teapot"
    421 => "Misdirected Request"
    422 => "Unprocessable Entity"
    423 => "Locked"
    424 => "Failed Dependency"
    425 => "Too Early"
    426 => "Upgrade Required"
    428 => "Precondition Required"
    429 => "Too Many Requests"
    431 => "Request Header Fields Too Large"
    451 => "Unavailable For Legal Reasons"
    500 => "Internal Server Error"
    501 => "Not Implemented"
    502 => "Bad Gateway"
    503 => "Service Unavailable"
    504 => "Gateway Timeout"
    505 => "HTTP Version Not Supported"
    506 => "Variant Also Negotiates"
    507 => "Insufficient Storage"
    508 => "Loop Detected"
    510 => "Not Extended"
    511 => "Network Authentication Required"
    _ => "Unknown"
  }
}

///|
/// Number of days in `month` (1-12) of `year`, or 0 for an invalid month.
fn days_in_month(year : Int64, month : Int) -> Int {
  match month {
    1 | 3 | 5 | 7 | 8 | 10 | 12 => 31
    4 | 6 | 9 | 11 => 30
    2 =>
      if year % 4L == 0L && (year % 100L != 0L || year % 400L == 0L) {
        29
      } else {
        28
      }
    _ => 0
  }
}

///|
fn days_from_civil(year : Int64, month : Int, day : Int) -> Int64 {
  let y = if month <= 2 { year - 1 } else { year }
  let era = (if y >= 0 { y } else { y - 399 }) / 400
  let yoe = y - era * 400
  let mp = if month > 2 { month - 3 } else { month + 9 }
  let doy = (153L * mp.to_int64() + 2L) / 5L + day.to_int64() - 1L
  let doe = yoe * 365L + yoe / 4L - yoe / 100L + doy
  era * 146097L + doe - 719468L
}

///|
fn civil_from_days(days : Int64) -> (Int64, Int, Int) {
  if days < -1000000000L || days > 1000000000L {
    return civil_from_days_wide(days)
  }
  let z = days.to_int() + 719468
  let era = (if z >= 0 { z } else { z - 146096 }) / 146097
  let doe = z - era * 146097
  let yoe = (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365
  let y = yoe + era * 400
  let doy = doe - (365 * yoe + yoe / 4 - yoe / 100)
  let mp = (5 * doy + 2) / 153
  let day = doy - (153 * mp + 2) / 5 + 1
  let month = if mp < 10 { mp + 3 } else { mp - 9 }
  let year = if month <= 2 { y + 1 } else { y }
  (year.to_int64(), month, day)
}

///|
fn civil_from_days_wide(days : Int64) -> (Int64, Int, Int) {
  let z = days + 719468L
  let era = (if z >= 0 { z } else { z - 146096L }) / 146097L
  let doe = z - era * 146097L
  let yoe = (doe - doe / 1460L + doe / 36524L - doe / 146096L) / 365L
  let y = yoe + era * 400L
  let doy = doe - (365L * yoe + yoe / 4L - yoe / 100L)
  let mp = (5L * doy + 2L) / 153L
  let day = (doy - (153L * mp + 2L) / 5L + 1L).to_int()
  let month = if mp < 10L { (mp + 3L).to_int() } else { (mp - 9L).to_int() }
  let year = if month <= 2 { y + 1L } else { y }
  (year, month, day)
}

///|
let http_weekdays : Array[String] = [
  "Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat",
]

///|
let http_months : Array[String] = [
  "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov",
  "Dec",
]

///|
fn write_two_digits(builder : StringBuilder, value : Int) -> Unit {
  if value >= 0 && value < 100 {
    if value < 10 {
      builder.write_char('0')
    } else {
      builder.write_char((48 + value / 10).unsafe_to_char())
    }
    builder.write_char((48 + value % 10).unsafe_to_char())
  } else if value < 10 {
    builder.write_char('0')
    builder.write_string(value.to_string())
  } else {
    builder.write_string(value.to_string())
  }
}

///|
fn write_year(builder : StringBuilder, year : Int64) -> Unit {
  if year >= 0L && year < 10000L {
    let value = year.to_int()
    builder.write_char((48 + value / 1000).unsafe_to_char())
    builder.write_char((48 + value / 100 % 10).unsafe_to_char())
    builder.write_char((48 + value / 10 % 10).unsafe_to_char())
    builder.write_char((48 + value % 10).unsafe_to_char())
  } else {
    builder.write_string(year.to_string())
  }
}

///|
pub fn format_http_date(unix_seconds : Int64) -> String {
  let mut days = unix_seconds / 86400L
  let mut time_of_day = unix_seconds - days * 86400L
  if time_of_day < 0L {
    days = days - 1L
    time_of_day = time_of_day + 86400L
  }
  let (year, month, day) = civil_from_days(days)
  let mut weekday = (days + 4L) % 7L
  if weekday < 0L {
    weekday = weekday + 7L
  }
  let mut hour = 0
  let mut minute = 0
  let mut second = 0
  if time_of_day >= 0L && time_of_day < 86400L {
    let tod = time_of_day.to_int()
    hour = tod / 3600
    minute = tod % 3600 / 60
    second = tod % 60
  } else {
    hour = (time_of_day / 3600L).to_int()
    minute = ((time_of_day % 3600L) / 60L).to_int()
    second = (time_of_day % 60L).to_int()
  }
  let builder = StringBuilder(size_hint=29)
  builder.write_string(http_weekdays[weekday.to_int()])
  builder.write_string(", ")
  write_two_digits(builder, day)
  builder.write_char(' ')
  builder.write_string(http_months[month - 1])
  builder.write_char(' ')
  write_year(builder, year)
  builder.write_char(' ')
  write_two_digits(builder, hour)
  builder.write_char(':')
  write_two_digits(builder, minute)
  builder.write_char(':')
  write_two_digits(builder, second)
  builder.write_string(" GMT")
  builder.to_string()
}

///|
fn parse_decimal(view : StringView) -> Int? {
  let length = view.length()
  if length == 0 {
    return None
  }
  let mut value = 0
  let mut i = 0
  while i < length {
    let digit = view.unsafe_get(i).to_int() - 48
    if digit < 0 || digit > 9 {
      return None
    }
    value = value * 10 + digit
    if value > 100000000 {
      return None
    }
    i = i + 1
  }
  Some(value)
}

///|
fn month_from_name(name : StringView) -> Int? {
  let length = name.length()
  if length != 3 {
    return None
  }
  for i, month in http_months {
    if name == month.view() {
      return Some(i + 1)
    }
  }
  None
}

///|
fn parse_time_of_day(time : StringView) -> Int64? {
  let first_colon = match time.find(":") {
    Some(index) => index
    None => return None
  }
  let second_colon = match time[first_colon + 1:].find(":") {
    Some(index) => first_colon + 1 + index
    None => return None
  }
  let hour = match parse_decimal(time[:first_colon]) {
    Some(hour) => hour
    None => return None
  }
  let minute = match parse_decimal(time[first_colon + 1:second_colon]) {
    Some(minute) => minute
    None => return None
  }
  let second = match parse_decimal(time[second_colon + 1:]) {
    Some(second) => second
    None => return None
  }
  if hour > 23 || minute > 59 || second > 60 {
    return None
  }
  Some((hour * 3600 + minute * 60 + second).to_int64())
}

///|
fn imf_fixdate_two_digits(view : StringView, at : Int32) -> Int {
  let a = view.unsafe_get(at).to_int() - 48
  let b = view.unsafe_get(at + 1).to_int() - 48
  if a < 0 || a > 9 || b < 0 || b > 9 {
    return -1
  }
  a * 10 + b
}

///|
fn imf_fixdate_four_digits(view : StringView, at : Int32) -> Int {
  let a = view.unsafe_get(at).to_int() - 48
  let b = view.unsafe_get(at + 1).to_int() - 48
  let c = view.unsafe_get(at + 2).to_int() - 48
  let d = view.unsafe_get(at + 3).to_int() - 48
  if a < 0 || a > 9 || b < 0 || b > 9 || c < 0 || c > 9 || d < 0 || d > 9 {
    return -1
  }
  a * 1000 + b * 100 + c * 10 + d
}

///|
/// Parse the fixed-layout IMF-fixdate form (`Sun, 15 Jun 2025 10:20:30 GMT`)
/// without tokenizing, falling back to the general path on any deviation.
fn parse_imf_fixdate(view : StringView) -> Int64? {
  if view.length() != 29 {
    return None
  }
  if view.unsafe_get(3) != (',' : UInt16) ||
    view.unsafe_get(4) != (' ' : UInt16) ||
    view.unsafe_get(7) != (' ' : UInt16) ||
    view.unsafe_get(11) != (' ' : UInt16) ||
    view.unsafe_get(16) != (' ' : UInt16) ||
    view.unsafe_get(19) != (':' : UInt16) ||
    view.unsafe_get(22) != (':' : UInt16) ||
    view.unsafe_get(25) != (' ' : UInt16) {
    return None
  }
  // The tokenizing parser takes the RFC 1123 branch only when the first
  // whitespace-delimited token contains the comma, so a weekday with an
  // embedded space must fall back rather than parse.
  let mut weekday_start = 0
  while weekday_start < 4 &&
    view.unsafe_get(weekday_start) == (' ' : UInt16) {
    weekday_start = weekday_start + 1
  }
  let mut weekday_end = weekday_start
  while weekday_end < 4 &&
    view.unsafe_get(weekday_end) != (' ' : UInt16) {
    weekday_end = weekday_end + 1
  }
  if weekday_end != 4 {
    return None
  }
  let day = imf_fixdate_two_digits(view, 5)
  let month = match month_from_name(view[8:11]) {
    Some(month) => month
    None => return None
  }
  let year = imf_fixdate_four_digits(view, 12)
  let hour = imf_fixdate_two_digits(view, 17)
  let minute = imf_fixdate_two_digits(view, 20)
  let second = imf_fixdate_two_digits(view, 23)
  if day < 0 || year < 0 || hour < 0 || minute < 0 || second < 0 {
    return None
  }
  if day < 1 ||
    day > days_in_month(year.to_int64(), month) ||
    year < 1970 ||
    hour > 23 ||
    minute > 59 ||
    second > 60 {
    return None
  }
  Some(
    days_from_civil(year.to_int64(), month, day) *
    86400L +
    (hour * 3600 + minute * 60 + second).to_int64(),
  )
}

///|
pub fn parse_http_date(value : String) -> Int64? {
  let view = value.view()
  match parse_imf_fixdate(view) {
    Some(seconds) => return Some(seconds)
    None => ()
  }
  let length = view.length()
  let parts : FixedArray[StringView] = FixedArray::make(6, "")
  let mut count = 0
  let mut i = 0
  while i < length && count < 6 {
    while i < length && view.unsafe_get(i) == (' ' : UInt16) {
      i = i + 1
    }
    if i >= length {
      break
    }
    let start = i
    while i < length && view.unsafe_get(i) != (' ' : UInt16) {
      i = i + 1
    }
    parts[count] = view[start:i]
    count = count + 1
  }
  if count < 4 {
    return None
  }
  let mut day = 0
  let mut month = 0
  let mut year = 0L
  let mut time = parts[0]
  if parts[1].contains("-") {
    let date = parts[1]
    let first_dash = match date.find("-") {
      Some(index) => index
      None => return None
    }
    let second_dash = match date[first_dash + 1:].find("-") {
      Some(index) => first_dash + 1 + index
      None => return None
    }
    day = match parse_decimal(date[:first_dash]) {
      Some(day) => day
      None => return None
    }
    month = match month_from_name(date[first_dash + 1:second_dash]) {
      Some(month) => month
      None => return None
    }
    let year_text = date[second_dash + 1:]
    let parsed_year = match parse_decimal(year_text) {
      Some(year) => year
      None => return None
    }
    if year_text.length() == 2 {
      year = (if parsed_year < 70 { 2000 + parsed_year } else { 1900 + parsed_year }).to_int64()
    } else if year_text.length() == 4 {
      year = parsed_year.to_int64()
    } else {
      return None
    }
    time = parts[2]
  } else if parts[0].contains(",") {
    if count < 5 {
      return None
    }
    day = match parse_decimal(parts[1]) {
      Some(day) => day
      None => return None
    }
    month = match month_from_name(parts[2]) {
      Some(month) => month
      None => return None
    }
    year = match parse_decimal(parts[3]) {
      Some(year) => year.to_int64()
      None => return None
    }
    time = parts[4]
  } else {
    if count < 5 {
      return None
    }
    month = match month_from_name(parts[1]) {
      Some(month) => month
      None => return None
    }
    day = match parse_decimal(parts[2]) {
      Some(day) => day
      None => return None
    }
    time = parts[3]
    year = match parse_decimal(parts[4]) {
      Some(year) => year.to_int64()
      None => return None
    }
  }
  if day < 1 || day > days_in_month(year, month) || year < 1970 {
    return None
  }
  let seconds_of_day = match parse_time_of_day(time) {
    Some(seconds) => seconds
    None => return None
  }
  Some(days_from_civil(year, month, day) * 86400L + seconds_of_day)
}

///|
pub(all) enum ByteRange {
  ByteRangeFull
  ByteRangeSpec(Int64, Int64)
  ByteRangeInvalid
}

///|
fn etag_header_matches(value : StringView, etag : String) -> Bool {
  let etag_view = etag.view()
  let etag_opaque = if etag_view.has_prefix("W/") {
    etag_view[2:]
  } else {
    etag_view
  }
  let length = value.length()
  let mut start = 0
  let mut i = 0
  let mut in_quotes = false
  while i <= length {
    if i == length ||
      (value.unsafe_get(i) == (',' : UInt16) && !in_quotes) {
      let token = trim_ascii_space(value[start:i])
      if token == "*" {
        return true
      }
      let token_opaque = if token.has_prefix("W/") {
        token[2:]
      } else {
        token
      }
      if !token_opaque.is_empty() && token_opaque == etag_opaque {
        return true
      }
      start = i + 1
    } else if value.unsafe_get(i) == ('"' : UInt16) {
      in_quotes = !in_quotes
    }
    i = i + 1
  }
  false
}

///|
/// Whether an `If-Match` field value satisfies the strong comparison function
/// (RFC 9110 §13.1.1) against `etag`. The wildcard `*` matches any existing
/// representation; weak tags never match, because `If-Match` requires strong
/// comparison.
fn if_match_header_matches(value : StringView, etag : String) -> Bool {
  let length = value.length()
  let etag_view = etag.view()
  let etag_is_strong = etag != "" && !etag_view.has_prefix("W/")
  let mut start = 0
  let mut i = 0
  let mut in_quotes = false
  while i <= length {
    if i == length || (value.unsafe_get(i) == (',' : UInt16) && !in_quotes) {
      let token = trim_ascii_space(value[start:i])
      if token == "*" {
        return true
      }
      if etag_is_strong && !token.has_prefix("W/") && token == etag_view {
        return true
      }
      start = i + 1
    } else if value.unsafe_get(i) == ('"' : UInt16) {
      in_quotes = !in_quotes
    }
    i = i + 1
  }
  false
}

///|
/// Whether the `If-Unmodified-Since` condition holds for a representation last
/// modified at `mtime_secs`. An invalid date or an unknown modification date
/// is ignored, as is the condition for a modification exactly at the given
/// second, matching the one-second granularity of HTTP dates.
fn if_unmodified_since_ok(value : StringView, mtime_secs : Int64) -> Bool {
  if mtime_secs <= 0L {
    return true
  }
  match parse_http_date(owned_trimmed(value)) {
    Some(since) => mtime_secs <= since
    None => true
  }
}

///|
/// Result of evaluating a request's precondition headers against the selected
/// representation's validators.
priv enum PreconditionOutcome {
  PreconditionPass
  PreconditionNotModified
  PreconditionFailed
}

///|
/// Evaluate `If-Match`, `If-Unmodified-Since`, `If-None-Match` and
/// `If-Modified-Since` in the order required by RFC 9110 §13.2.2.
///
/// `etag` and `mtime_secs` describe the selected representation; either may be
/// absent (empty tag / `0`). `allows_not_modified` is true for `GET`/`HEAD`,
/// the only methods that `304 Not Modified` may be sent for.
fn evaluate_preconditions(
  request : @http.Request,
  etag : String,
  mtime_secs : Int64,
  allows_not_modified : Bool,
) -> PreconditionOutcome {
  match request.headers.get(header_if_match) {
    Some(value) =>
      if !if_match_header_matches(value.view(), etag) {
        return PreconditionFailed
      }
    None =>
      match request.headers.get(header_if_unmodified_since) {
        Some(value) =>
          if !if_unmodified_since_ok(value.view(), mtime_secs) {
            return PreconditionFailed
          }
        None => ()
      }
  }
  match request.headers.get(header_if_none_match) {
    Some(value) =>
      if etag_header_matches(value.view(), etag) {
        if allows_not_modified {
          return PreconditionNotModified
        } else {
          return PreconditionFailed
        }
      }
    None =>
      if allows_not_modified {
        match request.headers.get(header_if_modified_since) {
          Some(value) =>
            match parse_http_date(value) {
              Some(since) =>
                if mtime_secs > 0L && mtime_secs <= since {
                  return PreconditionNotModified
                }
              None => ()
            }
          None => ()
        }
      }
  }
  PreconditionPass
}

///|
pub fn Context::fresh(self : Context, etag : String) -> Bool {
  if etag == "" {
    return false
  }
  let header = self.header("If-None-Match")
  if header == "" {
    return false
  }
  etag_header_matches(header.view(), etag)
}

///|
pub fn Context::not_modified(
  self : Context,
  etag? : String,
  last_modified? : String,
) -> Unit {
  self.file = None
  self.response.status = 304
  self.response.body = ""
  self.response.data = None
  self.response.headers.remove("Content-Type")
  match etag {
    Some(etag) => self.response.headers.set("ETag", etag)
    None => ()
  }
  match last_modified {
    Some(last_modified) =>
      self.response.headers.set("Last-Modified", last_modified)
    None => ()
  }
}

///|
/// Parse a non-negative decimal byte offset into `Int64`, returning `None` for
/// empty, non-numeric or out-of-range input.
fn parse_byte_offset(view : StringView) -> Int64? {
  let length = view.length()
  if length == 0 {
    return None
  }
  let mut value = 0L
  let mut i = 0
  while i < length {
    let digit = view.unsafe_get(i).to_int() - 48
    if digit < 0 || digit > 9 {
      return None
    }
    let digit64 = digit.to_int64()
    if value > (9223372036854775807L - digit64) / 10L {
      return None
    }
    value = value * 10L + digit64
    i = i + 1
  }
  Some(value)
}

///|
pub fn parse_byte_range(value : String, total : Int64) -> ByteRange {
  let view = trim_ascii_space(value.view())
  if !starts_with_ignore_ascii_case(view, "bytes=".view()) {
    return ByteRangeFull
  }
  let spec = trim_ascii_space(view[6:])
  if spec.contains(",") {
    return ByteRangeFull
  }
  let dash = match spec.find("-") {
    Some(index) => index
    None => return ByteRangeFull
  }
  let start_text = trim_ascii_space(spec[:dash])
  let end_text = trim_ascii_space(spec[dash + 1:])
  if start_text.is_empty() {
    let suffix = match parse_byte_offset(end_text) {
      Some(suffix) => suffix
      None => return ByteRangeFull
    }
    if suffix <= 0L || total <= 0L {
      return ByteRangeInvalid
    }
    let start = if suffix >= total { 0L } else { total - suffix }
    return ByteRangeSpec(start, total - 1L)
  }
  let start = match parse_byte_offset(start_text) {
    Some(start) => start
    None => return ByteRangeFull
  }
  if end_text.is_empty() {
    if start >= total {
      return ByteRangeInvalid
    }
    return ByteRangeSpec(start, total - 1L)
  }
  let end = match parse_byte_offset(end_text) {
    Some(end) => end
    None => return ByteRangeFull
  }
  if start > end {
    return ByteRangeFull
  }
  if start >= total {
    return ByteRangeInvalid
  }
  let end = if end >= total { total - 1L } else { end }
  ByteRangeSpec(start, end)
}

///|
fn normalize_prefix(prefix : String) -> String {
  let view = prefix.view()
  let builder = StringBuilder(size_hint=view.length() + 1)
  let mut has_segment = false
  for segment in view.split("/") {
    if segment.is_empty() {
      continue
    }
    builder.write_char('/')
    builder.write_stringview(segment)
    has_segment = true
  }
  if !has_segment {
    return ""
  }
  builder.to_string()
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
}

///|
pub fn Router::group(self : Router, prefix : String) -> RouteGroup {
  { router: self, prefix: normalize_prefix(prefix), middlewares: [], }
}

///|
pub fn RouteGroup::group(self : RouteGroup, prefix : String) -> RouteGroup {
  {
    router: self.router,
    prefix: join_paths(self.prefix, prefix),
    middlewares: self.middlewares.copy(),
  }
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
  self.router.add_route(meth, join_paths(self.prefix, path), self.wrap(handler))
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
  self.router.add_named_route(
    name,
    meth,
    join_paths(self.prefix, path),
    self.wrap(handler),
  )
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
pub fn RouteGroup::all(
  self : RouteGroup,
  path : String,
  handler : Handler,
) -> RouteGroup {
  for meth in ["GET", "POST", "PUT", "PATCH", "DELETE", "HEAD", "OPTIONS"] {
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
pub(all) struct StaticMount {
  url_prefix : String
  root : String
  index : String
  max_age : Int32
  precompressed : Bool
}

///|
pub struct App {
  router : Router
  middlewares : Array[Middleware]
  mut max_body_size : Int32
  mut timeout : Int32
  mut chain : Handler?
  static_mounts : Array[StaticMount]
  mut no_route_handler : Handler?
  ws_router : Router
  ws_handlers : Map[String, WebSocketHandler]
  sse_router : Router
  sse_handlers : Map[String, SseHandler]
  stream_router : Router
  stream_handlers : Map[String, StreamHandler]
  mut compress_enabled : Bool
  mut compress_min_size : Int32
  mut etag_enabled : Bool
  static_lookup_cache : Map[String, (String, String, Bool)?]
}

///|
/// Build an application with every optional feature disabled. `timeout` is the
/// per-request timeout in milliseconds; `0` disables it.
fn App::fresh(timeout : Int32) -> App {
  {
    router: create_router(),
    middlewares: [],
    max_body_size: DEFAULT_MAX_BODY_SIZE,
    timeout,
    chain: None,
    static_mounts: [],
    no_route_handler: None,
    ws_router: create_router(),
    ws_handlers: Map([]),
    sse_router: create_router(),
    sse_handlers: Map([]),
    stream_router: create_router(),
    stream_handlers: Map([]),
    compress_enabled: false,
    compress_min_size: 1024,
    etag_enabled: false,
    static_lookup_cache: Map([]),
  }
}

///|
pub fn App::new() -> App {
  App::fresh(0)
}

///|
pub fn App::use(self : App, middleware : Middleware) -> App {
  self.middlewares.push(middleware)
  self.chain = None
  self
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
pub fn App::all(self : App, path : String, handler : Handler) -> App {
  for meth in ["GET", "POST", "PUT", "PATCH", "DELETE", "HEAD", "OPTIONS"] {
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
  self.router.group(prefix)
}

///|
pub fn App::websocket(
  self : App,
  path : String,
  handler : WebSocketHandler,
) -> App {
  let clean_path = clean_route_path(path)
  self.ws_router.add_route("GET", clean_path, fn(_ctx) { () })
  self.ws_handlers.set(clean_path, handler)
  self
}

///|
pub fn App::has_websocket(self : App, path : String) -> Bool {
  self.ws_router.is_routable("GET", path)
}

///|
/// Register a server-sent events handler for `GET path`.
///
/// The handler receives a `Sse` writer after the `200 OK` header
/// (`Content-Type: text/event-stream`) has been sent and keeps the response
/// open until it returns or calls `Sse::close`. Event streams are long-lived,
/// so they are not subject to `App::request_timeout`, and application
/// middleware registered with `App::use` does not run for them, mirroring
/// `App::websocket`. Path parameters are available through `Context::param`.
pub fn App::sse(self : App, path : String, handler : SseHandler) -> App {
  let clean_path = clean_route_path(path)
  self.sse_router.add_route("GET", clean_path, fn(_ctx) { () })
  self.sse_handlers.set(clean_path, handler)
  self
}

///|
pub fn App::has_sse(self : App, path : String) -> Bool {
  self.sse_router.is_routable("GET", path)
}

///|
pub fn App::resolve_sse(
  self : App,
  path : String,
) -> (SseHandler, Map[String, String])? {
  if self.sse_handlers.is_empty() {
    return None
  }
  match self.sse_router.route("GET", path) {
    RouteFound(route) =>
      match self.sse_handlers.get(route.path) {
        Some(handler) => Some((handler, route.params))
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
  if self.ws_handlers.is_empty() {
    return None
  }
  match self.ws_router.route("GET", path) {
    RouteFound(route) =>
      match self.ws_handlers.get(route.path) {
        Some(handler) => Some((handler, route.params))
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
/// Streams are long-lived, so they are not subject to `App::request_timeout`,
/// and application middleware registered with `App::use` does not run for
/// them, mirroring `App::websocket` and `App::sse`. Path parameters are
/// available through `Context::param`.
pub fn App::stream(self : App, path : String, handler : StreamHandler) -> App {
  let clean_path = clean_route_path(path)
  self.stream_router.add_route("GET", clean_path, fn(_ctx) { () })
  self.stream_handlers.set(clean_path, handler)
  self
}

///|
pub fn App::has_stream(self : App, path : String) -> Bool {
  self.stream_router.is_routable("GET", path)
}

///|
pub fn App::resolve_stream(
  self : App,
  path : String,
) -> (StreamHandler, Map[String, String])? {
  if self.stream_handlers.is_empty() {
    return None
  }
  match self.stream_router.route("GET", path) {
    RouteFound(route) =>
      match self.stream_handlers.get(route.path) {
        Some(handler) => Some((handler, route.params))
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
fn clean_relative_path(relative : StringView) -> String? {
  if relative.contains("\u{0}") || relative.contains("\\") {
    return None
  }
  let length = relative.length()
  let mut needs_clean = false
  let mut i = 0
  let mut at_start = true
  while i < length {
    if relative.unsafe_get(i).to_int() == 47 {
      if at_start || i + 1 == length || relative.unsafe_get(i - 1).to_int() == 47 {
        needs_clean = true
      }
      i = i + 1
    } else {
      at_start = false
      let end = segment_end(relative, i)
      let segment = relative[i:end]
      if segment == "." {
        needs_clean = true
      } else if segment == ".." {
        return None
      }
      i = end
    }
  }
  if !needs_clean {
    return Some(relative.to_owned())
  }
  let segments : Array[StringView] = []
  for segment in relative.split("/") {
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

///|
/// Serve files from `root` under `url_prefix`.
///
/// When `precompressed` is enabled, a sibling `<file>.gz` is served instead of
/// the file itself to clients that accept the `gzip` coding. Responses carry
/// `Vary: Accept-Encoding` so shared caches keep the variants apart.
pub fn App::static_files(
  self : App,
  url_prefix : String,
  root : String,
  index~ : String = "index.html",
  max_age~ : Int32 = 0,
  precompressed~ : Bool = false,
) -> App {
  let mut clean_root = root
  while clean_root.length() > 1 && clean_root.has_suffix("/") {
    clean_root = clean_root[:clean_root.length() - 1].to_owned()
  }
  self.static_mounts.push({
    url_prefix: normalize_prefix(url_prefix),
    root: clean_root,
    index,
    max_age,
    precompressed,
  })
  self.static_lookup_cache.clear()
  self
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
  let base = normalize_prefix(prefix)
  for route in child.router.routes {
    match route.handler {
      Some(handler) => {
        let wrapped = apply_middleware(child.middlewares, handler)
        self.router.add_route(route.method, join_paths(base, route.path), wrapped)
      }
      None => ()
    }
  }
  for name, named in child.router.named {
    self.router.named.set(name, {
      method: named.method,
      path: join_paths(base, named.path),
    })
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
      precompressed: mount.precompressed,
    })
  }
  self.static_lookup_cache.clear()
  for path, handler in child.ws_handlers {
    let mounted = join_paths(base, path)
    self.ws_router.add_route("GET", mounted, fn(_ctx) { () })
    self.ws_handlers.set(mounted, handler)
  }
  for path, handler in child.sse_handlers {
    let mounted = join_paths(base, path)
    self.sse_router.add_route("GET", mounted, fn(_ctx) { () })
    self.sse_handlers.set(mounted, handler)
  }
  for path, handler in child.stream_handlers {
    let mounted = join_paths(base, path)
    self.stream_router.add_route("GET", mounted, fn(_ctx) { () })
    self.stream_handlers.set(mounted, handler)
  }
  self.chain = None
  self
}

///|
fn Router::is_routable(self : Router, meth : String, path : String) -> Bool {
  match self.match_dispatch(normalize_method(meth), clean_path_view(path)) {
    DispatchFound(_) => true
    _ => false
  }
}

///|
pub fn App::has_route(self : App, meth : String, path : String) -> Bool {
  self.router.is_routable(meth, path)
}

///|
fn App::best_static_mount(
  self : App,
  path_view : StringView,
) -> StaticMount? {
  if self.static_mounts.length() == 0 {
    return None
  }
  let path_length = path_view.length()
  let mut best : StaticMount? = None
  let mut best_length = -1
  for mount in self.static_mounts {
    let prefix_view = mount.url_prefix.view()
    let prefix_length = mount.url_prefix.length()
    let matched = if prefix_length == 0 {
      true
    } else {
      path_view == prefix_view ||
      (path_length > prefix_length &&
        path_view[:prefix_length] == prefix_view &&
        path_view[prefix_length:].has_prefix("/"))
    }
    if matched && prefix_length > best_length {
      best = Some(mount)
      best_length = prefix_length
    }
  }
  best
}

///|
/// Maximum number of request paths kept by `App::static_lookup`.
const STATIC_LOOKUP_CACHE_LIMIT : Int = 256

///|
/// Resolve a static file request to its filesystem path, `Cache-Control` value
/// and precompressed-serving flag.
fn App::static_lookup(
  self : App,
  path : String,
) -> (String, String, Bool)? {
  let clean = clean_path_view(path)
  match self.static_lookup_cache.get_from_string(clean) {
    Some(cached) => cached
    None => {
      let result = self.static_lookup_uncached(clean)
      if clean.length() <= PARSE_CACHE_MAX_KEY {
        if self.static_lookup_cache.length() >= STATIC_LOOKUP_CACHE_LIMIT {
          match self.static_lookup_cache.keys().next() {
            Some(oldest) => ignore(self.static_lookup_cache.remove(oldest))
            None => ()
          }
        }
        self.static_lookup_cache.set(clean.to_owned(), result)
      }
      result
    }
  }
}

///|
/// Resolve a static file request to its filesystem path, `Cache-Control` value
/// and precompressed-serving flag in one pass over the configured mounts.
fn App::static_lookup_uncached(
  self : App,
  path_view : StringView,
) -> (String, String, Bool)? {
  match self.best_static_mount(path_view) {
    None => None
    Some(mount) => {
      let prefix_view = mount.url_prefix.view()
      let prefix_length = mount.url_prefix.length()
      let relative : StringView = if prefix_length == 0 {
        path_view
      } else if path_view == prefix_view {
        ""
      } else {
        path_view[prefix_length + 1:]
      }
      let decoded = decode_url_path(relative)
      let clean = match clean_relative_path(decoded.view()) {
        Some(clean) => clean
        None => return None
      }
      let file_path = if clean.is_empty() || decoded.has_suffix("/") {
        join_fs_path(join_fs_path(mount.root, clean), mount.index)
      } else {
        join_fs_path(mount.root, clean)
      }
      let cache_control = if mount.max_age > 0 {
        "public, max-age=" + mount.max_age.to_string()
      } else {
        ""
      }
      Some((file_path, cache_control, mount.precompressed))
    }
  }
}

///|
pub fn App::static_file_for(self : App, path : String) -> String? {
  match self.static_lookup(path) {
    Some((file_path, _, _)) => Some(file_path)
    None => None
  }
}

///|
pub fn App::static_cache_control_for(self : App, path : String) -> String {
  let path_view = clean_path_view(path)
  match self.best_static_mount(path_view) {
    Some(mount) =>
      if mount.max_age > 0 {
        "public, max-age=" + mount.max_age.to_string()
      } else {
        ""
      }
    None => ""
  }
}

///|
pub fn App::max_body_size(self : App, size : Int32) -> App {
  self.max_body_size = size
  self
}

///|
pub fn App::request_timeout(self : App, millis : Int32) -> App {
  self.timeout = millis
  self
}

///|
pub fn App::handle(self : App, ctx : Context) -> Unit raise {
  let chain = match self.chain {
    Some(chain) => chain
    None => {
      let router = self.router
      let terminal : Handler = fn(ctx) raise {
        router.dispatch_with(ctx, self.no_route_handler)
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
pub fn App::respond(self : App, request : Request) -> Response {
  let ctx = Context::new(request)
  self.handle(ctx) catch {
    HttpError(status, message) => error_response(ctx, status, message)
    HttpErrorPayload(status, message, payload) =>
      error_response_with_payload(ctx, status, message, payload)
    err => internal_error(ctx, "\{err}")
  }
  ctx.response
}

///|
/// Middleware that turns errors escaping the handler chain into responses:
/// `HttpError` / `HttpErrorPayload` become their status and JSON body, while
/// any other error becomes a `500` (and is reported through `log` when one is
/// given, since the client only sees a generic body).
pub fn middleware_recover(log? : (String) -> Unit) -> Middleware {
  fn(next) {
    fn(ctx) {
      next(ctx) catch {
        HttpError(status, message) => error_response(ctx, status, message)
        HttpErrorPayload(status, message, payload) =>
          error_response_with_payload(ctx, status, message, payload)
        err => {
          let detail = "\{err}"
          match log {
            Some(log) =>
              log(
                "\{ctx.request.method} \{ctx.request.path} failed: \{detail}",
              )
            None => ()
          }
          internal_error(ctx, detail)
        }
      }
    }
  }
}

///|
pub fn middleware_error_handler() -> Middleware {
  fn(next) {
    fn(ctx) {
      next(ctx) catch {
        HttpError(status, message) => error_response(ctx, status, message)
        HttpErrorPayload(status, message, payload) =>
          error_response_with_payload(ctx, status, message, payload)
        err => error_response(ctx, 500, "\{err}")
      }
    }
  }
}

///|
pub fn middleware_logger(
  log~ : (String) -> Unit = println,
  with_duration~ : Bool = false,
) -> Middleware {
  fn(next) {
    fn(ctx) raise {
      let started = if with_duration { @async.now() } else { 0L }
      let record = fn() {
        if with_duration {
          let elapsed = @async.now() - started
          log(
            "[\{ctx.response.status}] \{ctx.request.method} \{ctx.request.path} (\{elapsed}ms)",
          )
        } else {
          log("[\{ctx.response.status}] \{ctx.request.method} \{ctx.request.path}")
        }
      }
      next(ctx) catch {
        HttpError(status, message) => {
          ctx.response.status = status
          record()
          raise HttpError(status, message)
        }
        HttpErrorPayload(status, message, payload) => {
          ctx.response.status = status
          record()
          raise HttpErrorPayload(status, message, payload)
        }
        err => {
          ctx.response.status = 500
          record()
          raise err
        }
      }
      record()
    }
  }
}

///|
pub fn middleware_request_id(header~ : String = "X-Request-Id") -> Middleware {
  let counter = Ref(0)
  fn(next) {
    fn(ctx) raise {
      let existing = ctx.header(header)
      let id = if existing != "" {
        existing
      } else {
        match ctx.response.headers.get(header) {
          Some(value) => value
          None => {
            counter.val = counter.val + 1
            "feather-" + counter.val.to_string()
          }
        }
      }
      ctx.response.headers.set(header, id)
      ctx.state.set("request_id", id)
      next(ctx)
    }
  }
}

///|
/// Whether a comma-separated header list such as `Vary` contains `token` as a
/// complete entry, compared case-insensitively. Checking element boundaries
/// keeps `Accept` from matching an existing `Accept-Encoding` entry.
fn header_list_has_token(list : StringView, token : StringView) -> Bool {
  let length = list.length()
  let mut start = 0
  let mut i = 0
  while i <= length {
    if i == length || list.unsafe_get(i) == (',' : UInt16) {
      if trim_ascii_space(list[start:i]).equal_ignore_ascii_case(token) {
        return true
      }
      start = i + 1
    }
    i = i + 1
  }
  false
}

///|
/// Append `value` to the response's `Vary` header unless it is already listed.
pub fn Context::vary(self : Context, value : String) -> Unit {
  match get_header_ignore_case(self.response.headers, "Vary") {
    Some(existing) =>
      if !header_list_has_token(existing.view(), value.view()) {
        set_header_ignore_case(
          self.response.headers,
          "Vary",
          existing + ", " + value,
        )
      }
    None => self.response.headers.set("Vary", value)
  }
}

///|
/// Middleware that adds hardening headers to every response: `nosniff`,
/// clickjacking protection and a referrer policy by default.
///
/// Pass `hsts` to also advertise `Strict-Transport-Security` (only meaningful
/// over HTTPS) and `content_security_policy` to lock down which resources the
/// browser may load.
pub fn middleware_secure_headers(
  content_type_options~ : String = "nosniff",
  frame_options~ : String = "DENY",
  referrer_policy~ : String = "no-referrer",
  hsts? : String,
  content_security_policy? : String,
) -> Middleware {
  fn(next) {
    fn(ctx) raise {
      ctx.response.headers.set("X-Content-Type-Options", content_type_options)
      ctx.response.headers.set("X-Frame-Options", frame_options)
      ctx.response.headers.set("Referrer-Policy", referrer_policy)
      match hsts {
        Some(value) =>
          ctx.response.headers.set("Strict-Transport-Security", value)
        None => ()
      }
      match content_security_policy {
        Some(value) => ctx.response.headers.set("Content-Security-Policy", value)
        None => ()
      }
      next(ctx)
    }
  }
}

///|
/// Middleware that redirects requests that did not arrive over HTTPS.
///
/// Useful behind a TLS-terminating proxy that sets `X-Forwarded-Proto`
/// (honored by `Context::is_secure`): requests marked `http` are answered with
/// a redirect to the same URL under `https`, preserving the method, the host
/// from the `Host` header (or `host` when given) and the query string.
/// `permanent` selects `308 Permanent Redirect`; pass `permanent=false` for a
/// `307 Temporary Redirect` while testing. Requests without a usable `Host`
/// are passed through untouched so no broken `Location` is produced.
pub fn middleware_https_redirect(
  permanent~ : Bool = true,
  host? : String,
) -> Middleware {
  let status : Int32 = if permanent { 308 } else { 307 }
  let fixed_host = host
  fn(next) {
    fn(ctx) raise {
      if ctx.is_secure() {
        next(ctx)
        return
      }
      let authority = match fixed_host {
        Some(value) => value
        None => trim_ascii_space(ctx.header("Host").view()).to_owned()
      }
      if authority == "" {
        next(ctx)
        return
      }
      ctx.redirect(status, "https://" + authority + ctx.request.path)
    }
  }
}

///|
/// Middleware that lets HTML forms perform non-`POST` methods.
///
/// Browsers can only submit `GET` and `POST` forms, so frameworks commonly
/// tunnel `PUT` / `PATCH` / `DELETE` through a `POST` carrying an override:
/// the `header` (default `X-HTTP-Method-Override`) or, when the body is
/// `application/x-www-form-urlencoded`, the `field` (default `_method`).
/// Only safe, well-known methods are accepted; anything else is ignored and
/// the request stays a `POST`. Install it before the router runs, i.e. as any
/// other `App::use` middleware.
pub fn middleware_method_override(
  field~ : String = "_method",
  header~ : String = "X-HTTP-Method-Override",
) -> Middleware {
  let field_name = field
  let header_name = header
  fn(next) {
    fn(ctx) raise {
      if ctx.request.method == "POST" {
        let value = {
          let from_header = trim_ascii_space(ctx.header(header_name).view())
          if from_header.is_empty() {
            trim_ascii_space(ctx.form(field_name).view())
          } else {
            from_header
          }
        }
        if value.view().equal_ignore_ascii_case("PUT".view()) {
          ctx.request.method = "PUT"
        } else if value.view().equal_ignore_ascii_case("PATCH".view()) {
          ctx.request.method = "PATCH"
        } else if value.view().equal_ignore_ascii_case("DELETE".view()) {
          ctx.request.method = "DELETE"
        } else if value.view().equal_ignore_ascii_case("OPTIONS".view()) {
          ctx.request.method = "OPTIONS"
        }
      }
      next(ctx)
    }
  }
}

///|
pub fn middleware_cors(
  allow_origin~ : String = "*",
  allow_methods~ : String = "GET, POST, PUT, PATCH, DELETE, HEAD, OPTIONS",
  allow_headers~ : String = "*",
  expose_headers~ : String = "",
  allow_credentials~ : Bool = false,
  max_age~ : Int32 = 0,
) -> Middleware {
  fn(next) {
    fn(ctx) raise {
      let request_origin = ctx.header("Origin")
      let echo_origin = allow_origin != "*" ||
        (allow_credentials && request_origin != "")
      if echo_origin {
        let origin = if allow_origin != "*" { allow_origin } else { request_origin }
        ctx.response.headers.set("Access-Control-Allow-Origin", origin)
        ctx.vary("Origin")
      } else {
        ctx.response.headers.set("Access-Control-Allow-Origin", allow_origin)
      }
      if allow_credentials {
        ctx.response.headers.set("Access-Control-Allow-Credentials", "true")
      }
      if ctx.request.method == "OPTIONS" {
        // A real CORS preflight carries both `Origin` and
        // `Access-Control-Request-Method` and is answered here without running
        // the handler. Other OPTIONS requests (including explicit OPTIONS
        // routes) pass through to the router and are only decorated with the
        // CORS headers below.
        let preflight = request_origin != "" &&
          ctx.header("Access-Control-Request-Method") != ""
        if preflight {
          ctx.response.status = 204
          ctx.response.data = None
          ctx.response.body = ""
          ctx.response.headers.remove("Content-Type")
        } else {
          next(ctx)
        }
        ctx.response.headers.set("Access-Control-Allow-Methods", allow_methods)
        ctx.response.headers.set("Access-Control-Allow-Headers", allow_headers)
        if max_age > 0 {
          ctx.response.headers.set(
            "Access-Control-Max-Age", max_age.to_string(),
          )
        }
      } else {
        if expose_headers != "" {
          ctx.response.headers.set("Access-Control-Expose-Headers", expose_headers)
        }
        next(ctx)
      }
    }
  }
}

///|
fn basic_auth_challenge(realm : String) -> String {
  let clean = strip_control_characters(realm)
  let view = clean.view()
  let length = view.length()
  let builder = StringBuilder(size_hint=length + 24)
  builder.write_string("Basic realm=\"")
  let mut i = 0
  while i < length {
    let code = view.unsafe_get(i).to_int()
    if code == 34 || code == 92 {
      builder.write_char('\\')
    }
    builder.write_char(code.unsafe_to_char())
    i = i + 1
  }
  builder.write_char('"')
  builder.to_string()
}

///|
fn constant_time_equal(left : String, right : String) -> Bool {
  let left_view = left.view()
  let right_view = right.view()
  let left_length = left_view.length()
  let right_length = right_view.length()
  let mut difference = left_length ^ right_length
  let length = if left_length > right_length { left_length } else { right_length }
  for i = 0; i < length; i = i + 1 {
    let a = if i < left_length { left_view.unsafe_get(i) } else { 0 }
    let b = if i < right_length { right_view.unsafe_get(i) } else { 0 }
    difference = difference | (a ^ b).to_int()
  }
  difference == 0
}

///|
fn basic_auth_middleware(
  check : (String, String) -> Bool,
  realm : String,
) -> Middleware {
  fn(next) {
    fn(ctx) raise {
      let authorized = match ctx.basic_auth() {
        Some((username, password)) => check(username, password)
        None => false
      }
      if authorized {
        next(ctx)
      } else {
        ctx.file = None
        ctx.response.status = 401
        ctx.response.headers.set("WWW-Authenticate", basic_auth_challenge(realm))
        ctx.response.headers.set("Content-Type", "text/plain; charset=utf-8")
        ctx.response.data = None
        ctx.response.body = "401 Unauthorized"
      }
    }
  }
}

///|
/// Middleware that challenges requests with HTTP Basic authentication and
/// accepts credentials listed in `accounts`.
pub fn middleware_basic_auth(
  accounts : Map[String, String],
  realm~ : String = "Restricted",
) -> Middleware {
  basic_auth_middleware(fn(username, password) {
    match accounts.get(username) {
      Some(expected) => constant_time_equal(password, expected)
      None => false
    }
  }, realm)
}

///|
/// Middleware that challenges requests with HTTP Basic authentication and
/// accepts credentials approved by `check`.
pub fn middleware_basic_auth_with(
  check : (String, String) -> Bool,
  realm~ : String = "Restricted",
) -> Middleware {
  basic_auth_middleware(check, realm)
}

///|
pub(all) struct Feather {
  config : Config
  app : App
}

///|
pub fn create_feather(config : Config) -> Feather {
  { config, app: App::fresh(config.timeout) }
}

///|
pub fn Feather::use(self : Feather, middleware : Middleware) -> Feather {
  ignore(self.app.use(middleware))
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
pub fn Feather::all(self : Feather, path : String, handler : Handler) -> Feather {
  for meth in ["GET", "POST", "PUT", "PATCH", "DELETE", "HEAD", "OPTIONS"] {
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
pub fn Feather::websocket(
  self : Feather,
  path : String,
  handler : WebSocketHandler,
) -> Feather {
  ignore(self.app.websocket(path, handler))
  self
}

///|
pub fn Feather::mount(self : Feather, prefix : String, child : Feather) -> Feather {
  ignore(self.app.mount(prefix, child.app))
  self
}

///|
pub fn Feather::sse(self : Feather, path : String, handler : SseHandler) -> Feather {
  ignore(self.app.sse(path, handler))
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
) -> Feather {
  ignore(
    self.app.static_files(url_prefix, root, index~, max_age~, precompressed~),
  )
  self
}

///|
pub fn Feather::handle(self : Feather, request : Request) -> Response {
  self.app.respond(request)
}

///|
pub fn Feather::validate_body_size(self : Feather, body : String) -> Bool {
  body.length() <= self.app.max_body_size
}
