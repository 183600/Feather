///|
pub const DEFAULT_MAX_BODY_SIZE : Int32 = 1000

///|
pub const PARAM_PREFIX : String = "param:"

///|
/// Request-state key holding the registered pattern of the route that matched.
/// The prefix keeps these framework-internal keys out of ordinary application
/// state.
const ROUTE_PATTERN_STATE_KEY : String = "__feather_route_pattern"

///|
/// Request-state key holding the method of the route that matched.
const ROUTE_METHOD_STATE_KEY : String = "__feather_route_method"

///|
/// Request-state key holding the registered name of the route that matched.
const ROUTE_NAME_STATE_KEY : String = "__feather_route_name"

///|
pub(all) suberror HttpError {
  HttpError(Int32, String)
}

///|
pub(all) suberror HttpErrorPayload {
  HttpErrorPayload(Int32, String, Json)
}

///|
/// An RFC 7807 problem detail raised by a handler.
///
/// `Context::fail_problem` builds it; every dispatch path renders it as an
/// `application/problem+json` body carrying `type`, `title`, `status`,
/// `detail` and `instance`.
pub(all) suberror HttpProblem {
  HttpProblem(Int32, String, String, String, String)
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
pub type WebSocketHandler = async (Context, @websocket.Conn) -> Unit

///|
pub type SseHandler = async (Context, Sse) -> Unit

///|
pub type StreamHandler = async (Context, Stream) -> Unit

///|
pub(all) struct Route {
  path : String
  method : String
  /// Registered name, or `""` for an unnamed route.
  name : String
  params : Map[String, String]
  wildcard : String
  wildcard_name : String
  handler : Handler?
}

///|
pub struct RouteNode {
  mut handler : Handler?
  mut route_path : String
  mut route_name : String
  mut static_children : Map[String, RouteNode]?
  mut param_child : RouteNode?
  mut wildcard_child : RouteNode?
  mut has_dynamic : Bool
  mut param_names : Array[String]
  mut param_keys : Array[String]
  mut pattern_kinds : Array[Int32]
  mut route_wildcard_name : String
  mut route_wildcard_key : String
  mut exact_cache : Map[String, RouteNode]?
}

///|
pub(all) struct NamedRoute {
  method : String
  path : String
}

///|
pub(all) struct Router {
  trees : Map[String, RouteNode]
  named : Map[String, NamedRoute]
  dynamic_caches : Map[
    String,
    Map[String, (RouteNode, Map[String, String]?, String)],
  ]
  miss_caches : Map[String, Map[String, String]]
  miss_method_caches : Map[String, Map[String, Array[String]]]
  dynamic_cache_ages : Map[String, Map[String, Int32]]
  miss_cache_ages : Map[String, Map[String, Int32]]
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
    route_name: "",
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
  }
}

///|
pub fn create_router() -> Router {
  {
    trees: Map([]),
    named: Map([]),
    dynamic_caches: Map([]),
    miss_caches: Map([]),
    miss_method_caches: Map([]),
    dynamic_cache_ages: Map([]),
    miss_cache_ages: Map([]),
  }
}

///|
pub fn Context::new(request : Request) -> Context {
  let normalized_path = normalize_request_target(request.path)
  let authority = absolute_target_authority(request.path)
  let request = match authority {
    Some(authority) => {
      // An absolute-form target names the authority the request was sent to,
      // which replaces any Host header the client also supplied (RFC 9112
      // §3.2.2). The server already does this before dispatch; doing it here
      // keeps the offline `App::respond` facade consistent.
      let headers = request.headers.copy()
      set_header_ignore_case(headers, "Host", authority)
      {
        method: request.method,
        path: normalized_path,
        headers,
        body: request.body,
      }
    }
    None =>
      if normalized_path == request.path {
        request
      } else {
        {
          method: request.method,
          path: normalized_path,
          headers: request.headers,
          body: request.body,
        }
      }
  }
  {
    request,
    response: {
      status: 200,
      headers: Map([], capacity=2),
      body: "",
      data: None,
      cookies: [],
    },
    state: Map([], capacity=2),
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
/// Every method `App::all` / `RouteGroup::all` / `Feather::all` registers.
/// `CONNECT` and `TRACE` are part of HTTP/1.1 just like the usual verbs, so an
/// "all methods" route must cover them too.
fn standard_methods() -> Array[String] {
  [
    "GET",
    "POST",
    "PUT",
    "PATCH",
    "DELETE",
    "HEAD",
    "OPTIONS",
    "CONNECT",
    "TRACE",
  ]
}

///|
///|
/// Position where the path component ends: the first `?` (query) or `#`
/// (fragment), whichever comes first. Request targets normally carry no raw
/// fragment, but accepting one keeps offline requests and hand-built contexts
/// consistent with HTTP URL parsing.
fn path_head_end(path : String) -> Int32? {
  let mut end : Int32? = match path.find("?") {
    Some(index) => Some(index)
    None => None
  }
  match path.find("#") {
    Some(index) =>
      match end {
        Some(current) => if index < current { end = Some(index) }
        None => end = Some(index)
      }
    None => ()
  }
  end
}

///|
fn clean_path_view(path : String) -> StringView {
  match path_head_end(path) {
    Some(index) => path[:index]
    None => path.view()
  }
}

///|
/// Whether `code` may appear in a URI scheme (RFC 3986 §3.1).
fn is_uri_scheme_character(code : Int32) -> Bool {
  (code >= 48 && code <= 57) ||
  (code >= 65 && code <= 90) ||
  (code >= 97 && code <= 122) ||
  code == 43 ||
  code == 45 ||
  code == 46
}

///|
/// The effective request target for routing and context accessors.
///
/// Origin-form targets (`/users/1?q=x`), authority-form `CONNECT` targets and
/// the asterisk-form (`*`) are returned unchanged. An absolute-form target,
/// which HTTP/1.1 clients send to proxies (`GET http://example.com/users/1
/// HTTP/1.1`), is reduced to its path and query so routing, static lookup and
/// `Context` helpers behave exactly as they do for origin-form requests.
///
/// An absolute URI without an explicit path is the root path, so
/// `http://example.com?q=x` becomes `/?q=x`. A value that is not a valid
/// absolute URI is left untouched, letting normal routing produce the 404.
fn normalize_request_target(path : String) -> String {
  let view = path.view()
  let length = view.length()
  if length == 0 || view.unsafe_get(0) == ('/' : UInt16) {
    return path
  }
  let separator = match view.find("://") {
    Some(index) => index
    None => return path
  }
  // The scheme starts with a letter and contains only scheme characters;
  // anything else (for example `a/b://host`) is not an absolute URI.
  let first = view.unsafe_get(0).to_int()
  if !((first >= 65 && first <= 90) || (first >= 97 && first <= 122)) {
    return path
  }
  let mut i = 1
  while i < separator {
    if !is_uri_scheme_character(view.unsafe_get(i).to_int()) {
      return path
    }
    i = i + 1
  }
  let authority_start = separator + 3
  let mut path_start = authority_start
  while path_start < length {
    let code = view.unsafe_get(path_start)
    if code == ('/' : UInt16) ||
      code == ('?' : UInt16) ||
      code == ('#' : UInt16) {
      break
    }
    path_start = path_start + 1
  }
  // Require a non-empty authority so malformed targets are not turned into a
  // root request by accident.
  if path_start == authority_start {
    return path
  }
  // A non-empty authority is not enough: a malformed host, port or bracketed
  // literal must leave the target untouched rather than routing its path. Ask
  // the same parser that supplies the effective `Host` value so a value that
  // cannot name an authority is never reduced to a request path.
  if absolute_target_authority(path) is None {
    return path
  }
  if path_start >= length {
    return "/"
  }
  let code = view.unsafe_get(path_start)
  if code == ('/' : UInt16) {
    view[path_start:].to_owned()
  } else {
    // A query or fragment with no path component belongs to the root path.
    "/" + view[path_start:].to_owned()
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
      return Some({ node, wildcard_start: -1, })
    }
    return match node.wildcard_child {
      Some(child) => Some({ node: child, wildcard_start: pos, })
      None => None
    }
  }
  let end = segment_end(path, start)
  match node.static_children {
    Some(children) =>
      match static_child_for(children, path[start:end]) {
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
    Some(child) => Some({ node: child, wildcard_start: pos, })
    None => None
  }
}

///|
/// Extract the per-path bindings for `node`.
fn RouteNode::bound_values(
  self : RouteNode,
  path : StringView,
) -> (Array[String], String) {
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
      match static_child_for(children, path[start:end]) {
        Some(child) => match_static_node(child, path, end + 1)
        None => None
      }
    None => None
  }
}

///|
fn clean_route_path(path : String) -> String {
  match path_head_end(path) {
    Some(index) => path[:index].to_owned()
    None => path
  }
}

///|
/// Normalize one static route segment to the decoded spelling used for
/// matching. A route registered as `/café` therefore matches both the raw and
/// the percent-encoded request target, while a percent-encoded registration
/// such as `/caf%C3%A9` is treated as the same route. Parameters and wildcard
/// captures keep the raw request text, so `%2F` still cannot become a path
/// separator.
fn normalize_static_route_segment(segment : StringView) -> String {
  if segment.contains("%") {
    decode_url_path(segment)
  } else {
    segment.to_owned()
  }
}

///|
/// Encode a static route segment for URL generation. The stored route segment
/// is decoded first so an already percent-encoded registration is not
/// double-encoded.
fn encode_static_route_segment(segment : StringView) -> String {
  url_encode(decode_url_path(segment))
}

///|
/// Look up a static child by the decoded form of the request segment.
fn static_child_for(
  children : Map[String, RouteNode],
  segment : StringView,
) -> RouteNode? {
  if segment.contains("%") {
    children.get(decode_url_path(segment))
  } else {
    children.get_from_string(segment)
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
/// Insert a route and return the leaf node, so named registration can attach
/// the name to exactly the node it just created even when another route
/// pattern would otherwise win the generic matcher (for example a static
/// `%3Aid` sibling of a `:id` parameter).
fn Router::add_route_node(
  self : Router,
  meth : String,
  path : String,
  handler : Handler,
) -> RouteNode {
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
  let pattern_kinds : Array[Int32] = []
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
      let key = normalize_static_route_segment(segment)
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
  // An unnamed registration replaces any name a previous registration of the
  // same method and path installed.
  node.route_name = ""
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
  self.dynamic_cache_ages.remove(method_key)
  self.miss_caches.clear()
  self.miss_method_caches.clear()
  self.miss_cache_ages.clear()
  last_route_valid.val = false
  last_route_hit.val = None
  last_route_miss.val = None
  node
}

///|
/// Canonical identity of a registered route pattern, independent of spelling
/// details that share one `RouteNode`.
///
/// Empty path segments and a trailing slash are ignored, static segments use
/// their decoded spelling, parameter names are irrelevant (a re-registration
/// under `:name` replaces the node created for `:id`), and everything after a
/// wildcard is ignored because registration stops there. The result is used to
/// tie names to nodes rather than to raw path strings.
fn route_pattern_identity(path : StringView) -> String {
  let builder = StringBuilder(size_hint=path.length())
  for segment in split_segments(path) {
    if segment.has_prefix(":") {
      builder.write_char('p')
    } else if segment.has_prefix("*") {
      builder.write_char('*')
      break
    } else {
      let key = normalize_static_route_segment(segment)
      builder.write_char('s')
      builder.write_string(key.length().to_string())
      builder.write_char(':')
      builder.write_string(key)
    }
  }
  builder.to_string()
}

///|
/// Forget names attached to the route node being re-registered without one, so
/// `url_for` cannot keep generating a URL for a name whose route no longer
/// reports it through `Context::route_name`. Equivalent spellings (`/thing/`,
/// `/caf%C3%A9`, `:name` instead of `:id`, ...) are the same node and must
/// drop their old names too.
fn Router::forget_route_names(
  self : Router,
  meth : String,
  path : String,
) -> Unit {
  let method = normalize_method(meth)
  let clean_path = clean_route_path(path)
  let identity = route_pattern_identity(clean_path.view())
  let stale : Array[String] = []
  for name, named in self.named {
    if named.method == method &&
      route_pattern_identity(named.path.view()) == identity {
      stale.push(name)
    }
  }
  for name in stale {
    ignore(self.named.remove(name))
  }
}

///|
/// Register a route.
pub fn Router::add_route(
  self : Router,
  meth : String,
  path : String,
  handler : Handler,
) -> Unit {
  self.forget_route_names(meth, path)
  ignore(self.add_route_node(meth, path, handler))
}

///|
/// Register a route whose handler is wrapped in route-level middleware.
///
/// The middlewares are composed with `apply_middleware`, so the first entry is
/// the outermost layer, and run only for requests that match this route.
pub fn Router::add_route_with(
  self : Router,
  meth : String,
  path : String,
  middlewares : Array[Middleware],
  handler : Handler,
) -> Unit {
  self.add_route(meth, path, apply_middleware(middlewares, handler))
}

///|
/// Find the node carrying the canonical pattern `identity` in one method tree.
/// Named-route bookkeeping uses this to clear a name from the node it used to
/// identify when the same name is attached to a different route.
fn find_route_node_by_identity(
  node : RouteNode,
  identity : String,
) -> RouteNode? {
  if node.handler is Some(_) &&
    route_pattern_identity(node.route_path.view()) == identity {
    return Some(node)
  }
  match node.static_children {
    Some(children) =>
      for _segment, child in children {
        match find_route_node_by_identity(child, identity) {
          Some(found) => return Some(found)
          None => ()
        }
      }
    None => ()
  }
  match node.param_child {
    Some(child) =>
      match find_route_node_by_identity(child, identity) {
        Some(found) => return Some(found)
        None => ()
      }
    None => ()
  }
  match node.wildcard_child {
    Some(child) =>
      match find_route_node_by_identity(child, identity) {
        Some(found) => return Some(found)
        None => ()
      }
    None => ()
  }
  None
}

///|
/// Detach `name` from the route it currently identifies. A route may carry at
/// most one name; when another name still points at the same pattern, that
/// name becomes the route's reported name.
fn Router::detach_route_name(self : Router, name : String) -> Unit {
  let previous = match self.named.remove_and_get(name) {
    Some(previous) => previous
    None => return
  }
  let root = match self.trees.get(previous.method) {
    Some(root) => root
    None => return
  }
  let identity = route_pattern_identity(previous.path.view())
  let node = match find_route_node_by_identity(root, identity) {
    Some(node) => node
    None => return
  }
  if node.route_name != name {
    return
  }
  let mut replacement = ""
  for other, route in self.named {
    if route.method == previous.method &&
      route_pattern_identity(route.path.view()) == identity {
      replacement = other
      break
    }
  }
  node.route_name = replacement
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
  // Re-registering the same method/path replaces the route, so names attached
  // to that route must not survive and generate URLs for a different handler.
  self.forget_route_names(meth, clean_path)
  self.detach_route_name(name)
  let node = self.add_route_node(meth, clean_path, handler)
  node.route_name = name
  self.named.set(name, { method: normalize_method(meth), path: clean_path, })
}

///|
/// Named version of `Router::add_route_with`: the route can be registered with
/// route-level middleware and still be looked up by name via `Router::url_for`.
pub fn Router::add_named_route_with(
  self : Router,
  name : String,
  meth : String,
  path : String,
  middlewares : Array[Middleware],
  handler : Handler,
) -> Unit {
  let clean_path = clean_route_path(path)
  self.forget_route_names(meth, clean_path)
  self.detach_route_name(name)
  let node = self.add_route_node(
    meth,
    clean_path,
    apply_middleware(middlewares, handler),
  )
  node.route_name = name
  self.named.set(name, { method: normalize_method(meth), path: clean_path, })
}

///|
pub fn Router::route_name(self : Router, name : String) -> NamedRoute? {
  self.named.get(name)
}

///|
/// Collect `(method, path)` pairs for every node that has a handler.
fn collect_route_paths(
  node : RouteNode,
  method : String,
  out : Array[(String, String)],
) -> Unit {
  if node.handler is Some(_) {
    out.push((method, node.route_path))
  }
  match node.static_children {
    Some(children) =>
      for _segment, child in children {
        collect_route_paths(child, method, out)
      }
    None => ()
  }
  match node.param_child {
    Some(child) => collect_route_paths(child, method, out)
    None => ()
  }
  match node.wildcard_child {
    Some(child) => collect_route_paths(child, method, out)
    None => ()
  }
}

///|
/// Every route registered in the router as `(method, path)` pairs, sorted by
/// method and then by path. The paths are the registered patterns, so
/// parameter routes appear as `/users/:id` and wildcard routes as
/// `/files/*path`. Useful for startup logging, documentation and debugging.
pub fn Router::routes(self : Router) -> Array[(String, String)] {
  let out : Array[(String, String)] = []
  for method, root in self.trees {
    collect_route_paths(root, method, out)
  }
  out.sort_by(fn(a, b) {
    let by_method = a.0.lexical_compare(b.0)
    if by_method != 0 {
      by_method
    } else {
      a.1.lexical_compare(b.1)
    }
  })
  out
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
  let mut ended_with_wildcard = false
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
      ended_with_wildcard = true
      break
    } else {
      builder.write_string(encode_static_route_segment(segment))
    }
    i = skip_slashes(path, end)
  }
  if !has_segment {
    builder.write_char('/')
  } else if !ended_with_wildcard &&
    path.unsafe_get(length - 1) == ('/' : UInt16) {
    // A trailing slash is part of the registered spelling (for example the
    // canonical `/files/` directory route), so generated URLs keep it.
    builder.write_char('/')
  }
  match query {
    Some(query) => builder.write_string(encode_query_string(query))
    None => ()
  }
  Some(builder.to_string())
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
/// Rendered `Allow` header values, keyed by the joined method list.
let allow_header_values : Map[String, String] = Map([])

///|
/// Render an `Allow` header value. `HEAD` is implicit whenever `GET` is
/// allowed (RFC 9110 §9.3.2), so it is listed even when no HEAD route exists.
fn allow_header_value(allowed : Array[String]) -> String {
  if allowed.length() == 0 {
    return ""
  }
  let key = allowed.join(",")
  match allow_header_values.get(key) {
    Some(cached) => return cached
    None => ()
  }
  let rendered = render_allow_header_value(allowed)
  if allow_header_values.length() >= 128 {
    allow_header_values.clear()
  }
  allow_header_values.set(key, rendered)
  rendered
}

///|
fn render_allow_header_value(allowed : Array[String]) -> String {
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
/// Most recent method/path pair resolved for a router and its node/bindings.
/// `add_route` invalidates it.
let last_route_trees : Ref[Map[String, RouteNode]?] = Ref(None)

///|
let last_route_method : Ref[String] = Ref("")

///|
let last_route_path : Ref[String] = Ref("")

///|
let last_route_hit : Ref[(RouteNode, Map[String, String]?, String)?] = Ref(None)

///|
let last_route_valid : Ref[Bool] = Ref(false)

///|
/// Most recent method/path pair that did not resolve to a route, together with
/// the allowed methods (or `None` when no method matches).
let last_route_miss : Ref[
  (Map[String, RouteNode], String, String, Array[String]?)?,
] = Ref(None)

///|
fn Router::find_last_hit(
  self : Router,
  meth : String,
  clean_path : StringView,
) -> (RouteNode, Map[String, String]?, String)? {
  if !last_route_valid.val {
    return None
  }
  match last_route_trees.val {
    Some(trees) =>
      if physical_equal(trees, self.trees) &&
        last_route_method.val == meth &&
        last_route_path.val.view() == clean_path {
        return last_route_hit.val
      }
    None => ()
  }
  None
}

///|
fn Router::remember_last_hit(
  self : Router,
  meth : String,
  clean_path : StringView,
  hit : (RouteNode, Map[String, String]?, String),
) -> Unit {
  last_route_trees.val = Some(self.trees)
  last_route_method.val = meth
  last_route_path.val = clean_path.to_owned()
  last_route_hit.val = Some(hit)
  last_route_valid.val = true
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
) -> (RouteNode, Map[String, String]?, String)? {
  let root = match self.trees.get(tree_key) {
    Some(root) => root
    None => return None
  }
  if !root.has_dynamic {
    match root.exact_cache {
      Some(cache) =>
        match cache.get_from_string(clean_path) {
          Some(node) => return Some((node, None, ""))
          None => ()
        }
      None => ()
    }
    return match match_static_node(root, clean_path, 0) {
      Some(node) => Some((node, None, ""))
      None => None
    }
  }
  // Dynamic trees resolve every path, static or not, through the per-method
  // dispatch cache. Entries carry the extracted bindings too.
  let cache = match self.dynamic_caches.get(tree_key) {
    Some(cache) => cache
    None => {
      let cache : Map[String, (RouteNode, Map[String, String]?, String)] = Map(
        [],
        capacity=32,
      )
      self.dynamic_caches.set(tree_key, cache)
      cache
    }
  }
  let ages = match self.dynamic_cache_ages.get(tree_key) {
    Some(ages) => ages
    None => {
      let ages : Map[String, Int32] = Map([])
      self.dynamic_cache_ages.set(tree_key, ages)
      ages
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
          let (params, wildcard_value) = route_params_for(node, -1, clean_path)
          let hit = (node, params, wildcard_value)
          remember_dynamic_hit(cache, ages, clean_path, hit)
          return Some(hit)
        }
        None => ()
      }
    None => ()
  }
  match match_dynamic_node(root, clean_path, 0) {
    Some(outcome) => {
      let (params, wildcard_value) = route_params_for(
        outcome.node,
        outcome.wildcard_start,
        clean_path,
      )
      let hit = (outcome.node, params, wildcard_value)
      remember_dynamic_hit(cache, ages, clean_path, hit)
      Some(hit)
    }
    None => None
  }
}

///|
/// Maximum number of paths kept by a per-method dynamic dispatch cache.
const DYNAMIC_CACHE_LIMIT : Int32 = 256

///|
/// Insert into a per-method dynamic dispatch cache, evicting the least recently
/// used entry when the cache is full.
fn remember_dynamic_hit(
  cache : Map[String, (RouteNode, Map[String, String]?, String)],
  ages : Map[String, Int32],
  clean_path : StringView,
  hit : (RouteNode, Map[String, String]?, String),
) -> Unit {
  cache_set(cache, ages, DYNAMIC_CACHE_LIMIT, clean_path.to_owned(), hit)
}

///|
fn Router::find_node(
  self : Router,
  tree_key : String,
  clean_path : StringView,
) -> (RouteNode, Map[String, String]?, String)? {
  self.find_node_raw(tree_key, clean_path)
}

///|
/// Bindings for a dispatch hit: `None` when the node has no parameters.
fn route_params_for(
  node : RouteNode,
  wildcard_start : Int32,
  clean_path : StringView,
) -> (Map[String, String]?, String) {
  if wildcard_start < 0 && node.param_names.length() == 0 {
    (None, "")
  } else {
    let (params, wildcard_value) = extract_route_params(node, clean_path)
    (Some(params), wildcard_value)
  }
}

///|
fn bind_route_params(
  node : RouteNode,
  params : Map[String, String]?,
  ctx : Context,
) -> Unit {
  match params {
    Some(params) => {
      let names = node.param_names
      let keys = node.param_keys
      for i = 0; i < names.length(); i = i + 1 {
        match params.get(names[i]) {
          Some(value) => ctx.state.set(keys[i], value)
          None => ()
        }
      }
      if node.route_wildcard_name != "" {
        match params.get(node.route_wildcard_name) {
          Some(value) => ctx.state.set(node.route_wildcard_key, value)
          None => ()
        }
      }
    }
    None => ()
  }
}

///|
priv enum DispatchMatch {
  DispatchFound(RouteNode, Map[String, String]?, String)
  DispatchMethods(String)
  DispatchMissing
}

///|
/// The cached `Allow` header value for a method/path pair that has no route.
/// An empty string records that no method matches the path at all.
fn Router::find_miss_cache(
  self : Router,
  meth : String,
  clean_path : StringView,
) -> String? {
  match self.miss_caches.get(meth) {
    Some(cache) => cache.get_from_string(clean_path)
    None => None
  }
}

///|
/// Maximum number of method/path entries kept by the negative caches.
const MISS_CACHE_LIMIT : Int32 = 256

///|
fn Router::remember_miss(
  self : Router,
  meth : String,
  clean_path : StringView,
  allow : String,
) -> Unit {
  let cache = match self.miss_caches.get(meth) {
    Some(cache) => cache
    None => {
      let cache : Map[String, String] = Map([], capacity=16)
      self.miss_caches.set(meth, cache)
      cache
    }
  }
  let ages = match self.miss_cache_ages.get(meth) {
    Some(ages) => ages
    None => {
      let ages : Map[String, Int32] = Map([])
      self.miss_cache_ages.set(meth, ages)
      ages
    }
  }
  cache_set(cache, ages, MISS_CACHE_LIMIT, clean_path.to_owned(), allow)
}

///|
/// Cached raw method list for a method/path pair that has no route. An empty
/// array records that no method matches the path at all.
fn Router::find_miss_methods(
  self : Router,
  meth : String,
  clean_path : StringView,
) -> Array[String]? {
  match self.miss_method_caches.get(meth) {
    Some(cache) => cache.get_from_string(clean_path)
    None => None
  }
}

///|
fn Router::remember_miss_methods(
  self : Router,
  meth : String,
  clean_path : StringView,
  methods : Array[String],
) -> Unit {
  let cache = match self.miss_method_caches.get(meth) {
    Some(cache) => cache
    None => {
      let cache : Map[String, Array[String]] = Map([], capacity=16)
      self.miss_method_caches.set(meth, cache)
      cache
    }
  }
  let ages = match self.miss_cache_ages.get(meth) {
    Some(ages) => ages
    None => {
      let ages : Map[String, Int32] = Map([])
      self.miss_cache_ages.set(meth, ages)
      ages
    }
  }
  cache_set(
    cache,
    ages,
    MISS_CACHE_LIMIT,
    clean_path.to_owned(),
    methods.copy(),
  )
}

///|
fn Router::match_dispatch(
  self : Router,
  meth : String,
  clean_path : StringView,
) -> DispatchMatch {
  match self.find_last_hit(meth, clean_path) {
    Some(hit) => return DispatchFound(hit.0, hit.1, hit.2)
    None => ()
  }
  // The negative cache is consulted first. `add_route` clears both caches, so
  // a cached miss cannot outlive its removal.
  let result = match self.find_miss_cache(meth, clean_path) {
    Some(allow) =>
      if allow != "" {
        DispatchMethods(allow)
      } else {
        DispatchMissing
      }
    None =>
      match self.find_node_raw(meth, clean_path) {
        Some(hit) => DispatchFound(hit.0, hit.1, hit.2)
        None => {
          let allowed = if meth == "HEAD" {
            match self.find_node_raw("GET", clean_path) {
              Some(hit) => return DispatchFound(hit.0, hit.1, hit.2)
              None => self.allowed_methods(clean_path)
            }
          } else {
            self.allowed_methods(clean_path)
          }
          let allow = allow_header_value(allowed)
          self.remember_miss(meth, clean_path, allow)
          if allow != "" {
            DispatchMethods(allow)
          } else {
            DispatchMissing
          }
        }
      }
  }
  match result {
    DispatchFound(node, params, wildcard) => {
      self.remember_last_hit(meth, clean_path, (node, params, wildcard))
      result
    }
    _ => result
  }
}

///|
fn Router::match_route(
  self : Router,
  meth : String,
  clean_path : StringView,
) -> RouteMatch {
  match self.find_last_hit(meth, clean_path) {
    Some(hit) => return MatchFound(hit.0, hit.1, hit.2)
    None => ()
  }
  match last_route_miss.val {
    Some((trees, cached_method, cached_path, allowed)) =>
      if physical_equal(trees, self.trees) &&
        cached_method == meth &&
        cached_path.view() == clean_path {
        return match allowed {
          Some(methods) => MatchMethods(methods.copy())
          None => MatchMissing
        }
      }
    None => ()
  }
  let result = match self.find_node(meth, clean_path) {
    Some(hit) => MatchFound(hit.0, hit.1, hit.2)
    None =>
      if meth == "HEAD" {
        // `HEAD` falls back to the `GET` route before the negative cache.
        match self.find_node("GET", clean_path) {
          Some(hit) => MatchFound(hit.0, hit.1, hit.2)
          None =>
            match self.find_miss_methods(meth, clean_path) {
              Some(methods) =>
                if methods.length() > 0 {
                  MatchMethods(methods.copy())
                } else {
                  MatchMissing
                }
              None => {
                let allowed = self.allowed_methods(clean_path)
                self.remember_miss_methods(meth, clean_path, allowed)
                if allowed.length() > 0 {
                  MatchMethods(allowed)
                } else {
                  MatchMissing
                }
              }
            }
        }
      } else {
        // Fall back to the cached method list when the node lookup misses.
        match self.find_miss_methods(meth, clean_path) {
          Some(methods) =>
            if methods.length() > 0 {
              MatchMethods(methods.copy())
            } else {
              MatchMissing
            }
          None => {
            let allowed = self.allowed_methods(clean_path)
            self.remember_miss_methods(meth, clean_path, allowed)
            if allowed.length() > 0 {
              MatchMethods(allowed)
            } else {
              MatchMissing
            }
          }
        }
      }
  }
  match result {
    MatchFound(node, params, wildcard) => {
      self.remember_last_hit(meth, clean_path, (node, params, wildcard))
      result
    }
    MatchMethods(methods) => {
      last_route_miss.val = Some(
        (self.trees, meth, clean_path.to_owned(), Some(methods.copy())),
      )
      result
    }
    MatchMissing => {
      last_route_miss.val = Some(
        (self.trees, meth, clean_path.to_owned(), None),
      )
      result
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
        // A HEAD request served by a GET route reports that registered
        // method, matching `Context::route_method` and the router's own
        // dispatch identity.
        method: if meth == "HEAD" &&
          self.find_node_raw("HEAD", clean_path) is None {
          "GET"
        } else {
          meth
        },
        name: node.route_name,
        params: match params {
          // Route values are handed to callers, so keep them separate from the
          // internally cached bindings.
          Some(params) => params.copy()
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
  if self.trees.is_empty() {
    return Some({
      path: clean_path_view(path).to_owned(),
      method: normalize_method(meth),
      name: "",
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
/// Methods registered in this router, sorted. Used to describe server-wide
/// capabilities for an `OPTIONS *` request.
fn Router::registered_methods(self : Router) -> Array[String] {
  let methods : Array[String] = []
  for meth, _ in self.trees {
    methods.push(meth)
  }
  methods.sort()
  methods
}

///|
/// Answer the asterisk-form `OPTIONS *` request from RFC 9110 §9.3.7, which
/// asks about the server as a whole rather than a particular resource. The
/// response lists the methods the application knows plus `OPTIONS`, and is
/// produced here after routing found no explicit route for the literal `*`
/// target. An application fallback is therefore not consulted for this
/// server-wide request.
fn respond_server_options(ctx : Context, router : Router) -> Unit {
  let methods = router.registered_methods()
  if methods.is_empty() {
    let methods = standard_methods()
    methods.sort()
    respond_options(ctx, methods)
  } else {
    if !methods.contains("OPTIONS") {
      methods.push("OPTIONS")
    }
    methods.sort()
    respond_options(ctx, methods)
  }
}

///|
/// Methods the application can serve at all, including the implicit `GET`
/// contributed by asynchronous endpoints. Used by the server-wide `OPTIONS *`
/// reply so it does not over- or under-report when only SSE/WebSocket/stream
/// routes exist.
fn App::server_methods(self : App) -> Array[String] {
  let methods = self.router.registered_methods()
  // Static mounts also answer GET (and HEAD), even when no ordinary route is
  // registered, so they must not fall back to the full standard method list.
  if !self.static_mounts.is_empty() && !methods.contains("GET") {
    methods.push("GET")
  }
  if !self.ws_handlers.is_empty() ||
    !self.sse_handlers.is_empty() ||
    !self.stream_handlers.is_empty() {
    if !methods.contains("GET") {
      methods.push("GET")
    }
  }
  methods
}

///|
/// Whether a WebSocket route makes `path` unreachable as a `HEAD` request.
///
/// A route with the same pattern is fully shadowed. For a pattern without a
/// wildcard, the router can also check whether the literal pattern string is
/// matched by a WebSocket route: a static GET path is then shadowed by that
/// single URL, and a parameter GET route is covered by the equivalent
/// parameter or wildcard WebSocket route. A GET wildcard is only considered
/// shadowed by the same wildcard pattern, because a narrower WebSocket route
/// leaves other paths reachable.
fn App::websocket_shadows_get_path(
  self : App,
  path : StringView,
) -> Bool {
  let identity = route_pattern_identity(path)
  for pair in self.ws_router.routes() {
    let (_method, websocket_path) = pair
    if route_pattern_identity(websocket_path.view()) == identity {
      return true
    }
  }
  !path.contains("*") &&
  self.ws_router.is_routable("GET", path.to_owned())
}

///|
/// Whether the application can answer `HEAD` somewhere. Ordinary `GET` routes,
/// static mounts and SSE/streaming endpoints can; a WebSocket endpoint cannot,
/// because its only successful GET response is the upgrade handshake.
///
/// `Allow` adds `HEAD` implicitly whenever `GET` is listed, so the server-wide
/// `OPTIONS *` reply needs this distinction: a WebSocket-only application
/// advertises `GET` but must not claim `HEAD`. An ordinary `GET` route that a
/// WebSocket route shadows at the same pattern is not reachable for `HEAD`
/// either, so it does not contribute to the server-wide capability.
fn App::server_allows_head(self : App) -> Bool {
  if !self.static_mounts.is_empty() {
    return true
  }
  if !self.sse_handlers.is_empty() {
    for pair in self.sse_router.routes() {
      let (_method, path) = pair
      if !self.websocket_shadows_get_path(path.view()) {
        return true
      }
    }
  }
  if !self.stream_handlers.is_empty() {
    for pair in self.stream_router.routes() {
      let (_method, path) = pair
      if !self.websocket_shadows_get_path(path.view()) {
        return true
      }
    }
  }
  for pair in self.router.routes() {
    let (method, path) = pair
    if (method == "GET" || method == "HEAD") &&
      !self.websocket_shadows_get_path(path.view()) {
      return true
    }
  }
  false
}

///|
/// Answer `OPTIONS *` for an application, including async endpoints.
fn respond_app_server_options(ctx : Context, app : App) -> Unit {
  let methods = app.server_methods()
  if methods.is_empty() {
    let methods = standard_methods()
    methods.sort()
    respond_options(ctx, methods)
  } else {
    if !methods.contains("OPTIONS") {
      methods.push("OPTIONS")
    }
    methods.sort()
    if app.server_allows_head() {
      respond_options(ctx, methods)
    } else {
      // `respond_options` inserts `HEAD` for every listed `GET`; a WebSocket
      // endpoint accepts GET but rejects HEAD. Render the list literally and
      // drop an explicit HEAD route when a WebSocket also shadows it.
      let without_head : Array[String] = []
      for method in methods {
        if method != "HEAD" {
          without_head.push(method)
        }
      }
      respond_options_with_allow(ctx, without_head.join(", "))
    }
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
  self.dispatch_with_synthesized(ctx, fallback, None)
}

///|
/// Router dispatch with an optional handler for synthesized `OPTIONS` and
/// method-not-allowed responses, so callers can run middleware that wraps the
/// path before the automatic response is written.
fn Router::dispatch_with_synthesized(
  self : Router,
  ctx : Context,
  fallback : Handler?,
  synthesized : ((Context, String) -> Unit raise)?,
) -> Unit raise {
  let clean_path = clean_path_view(ctx.request.path)
  let meth = normalize_method(ctx.request.method)
  // A context can be dispatched more than once (for example by tests or a
  // custom router wrapper), so never let a previous match describe this one.
  // Parameter bindings use the reserved `param:` state namespace and must be
  // cleared too: otherwise a route for another method or pattern could still
  // read a parameter captured by the previous dispatch.
  ignore(ctx.state.remove(ROUTE_PATTERN_STATE_KEY))
  ignore(ctx.state.remove(ROUTE_METHOD_STATE_KEY))
  ignore(ctx.state.remove(ROUTE_NAME_STATE_KEY))
  let stale_params : Array[String] = []
  for key, _ in ctx.state {
    if key.has_prefix(PARAM_PREFIX) {
      stale_params.push(key)
    }
  }
  for key in stale_params {
    ignore(ctx.state.remove(key))
  }
  // The asterisk-form names the server, not a path. Answer it here so a
  // catch-all or parameter route cannot shadow the server-wide reply.
  if meth == "OPTIONS" && clean_path == "*" {
    respond_server_options(ctx, self)
    return
  }
  match self.match_dispatch(meth, clean_path) {
    DispatchFound(node, params, _) => {
      // A HEAD request can be served by a GET route, in which case the
      // registered method is GET even though the request method is HEAD.
      let route_method = if meth == "HEAD" &&
        self.find_node_raw("HEAD", clean_path) is None {
        "GET"
      } else {
        meth
      }
      ctx.state.set(ROUTE_PATTERN_STATE_KEY, node.route_path)
      ctx.state.set(ROUTE_METHOD_STATE_KEY, route_method)
      if node.route_name != "" {
        ctx.state.set(ROUTE_NAME_STATE_KEY, node.route_name)
      }
      bind_route_params(node, params, ctx)
      match node.handler {
        Some(handler) => handler(ctx)
        None => not_found(ctx)
      }
    }
    DispatchMethods(allow) =>
      match synthesized {
        Some(respond) => respond(ctx, allow)
        None =>
          if meth == "OPTIONS" {
            respond_options_with_allow(ctx, allow)
          } else {
            method_not_allowed_with_allow(ctx, allow)
          }
      }
    DispatchMissing =>
      if meth == "OPTIONS" && clean_path == "*" {
        respond_server_options(ctx, self)
      } else {
        match fallback {
          Some(handler) => handler(ctx)
          None => not_found(ctx)
        }
      }
  }
}

///|
fn clear_replaced_body_headers(headers : Map[String, String]) -> Unit {
  ignore(remove_header_ignore_case(headers, "Content-Length"))
  ignore(remove_header_ignore_case(headers, "Content-Encoding"))
  ignore(remove_header_ignore_case(headers, "Content-Range"))
}

///|
/// Drop representation metadata that described a body which is being replaced
/// by an error, a redirect or another empty response. Keeping an old `ETag` or
/// `Last-Modified` would let a cache reuse the validator for different bytes,
/// and an old `Content-Disposition` would turn an error body into a download.
fn clear_replaced_representation_headers(
  headers : Map[String, String],
) -> Unit {
  ignore(remove_header_ignore_case(headers, "ETag"))
  ignore(remove_header_ignore_case(headers, "Last-Modified"))
  ignore(remove_header_ignore_case(headers, "Content-Disposition"))
}

///|
/// Media type of an RFC 7807 problem-details document.
pub const PROBLEM_CONTENT_TYPE : String = "application/problem+json; charset=utf-8"

///|
/// Render an RFC 7807 problem-details document as JSON.
///
/// An empty `type_name` becomes `about:blank` and an empty `title` becomes the
/// status text, so callers only pass the fields they actually have. `detail`
/// and `instance` are omitted when empty, as the RFC allows.
pub fn build_problem_document(
  status : Int32,
  type_name : String,
  title : String,
  detail : String,
  instance : String,
) -> String {
  let body : Map[String, Json] = Map([], capacity=5)
  let kind = if type_name == "" { "about:blank" } else { type_name }
  let heading = if title == "" { status_text(status) } else { title }
  body.set("type", Json::string(kind))
  body.set("title", Json::string(heading))
  body.set("status", Json::number(status.to_double()))
  if detail != "" {
    body.set("detail", Json::string(detail))
  }
  if instance != "" {
    body.set("instance", Json::string(instance))
  }
  Json::object(body).stringify()
}

///|
/// Write an RFC 7807 problem-details response onto `ctx`.
///
/// Unlike the negotiated error helpers this always answers with
/// `application/problem+json`, because the handler asked for problem details
/// explicitly.
pub fn problem_response(
  ctx : Context,
  status : Int32,
  type_name : String,
  title : String,
  detail : String,
  instance : String,
) -> Unit {
  ctx.file = None
  ctx.response.status = status
  clear_replaced_body_headers(ctx.response.headers)
  clear_replaced_representation_headers(ctx.response.headers)
  set_header_ignore_case(
    ctx.response.headers,
    "Content-Type",
    PROBLEM_CONTENT_TYPE,
  )
  ctx.response.data = None
  ctx.response.body = build_problem_document(
    status, type_name, title, detail, instance,
  )
}

///|
/// Give `ctx` a problem-details body for `status`, keeping the negotiated
/// rendering used by every default error path: clients that ask for
/// `application/problem+json` get problem details, everyone else keeps the
/// plain rendering passed in `plain_body`.
fn negotiated_error_body(
  ctx : Context,
  status : Int32,
  plain_content_type : String,
  plain_body : String,
  plain_detail : String,
) -> Unit {
  clear_replaced_body_headers(ctx.response.headers)
  clear_replaced_representation_headers(ctx.response.headers)
  // The rendering below is chosen from `Accept`, so the response must not be
  // reused for a request with different preferences.
  ctx.vary("Accept")
  if ctx.wants_problem_details() {
    set_header_ignore_case(
      ctx.response.headers,
      "Content-Type",
      PROBLEM_CONTENT_TYPE,
    )
    ctx.response.data = None
    ctx.response.body = build_problem_document(
      status,
      "",
      status_text(status),
      plain_detail,
      "",
    )
  } else {
    set_header_ignore_case(
      ctx.response.headers,
      "Content-Type",
      plain_content_type,
    )
    ctx.response.data = None
    ctx.response.body = plain_body
  }
}

///|
pub fn not_found(ctx : Context) -> Unit {
  ctx.file = None
  ctx.response.status = 404
  negotiated_error_body(
    ctx, 404, "text/plain; charset=utf-8", "404 Not Found", "",
  )
}

///|
fn method_not_allowed_with_allow(ctx : Context, allow : String) -> Unit {
  ctx.file = None
  ctx.response.status = 405
  set_header_ignore_case(ctx.response.headers, "Allow", allow)
  negotiated_error_body(
    ctx, 405, "text/plain; charset=utf-8", "405 Method Not Allowed", "",
  )
}

///|
pub fn method_not_allowed(ctx : Context, allowed : Array[String]) -> Unit {
  method_not_allowed_with_allow(ctx, allow_header_value(allowed))
}

///|
fn respond_options_with_allow(ctx : Context, allow : String) -> Unit {
  ctx.file = None
  ctx.response.status = 204
  clear_replaced_body_headers(ctx.response.headers)
  clear_replaced_representation_headers(ctx.response.headers)
  // A 204 carries no representation, so a content type prepared for an
  // earlier response must not leak into the automatic OPTIONS answer.
  ignore(remove_header_ignore_case(ctx.response.headers, "Content-Type"))
  set_header_ignore_case(ctx.response.headers, "Allow", allow)
  ctx.response.data = None
  ctx.response.body = ""
}

///|
/// Answer an `OPTIONS` request for a path that exists under other methods with
/// `204 No Content` and an `Allow` header, without running any handler.
pub fn respond_options(ctx : Context, allowed : Array[String]) -> Unit {
  respond_options_with_allow(ctx, allow_header_value(allowed))
}

///|
/// Answer with the generic 500 body. `detail` is only recorded in request
/// state for logs and middleware; it is never sent to the client, in either
/// the plain or the problem-details rendering.
pub fn internal_error(ctx : Context, detail : String) -> Unit {
  ctx.file = None
  ctx.state.set("error", detail)
  ctx.response.status = 500
  negotiated_error_body(
    ctx, 500, "text/plain; charset=utf-8", "Internal Server Error", "",
  )
}

///|
let error_body_cache : Map[Int32, Map[String, String]] = Map([])

///|
/// Recency ticks for the cached error bodies, keyed by status and message.
let error_body_cache_ages : Map[Int32, Map[String, Int32]] = Map([])

///|
/// Cache of the problem-details rendering of the same errors, kept apart from
/// the plain bodies so one variant can never be served for the other.
let problem_body_cache : Map[Int32, Map[String, String]] = Map([])

///|
let problem_body_cache_ages : Map[Int32, Map[String, Int32]] = Map([])

///|
/// Look up `status`/`message` in `cache`, building and storing the body on a
/// miss. Bodies are dropped once the per-status map grows past eight entries
/// and the whole cache past 32 statuses; `build` renders on demand either way.
fn error_body_from_cache(
  cache : Map[Int32, Map[String, String]],
  ages_by_status : Map[Int32, Map[String, Int32]],
  status : Int32,
  message : String,
  build : () -> String,
) -> String {
  let by_message = match cache.get(status) {
    Some(by_message) => by_message
    None => {
      if cache.length() >= 32 {
        cache.clear()
        ages_by_status.clear()
      }
      let by_message : Map[String, String] = Map([], capacity=4)
      cache.set(status, by_message)
      by_message
    }
  }
  let ages = match ages_by_status.get(status) {
    Some(ages) => ages
    None => {
      let ages : Map[String, Int32] = Map([], capacity=4)
      ages_by_status.set(status, ages)
      ages
    }
  }
  match by_message.get(message) {
    Some(body) => {
      cache_touch(ages, message)
      body
    }
    None => {
      let body = build()
      if message.length() <= 128 {
        cache_set(by_message, ages, 8, message, body)
      }
      body
    }
  }
}

///|
fn cached_error_body(status : Int32, message : String) -> String {
  error_body_from_cache(
    error_body_cache,
    error_body_cache_ages,
    status,
    message,
    fn() {
      let payload : Map[String, Json] = Map([], capacity=2)
      payload.set("status", Json::number(status.to_double()))
      payload.set("error", Json::string(message))
      Json::object(payload).stringify()
    },
  )
}

///|
/// The cached problem-details rendering of `error_response` for a client that
/// prefers `application/problem+json`.
fn cached_problem_body(status : Int32, message : String) -> String {
  error_body_from_cache(
    problem_body_cache,
    problem_body_cache_ages,
    status,
    message,
    fn() {
      build_problem_document(status, "", status_text(status), message, "")
    },
  )
}

///|
pub fn error_response(ctx : Context, status : Int32, message : String) -> Unit {
  ctx.file = None
  ctx.response.status = status
  clear_replaced_body_headers(ctx.response.headers)
  clear_replaced_representation_headers(ctx.response.headers)
  ctx.vary("Accept")
  if ctx.wants_problem_details() {
    set_header_ignore_case(
      ctx.response.headers,
      "Content-Type",
      PROBLEM_CONTENT_TYPE,
    )
    ctx.response.data = None
    ctx.response.body = cached_problem_body(status, message)
  } else {
    set_header_ignore_case(
      ctx.response.headers,
      "Content-Type",
      "application/json; charset=utf-8",
    )
    ctx.response.data = None
    ctx.response.body = cached_error_body(status, message)
  }
}

///|
pub fn error_response_with_payload(
  ctx : Context,
  status : Int32,
  message : String,
  payload : Json,
) -> Unit {
  ctx.file = None
  ctx.vary("Accept")
  let problem = ctx.wants_problem_details()
  let body : Map[String, Json] = Map([], capacity=5)
  if problem {
    body.set("type", Json::string("about:blank"))
    body.set("title", Json::string(status_text(status)))
    body.set("status", Json::number(status.to_double()))
    body.set("detail", Json::string(message))
  } else {
    body.set("status", Json::number(status.to_double()))
    body.set("error", Json::string(message))
  }
  match payload {
    Json::Object(extra) =>
      for key, value in extra {
        if problem &&
          (
            key == "type" ||
            key == "title" ||
            key == "status" ||
            key == "detail" ||
            key == "instance"
          ) {
          continue
        }
        body.set(key, value)
      }
    _ =>
      // RFC 7807 requires `detail` to be a string. In problem mode it already
      // carries the error message, so keep non-object payloads in an extension
      // member instead of replacing it with arbitrary JSON.
      if problem {
        body.set("payload", payload)
      } else {
        body.set("detail", payload)
      }
  }
  ctx.response.status = status
  clear_replaced_body_headers(ctx.response.headers)
  clear_replaced_representation_headers(ctx.response.headers)
  if problem {
    set_header_ignore_case(
      ctx.response.headers,
      "Content-Type",
      PROBLEM_CONTENT_TYPE,
    )
  } else {
    set_header_ignore_case(
      ctx.response.headers,
      "Content-Type",
      "application/json; charset=utf-8",
    )
  }
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
/// Write an RFC 7807 problem-details response directly from a handler.
///
/// `title` defaults to the status text, `type_name` to `about:blank`; pass
/// `detail` for the human-readable explanation and `instance` for the URI of
/// the specific occurrence.
pub fn Context::problem(
  self : Context,
  status : Int32,
  detail : String,
  title~ : String = "",
  type_name~ : String = "",
  instance~ : String = "",
) -> Unit {
  problem_response(self, status, type_name, title, detail, instance)
}

///|
/// Raise an RFC 7807 problem detail. Every dispatch path renders it as an
/// `application/problem+json` body, so it works from handlers, route
/// middleware and mounted applications alike.
pub fn Context::fail_problem(
  self : Context,
  status : Int32,
  detail : String,
  title~ : String = "",
  type_name~ : String = "",
  instance~ : String = "",
) -> Unit raise HttpProblem {
  ignore(self)
  raise HttpProblem(status, type_name, title, detail, instance)
}

///|
/// Context state key holding a request body that is not valid UTF-8,
/// base64-encoded. Text handlers keep reading `Request::body`; binary
/// consumers read the untouched bytes through `Context::body_bytes`.
const RAW_BODY_STATE_KEY : String = "__feather_raw_body"

///|
/// Preserve the raw bytes of a request body that UTF-8 could not represent.
///
/// `Request::body` keeps the lossy text, because `@utf8.encode` refuses lone
/// surrogates and would panic if such a body were echoed into a response; the
/// untouched bytes ride along here instead.
fn attach_raw_body(ctx : Context, raw : Bytes?) -> Unit {
  match raw {
    Some(bytes) =>
      if bytes.length() > 0 {
        ctx.state.set(RAW_BODY_STATE_KEY, base64_encode(bytes))
      }
    None => ()
  }
}

///|
/// The request body as bytes, exactly as it arrived.
///
/// A body that is valid UTF-8 round-trips through `Request::body`; a body
/// that is not (image uploads, protobuf, arbitrary binary) comes back byte
/// for byte. Its length is already bounded by `App::max_body_size`.
pub fn Context::body_bytes(self : Context) -> Bytes {
  match self.state.get(RAW_BODY_STATE_KEY) {
    Some(encoded) =>
      match base64_decode(encoded) {
        Some(bytes) => bytes
        None => encode_utf8_lossy(self.request.body.view())
      }
    None => encode_utf8_lossy(self.request.body.view())
  }
}

///|
pub fn Context::json_body(self : Context) -> Json raise HttpError {
  // RFC 8259 requires UTF-8. Decode the exact request bytes rather than the
  // lossy `Request::body` text so invalid byte sequences are rejected instead
  // of quietly becoming U+FFFD and changing the document.
  let bytes = self.body_bytes()
  let text = @utf8.decode(bytes) catch {
    @utf8.Malformed(_) => raise HttpError(400, "invalid JSON body")
  }
  // RFC 8259 allows parsers to ignore a leading UTF-8 BOM, which otherwise
  // arrives as U+FEFF and makes an otherwise valid document fail to parse.
  let body = if text.has_prefix("\u{FEFF}") {
    text[1:].to_owned()
  } else {
    text
  }
  @json.parse(body) catch {
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
/// Whether request state contains `key`, including keys seeded from application
/// state. Unlike `Context::get`, this distinguishes a missing key from one
/// stored with an empty string value.
pub fn Context::has_state(self : Context, key : String) -> Bool {
  self.state.contains(key)
}

///|
/// Remove `key` from request state. Returns whether the key was present.
/// Removing a key seeded from application state only affects this request.
pub fn Context::remove_state(self : Context, key : String) -> Bool {
  match self.state.remove_and_get(key) {
    Some(_) => true
    None => false
  }
}

///|
/// Parameter names mapped to their `param:`-prefixed state keys.
let param_key_cache : Map[String, String] = Map([])

///|
/// Recency ticks for `param_key_cache`.
let param_key_cache_ages : Map[String, Int32] = Map([])

///|
fn param_state_key(name : String) -> String {
  match param_key_cache.get(name) {
    Some(key) => {
      cache_touch(param_key_cache_ages, name)
      key
    }
    None => {
      let key = PARAM_PREFIX + name
      parse_cache_set(param_key_cache, param_key_cache_ages, name, key)
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
/// Look up the route parameter `name`, returning `default` when the route did
/// not capture it. Route matching never produces an empty segment, so a
/// parameter that matched has a non-empty value and the fallback is only used
/// for parameters the route does not define.
pub fn Context::param_default(
  self : Context,
  name : String,
  default : String,
) -> String {
  if self.state.is_empty() {
    return default
  }
  match self.state.get(param_state_key(name)) {
    Some(value) => value
    None => default
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
/// Whether the matched route captured a parameter named `name`, including a
/// wildcard capture. Unlike `Context::param`, this distinguishes an absent
/// parameter from one whose captured text is empty (a wildcard can match the
/// empty remainder).
pub fn Context::has_param(self : Context, name : String) -> Bool {
  name != "" && self.state.contains(PARAM_PREFIX + name)
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
  set_header_ignore_case(self.response.headers, key, value)
}

///|
/// Read a response header, matched case-insensitively. Returns `""` when the
/// header is absent. Useful in middleware that inspects or rewrites headers
/// after calling through to the handler.
pub fn Context::response_header(self : Context, key : String) -> String {
  match get_header_ignore_case(self.response.headers, key) {
    Some(value) => value
    None => ""
  }
}

///|
/// Whether the response already carries `key`, matched case-insensitively.
/// Unlike `Context::response_header`, this distinguishes a header with an empty
/// value from an absent header.
pub fn Context::has_response_header(self : Context, key : String) -> Bool {
  get_header_ignore_case(self.response.headers, key) is Some(_)
}

///|
/// Remove every response header whose name matches `key` case-insensitively
/// and report whether one was present.
pub fn Context::remove_response_header(
  self : Context,
  key : String,
) -> Bool {
  let removed = remove_header_ignore_case(self.response.headers, key)
  // `set_cookie` records a pending cookie in addition to the raw header, and
  // the server sends that array as the authoritative `Set-Cookie` lines.
  // Removing the header must therefore drop those pending cookies too.
  if key.view().equal_ignore_ascii_case("Set-Cookie".view()) &&
    !self.response.cookies.is_empty() {
    self.response.cookies.clear()
    true
  } else {
    removed
  }
}

///|
/// Append `value` to the comma-separated response header `key`, matching the
/// name case-insensitively. When the header is absent it is created; when it
/// is present the new value is joined with `", "`. An empty `value` leaves an
/// existing field untouched (creating an empty field only when the header was
/// absent), so callers can append an optional value unconditionally.
///
/// This is the right helper for list-valued fields such as `Vary`, `Link` or
/// `Warning`. Do not use it for `Set-Cookie`: cookies must stay separate
/// header lines, so use `Context::add_cookie` / `Context::set_cookie` instead.
pub fn Context::append_header(
  self : Context,
  key : String,
  value : String,
) -> Unit {
  if sanitize_response_header_name(key) == "" {
    return
  }
  match get_header_ignore_case(self.response.headers, key) {
    Some(existing) =>
      if existing == "" {
        set_header_ignore_case(self.response.headers, key, value)
      } else if value != "" {
        set_header_ignore_case(
          self.response.headers,
          key,
          existing + ", " + value,
        )
      }
    None => set_header_ignore_case(self.response.headers, key, value)
  }
}

///|
/// Set the response header `key` to `value` only when no spelling of that
/// header is present, and report whether it was set. A header that exists with
/// an empty value still counts as present, so middleware can establish a
/// default without overwriting a handler's deliberate empty value.
pub fn Context::set_header_if_absent(
  self : Context,
  key : String,
  value : String,
) -> Bool {
  if sanitize_response_header_name(key) == "" {
    return false
  }
  if get_header_ignore_case(self.response.headers, key) is Some(_) {
    false
  } else {
    set_header_ignore_case(self.response.headers, key, value)
    true
  }
}

///|
fn Context::set_cache_control_scope(
  self : Context,
  scope : String,
  max_age : Int32,
  immutable : Bool,
) -> Unit {
  let seconds = if max_age > 0 { max_age } else { 0 }
  let value = if immutable {
    "\{scope}, max-age=\{seconds}, immutable"
  } else {
    "\{scope}, max-age=\{seconds}"
  }
  set_header_ignore_case(self.response.headers, "Cache-Control", value)
}

///|
/// Allow shared caches to store the response for `max_age` seconds
/// (`Cache-Control: public, max-age=N`). Negative lifetimes are clamped to
/// zero; pass `immutable=true` to advertise that the representation at this
/// URL never changes while it is fresh.
pub fn Context::cache_public(
  self : Context,
  max_age : Int32,
  immutable~ : Bool = false,
) -> Unit {
  self.set_cache_control_scope("public", max_age, immutable)
}

///|
/// Allow only the end user's private cache to store the response for
/// `max_age` seconds (`Cache-Control: private, max-age=N`). Negative
/// lifetimes are clamped to zero; `immutable` behaves as for
/// `Context::cache_public`.
pub fn Context::cache_private(
  self : Context,
  max_age : Int32,
  immutable~ : Bool = false,
) -> Unit {
  self.set_cache_control_scope("private", max_age, immutable)
}

///|
/// Mark the response as not storable by any cache
/// (`Cache-Control: no-store`).
pub fn Context::no_store(self : Context) -> Unit {
  set_header_ignore_case(self.response.headers, "Cache-Control", "no-store")
}

///|
/// Require caches to revalidate the response before reusing it
/// (`Cache-Control: no-cache`).
pub fn Context::no_cache(self : Context) -> Unit {
  set_header_ignore_case(self.response.headers, "Cache-Control", "no-cache")
}

///|
/// Replace the response's `Cache-Control` field with arbitrary directives.
///
/// This is the escape hatch for policies the typed helpers do not model, such
/// as `public, max-age=60, s-maxage=300, stale-while-revalidate=30`. Control
/// characters are stripped so a caller-supplied value cannot forge another
/// response header. Passing an empty value removes the field.
pub fn Context::cache_control(
  self : Context,
  directives : String,
) -> Unit {
  let cleaned = strip_control_characters(directives)
  let value = trim_ascii_space(cleaned.view()).to_owned()
  if value.is_empty() {
    ignore(remove_header_ignore_case(self.response.headers, "Cache-Control"))
  } else {
    set_header_ignore_case(self.response.headers, "Cache-Control", value)
  }
}

///|
/// Middleware that installs a default `Cache-Control` policy for the responses
/// it wraps.
///
/// The policy is applied after the handler returns, so a handler's own
/// `Cache-Control` value is kept by default. Pass `overwrite=true` to make the
/// middleware authoritative and replace any value the handler set. Because the
/// header is written after the handler, an error escaping the chain is not
/// decorated; install a recovery middleware outside this one when error
/// responses should also carry the policy. The value goes through
/// `Context::cache_control`, so control characters are stripped and an empty
/// value removes the field.
pub fn middleware_cache_control(
  directives : String,
  overwrite~ : Bool = false,
) -> Middleware {
  let cleaned = strip_control_characters(directives)
  let value = trim_ascii_space(cleaned.view()).to_owned()
  fn(next) {
    fn(ctx) raise {
      next(ctx)
      if overwrite || !ctx.has_response_header("Cache-Control") {
        ctx.cache_control(value)
      }
    }
  }
}

///|
/// Middleware that forbids storing the responses it wraps
/// (`Cache-Control: no-store`), without clobbering a more specific value set by
/// the handler. Handy for authenticated pages and API tokens.
pub fn middleware_no_store() -> Middleware {
  middleware_cache_control("no-store")
}

///|
/// Middleware that requires caches to revalidate the responses it wraps
/// (`Cache-Control: no-cache`), without clobbering a value set by the handler.
pub fn middleware_no_cache() -> Middleware {
  middleware_cache_control("no-cache")
}

///|
/// Middleware that lets shared caches store the responses it wraps for
/// `max_age` seconds, mirroring `Context::cache_public`. Negative lifetimes are
/// clamped to zero and `immutable=true` adds the `immutable` directive. A
/// handler's own `Cache-Control` value still wins.
pub fn middleware_cache_public(
  max_age : Int32,
  immutable~ : Bool = false,
) -> Middleware {
  let seconds = if max_age > 0 { max_age } else { 0 }
  let value = if immutable {
    "public, max-age=\{seconds}, immutable"
  } else {
    "public, max-age=\{seconds}"
  }
  middleware_cache_control(value)
}

///|
/// Middleware that lets only the end user's cache store the responses it wraps
/// for `max_age` seconds, mirroring `Context::cache_private`. Negative lifetimes
/// are clamped to zero and `immutable=true` adds the `immutable` directive. A
/// handler's own `Cache-Control` value still wins.
pub fn middleware_cache_private(
  max_age : Int32,
  immutable~ : Bool = false,
) -> Middleware {
  let seconds = if max_age > 0 { max_age } else { 0 }
  let value = if immutable {
    "private, max-age=\{seconds}, immutable"
  } else {
    "private, max-age=\{seconds}"
  }
  middleware_cache_control(value)
}

///|
pub fn Context::text(self : Context, status : Int32, body : String) -> Unit {
  self.file = None
  self.response.status = status
  clear_replaced_body_headers(self.response.headers)
  set_header_ignore_case(
    self.response.headers,
    "Content-Type",
    "text/plain; charset=utf-8",
  )
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
  clear_replaced_body_headers(self.response.headers)
  set_header_ignore_case(self.response.headers, "Content-Type", content_type)
  self.response.body = ""
  self.response.data = Some(data)
}

///|
pub fn Context::html(self : Context, status : Int32, body : String) -> Unit {
  self.file = None
  self.response.status = status
  clear_replaced_body_headers(self.response.headers)
  set_header_ignore_case(
    self.response.headers,
    "Content-Type",
    "text/html; charset=utf-8",
  )
  self.response.data = None
  self.response.body = body
}

///|
pub fn json_object(data : Map[String, String]) -> Json {
  let object : Map[String, Json] = Map([], capacity=data.length())
  data.each(fn(key, value) { object.set(key, Json::string(value)) })
  Json::object(object)
}

///|
/// Whether a UTF-16 code unit needs a JSON escape (`"`, `\`, or a control
/// character). Matches `@json`'s default string encoding.
#inline
fn json_needs_escape_code(code : UInt16) -> Bool {
  code == '"' || code == '\\' || code < ' '
}

///|
/// Write `value` as a JSON string body (without quotes), escaping exactly like
/// `@json.Json::string(value).stringify()` does by default.
fn json_write_escaped(buf : StringBuilder, value : String) -> Unit {
  let length = value.length()
  let mut run_start = 0
  let mut i = 0
  while i < length {
    let code = value.unsafe_get(i)
    if json_needs_escape_code(code) {
      if run_start < i {
        buf.write_view(value.exact_view(start=run_start, end=i))
      }
      match code {
        '"' => buf.write_string("\\\"")
        '\\' => buf.write_string("\\\\")
        '\n' => buf.write_string("\\n")
        '\r' => buf.write_string("\\r")
        '\b' => buf.write_string("\\b")
        '\t' => buf.write_string("\\t")
        0x0C => buf.write_string("\\f")
        _ => {
          buf.write_string("\\u00")
          buf.write_string(code.to_byte().to_hex())
        }
      }
      run_start = i + 1
    }
    i = i + 1
  }
  if run_start < length {
    buf.write_view(value.exact_view(start=run_start))
  }
}

///|
/// Serialize a flat string map as a JSON object. Keys keep the map's iteration
/// order.
fn json_object_text(data : Map[String, String]) -> String {
  if data.is_empty() {
    return "{}"
  }
  let buf = StringBuilder(size_hint=32)
  buf.write_char('{')
  let mut first = true
  data.each(fn(key, value) {
    if !first {
      buf.write_char(',')
    }
    first = false
    buf.write_char('"')
    json_write_escaped(buf, key)
    buf.write_string("\":\"")
    json_write_escaped(buf, value)
    buf.write_char('"')
  })
  buf.write_char('}')
  buf.to_string()
}

///|
pub fn Context::json_value(self : Context, status : Int32, data : Json) -> Unit {
  self.file = None
  self.response.status = status
  clear_replaced_body_headers(self.response.headers)
  set_header_ignore_case(
    self.response.headers,
    "Content-Type",
    "application/json; charset=utf-8",
  )
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
  self.file = None
  self.response.status = status
  clear_replaced_body_headers(self.response.headers)
  set_header_ignore_case(
    self.response.headers,
    "Content-Type",
    "application/json; charset=utf-8",
  )
  self.response.data = None
  self.response.body = json_object_text(data)
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
/// Keep only an origin-form path from a candidate redirect target.
///
/// A leading `//` would be parsed as a protocol-relative URL by browsers, and
/// a backslash is treated as a slash by some of them, so both are rejected
/// rather than rewritten. Fragments are dropped because they identify a place
/// in the returned document, not part of the request to replay.
fn safe_local_redirect_path(candidate : StringView) -> String? {
  if candidate.is_empty() ||
    candidate.unsafe_get(0) != ('/' : UInt16) ||
    candidate.has_prefix("//") ||
    candidate.has_prefix("/\\") ||
    candidate.contains("\\") {
    return None
  }
  let end = match candidate.find("#") {
    Some(index) => index
    None => candidate.length()
  }
  if end == 0 {
    return None
  }
  // Browsers and intermediaries may percent-decode a path before following
  // it. A target such as `/%2f%2fhost` would then become a protocol-relative
  // URL, and `/%5chost` a backslash spelling of it, so apply the same checks
  // to the decoded path rather than only to the raw request target.
  let path = candidate[:end]
  let path_end = match path.find("?") {
    Some(index) => index
    None => path.length()
  }
  let decoded_path = decode_url_path(path[:path_end])
  let decoded_view = decoded_path.view()
  if decoded_view.has_prefix("//") || decoded_view.contains("\\") {
    return None
  }
  let mut i = 0
  while i < decoded_view.length() {
    let code = decoded_view.unsafe_get(i).to_int()
    if code < 0x20 || code == 0x7F {
      return None
    }
    i = i + 1
  }
  Some(path.to_owned())
}

///|
/// Turn a `Referer` into a local redirect target, or `None` when it does not
/// name this host or cannot be parsed safely.
///
/// The result is always an origin-form path on the current host, even when the
/// referer was an absolute URL. That is what keeps `Context::redirect_back`
/// from becoming an open redirect: another origin is rejected, and a matching
/// origin contributes only its path and query.
fn local_referer_target(referer : String, authority : String) -> String? {
  let raw = trim_ascii_space(referer.view()).to_owned()
  if raw.is_empty() {
    return None
  }
  let clean = strip_control_characters(raw)
  if clean != raw {
    return None
  }
  let view = clean.view()
  if view.has_prefix("/") {
    return safe_local_redirect_path(view)
  }
  let scheme_length = if starts_with_ignore_ascii_case(
    view,
    "http://".view(),
  ) {
    7
  } else if starts_with_ignore_ascii_case(view, "https://".view()) {
    8
  } else {
    return None
  }
  let rest = view[scheme_length:]
  let mut end = 0
  while end < rest.length() {
    let code = rest.unsafe_get(end)
    if code == ('/' : UInt16) ||
      code == ('?' : UInt16) ||
      code == ('#' : UInt16) {
      break
    }
    end = end + 1
  }
  let host_part = rest[:end]
  if host_part.is_empty() {
    return None
  }
  let expected = match host_authority_host(authority.view()) {
    Some(host) => host
    None => return None
  }
  let actual = match host_authority_host(host_part) {
    Some(host) => host
    None => return None
  }
  if !expected.view().equal_ignore_ascii_case(actual.view()) {
    return None
  }
  let tail = rest[end:]
  if tail.is_empty() {
    return Some("/")
  }
  let first = tail.unsafe_get(0)
  if first == ('#' : UInt16) {
    // A fragment-only referer points into the current document, not at a
    // different path to return to.
    return Some("/")
  }
  if first == ('?' : UInt16) {
    let candidate = "/" + tail.to_owned()
    return safe_local_redirect_path(candidate.view())
  }
  safe_local_redirect_path(tail)
}

///|
/// Redirect back to the page named by the request's `Referer`.
///
/// The default is `303 See Other`, the right status after a form submission.
/// Only a local target is used: an absolute referer is reduced to its path and
/// query, and a referer naming another host, using a non-HTTP scheme, carrying
/// control characters, or posing as a protocol-relative URL is ignored in
/// favour of `fallback`. This keeps the helper safe against open-redirect
/// abuse when the `Referer` header is attacker-controlled.
pub fn Context::redirect_back(
  self : Context,
  status~ : Int32 = 303,
  fallback~ : String = "/",
) -> Unit {
  let target = match local_referer_target(
    self.header("Referer"),
    self.forwarded_authority(),
  ) {
    Some(target) => target
    None => if fallback == "" { "/" } else { fallback }
  }
  self.redirect(status, target)
}

///|
pub fn Context::redirect(
  self : Context,
  status : Int32,
  location : String,
) -> Unit {
  self.file = None
  self.response.status = status
  clear_replaced_body_headers(self.response.headers)
  clear_replaced_representation_headers(self.response.headers)
  // A redirect has no body, so a representation type prepared for an earlier
  // response must not leak into it.
  ignore(remove_header_ignore_case(self.response.headers, "Content-Type"))
  set_header_ignore_case(
    self.response.headers,
    "Location",
    strip_control_characters(location),
  )
  self.response.data = None
  self.response.body = ""
}

///|
pub fn Context::no_content(self : Context) -> Unit {
  self.file = None
  self.response.status = 204
  self.response.body = ""
  self.response.data = None
  ignore(remove_header_ignore_case(self.response.headers, "Content-Type"))
  clear_replaced_body_headers(self.response.headers)
  clear_replaced_representation_headers(self.response.headers)
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
/// The path component of the request target, without the query string or a
/// fragment. The spelling is preserved (including percent escapes), so a
/// signature or access-log line can use it exactly as the client sent it.
///
/// `Context::get_path` returns the whole request target; use this helper when
/// only the routing path is wanted.
pub fn Context::pathname(self : Context) -> String {
  clean_path_view(self.request.path).to_owned()
}

///|
/// The raw query string of the request target, without the leading `?` or a
/// trailing fragment.
///
/// Unlike `Context::queries` / `Context::query_values`, this preserves the
/// original order, duplicate keys and percent-encoding. It is the right input
/// for signature verification and for forwarding a request unchanged. Returns
/// `""` when the target carries no query.
pub fn Context::query_string(self : Context) -> String {
  match path_query_index(self.request.path) {
    Some(index) => query_source_view(self.request.path, index).to_owned()
    None => ""
  }
}

///|
/// The registered pattern of the route that matched the request, with `:param`
/// and `*wildcard` segments kept in place (for example `/users/:id`). Returns
/// `""` when no ordinary route matched, including fallback and static-file
/// responses.
///
/// This is the stable route identity middlewares should use for logging and
/// metrics; `Context::get_path`, by contrast, is the concrete request target.
pub fn Context::route_pattern(self : Context) -> String {
  match self.state.get(ROUTE_PATTERN_STATE_KEY) {
    Some(value) => value
    None => ""
  }
}

///|
/// The method under which the matched route was registered. Like
/// `Context::route_pattern`, this is empty when no ordinary route matched.
/// `HEAD` requests served by a `GET` route report `"GET"`, because that is the
/// route's registered method.
pub fn Context::route_method(self : Context) -> String {
  match self.state.get(ROUTE_METHOD_STATE_KEY) {
    Some(value) => value
    None => ""
  }
}

///|
/// The name under which the matched route was registered with
/// `App::route_named`, `RouteGroup::route_named` or `Router::add_named_route`.
/// Returns `""` when the route is unnamed or when no ordinary route matched.
///
/// This is the companion of `Context::route_pattern` / `Context::route_method`
/// for metrics grouped by named route, and it follows the same `HEAD`-to-`GET`
/// fallback as `Context::route_method`.
pub fn Context::route_name(self : Context) -> String {
  match self.state.get(ROUTE_NAME_STATE_KEY) {
    Some(value) => value
    None => ""
  }
}

///|
pub fn Context::header(self : Context, key : String) -> String {
  match get_header_ignore_case(self.request.headers, key) {
    Some(value) => value
    None => ""
  }
}

///|
/// Whether the request carries `key`, matched case-insensitively. Unlike
/// `Context::header`, this distinguishes a header with an empty value from an
/// absent header.
pub fn Context::has_header(self : Context, key : String) -> Bool {
  get_header_ignore_case(self.request.headers, key) is Some(_)
}

///|
/// Parsed host names keyed by the trimmed `Host` header value.
let host_cache : Map[StringView, String] = Map([])

///|
/// Recency ticks for `host_cache`.
let host_cache_ages : Map[StringView, Int32] = Map([])

///|
/// The host name from the `Host` header, without the port.
pub fn Context::host(self : Context) -> String {
  let authority = trim_ascii_space(self.header("Host").view())
  if authority == "" {
    return ""
  }
  match host_cache.get(authority) {
    Some(cached) => {
      cache_touch(host_cache_ages, authority)
      return cached
    }
    None => ()
  }
  // Validate the authority before truncating it: otherwise a malformed value
  // such as `[::1]evil` or `example.com:bad` would turn into an apparently
  // valid host and could be trusted by callers that use the parsed value for
  // host-based decisions.
  let host = match host_authority_host(authority) {
    None => ""
    Some(_) =>
      if authority.unsafe_get(0) == ('[' : UInt16) {
        match authority.find("]") {
          Some(index) => authority[:index + 1].to_owned()
          None => ""
        }
      } else {
        match authority.find(":") {
          Some(index) => authority[:index].to_owned()
          None => authority.to_owned()
        }
      }
  }
  if authority.length() <= PARSE_CACHE_MAX_KEY {
    parse_cache_set(host_cache, host_cache_ages, authority, host)
  }
  host
}

///|
/// Unescape an RFC 7239 parameter value enclosed in double quotes. Values
/// that are not quoted are returned unchanged; anything after the closing
/// quote is ignored.
fn unquote_forwarded_value(raw : StringView) -> String {
  if raw.length() < 2 || raw.unsafe_get(0) != ('"' : UInt16) {
    return raw.to_owned()
  }
  let length = raw.length()
  let builder = StringBuilder(size_hint=length)
  let mut i = 1
  while i < length {
    let unit = raw.unsafe_get(i)
    if unit == ('\\' : UInt16) && i + 1 < length {
      builder.write_char(raw.unsafe_get(i + 1).to_int().unsafe_to_char())
      i = i + 2
    } else if unit == ('"' : UInt16) {
      break
    } else {
      builder.write_char(unit.to_int().unsafe_to_char())
      i = i + 1
    }
  }
  builder.to_string()
}

///|
/// Value of parameter `name` in the first element of an RFC 7239 `Forwarded`
/// header, for example `host` in `for=192.0.2.60;host="example.com:8443"`.
///
/// Parameter names are matched case-insensitively and quoted values are
/// unescaped. Later elements describe further proxies, so only the first
/// element is inspected. Returns `None` when the parameter is absent or
/// empty.
fn forwarded_first_param(header : StringView, name : StringView) -> String? {
  let length = header.length()
  let mut element_end = length
  let mut i = 0
  let mut in_quotes = false
  while i < length {
    let unit = header.unsafe_get(i)
    if in_quotes && unit == ('\\' : UInt16) && i + 1 < length {
      i = i + 2
      continue
    }
    if unit == ('"' : UInt16) {
      in_quotes = !in_quotes
    } else if unit == (',' : UInt16) && !in_quotes {
      element_end = i
      break
    }
    i = i + 1
  }
  forwarded_element_param(header[:element_end], name)
}

///|
/// Value of parameter `name` in a single element of an RFC 7239 `Forwarded`
/// header, including the empty string when the parameter is present but
/// carries no value.
///
/// Parameter names are matched case-insensitively and quoted values are
/// unescaped. Returns `None` only when the parameter is absent, which lets the
/// trusted-proxy path distinguish an addressless `for=` node from a header
/// that never mentions `for` at all.
fn forwarded_element_param_value(
  element : StringView,
  name : StringView,
) -> String? {
  let mut pos = 0
  while pos < element.length() {
    let mut end = pos
    let mut quoted = false
    while end < element.length() {
      let unit = element.unsafe_get(end)
      if quoted && unit == ('\\' : UInt16) && end + 1 < element.length() {
        end = end + 2
        continue
      }
      if unit == ('"' : UInt16) {
        quoted = !quoted
      } else if unit == (';' : UInt16) && !quoted {
        break
      }
      end = end + 1
    }
    let mut eq = pos
    while eq < end && element.unsafe_get(eq) != ('=' : UInt16) {
      eq = eq + 1
    }
    if eq < end {
      let key = trim_ascii_space(element[pos:eq])
      if key.equal_ignore_ascii_case(name) {
        let unquoted = unquote_forwarded_value(
          trim_ascii_space(element[eq + 1:end]),
        )
        let value = trim_ascii_space(unquoted.view())
        return Some(value.to_owned())
      }
    }
    pos = end + 1
  }
  None
}

///|
/// Value of parameter `name` in a single element of an RFC 7239 `Forwarded`
/// header, for example `host` in `for=192.0.2.60;host="example.com:8443"`.
///
/// Parameter names are matched case-insensitively and quoted values are
/// unescaped. Returns `None` when the parameter is absent or empty.
fn forwarded_element_param(element : StringView, name : StringView) -> String? {
  match forwarded_element_param_value(element, name) {
    Some(value) => if value.is_empty() { None } else { Some(value) }
    None => None
  }
}

///|
/// Normalize an RFC 7239 `for=` node identifier to a client address: an
/// optional port is dropped and IPv6 literals keep their brackets, matching
/// `Context::ip`. Obfuscated (`_...`), `unknown`, and malformed nodes carry no
/// address, so they report `None`.
fn normalize_forwarded_for(value : StringView) -> String? {
  if value.is_empty() ||
    value.equal_ignore_ascii_case("unknown".view()) ||
    value.unsafe_get(0) == ('_' : UInt16) {
    return None
  }
  if value.unsafe_get(0) == ('[' : UInt16) {
    // Reuse the authority validator so a malformed literal such as
    // `[::1]junk`, `[::1]:bad`, or `[not-an-ip]` cannot be truncated into a
    // trusted client address.
    return host_authority_host(value)
  }
  let length = value.length()
  let mut i = 0
  let mut colons = 0
  let mut last_colon = -1
  while i < length {
    if value.unsafe_get(i) == (':' : UInt16) {
      colons = colons + 1
      last_colon = i
    }
    i = i + 1
  }
  // A node identifier is an IPv4address, a bracketed IPv6address, `unknown`
  // or an obfuscated `_...` name. A single colon separates an IPv4 address
  // from its port; several colons mean a bare IPv6 address. Anything else
  // (a host name, an out-of-range octet, ...) is not an address and must stay
  // addressless so trusted-hop counting cannot report client-chosen text.
  if colons == 0 {
    if !valid_ipv4_literal(value) {
      return None
    }
    return Some(value.to_owned())
  }
  if colons == 1 {
    if last_colon <= 0 {
      return None
    }
    let host = value[:last_colon]
    // `unknown` is a node name, not an address, even when it carries a port.
    if host.equal_ignore_ascii_case("unknown".view()) {
      return None
    }
    if !valid_ipv4_literal(host) ||
      !valid_host_port(value[last_colon + 1:]) {
      return None
    }
    return Some(host.to_owned())
  }
  // Several colons without brackets are a bare IPv6 literal, so validate it
  // instead of trusting an arbitrary client-chosen string as an address.
  if !valid_bracketed_host(value) {
    return None
  }
  Some(value.to_owned())
}

///|
/// Whether `value` is a syntactically valid URI scheme (RFC 3986 §3.1).
/// Forwarded protocol values are client-controlled, so a malformed value must
/// not be spliced into `Context::full_url`.
fn valid_url_scheme(value : StringView) -> Bool {
  let length = value.length()
  if length == 0 {
    return false
  }
  let first = value.unsafe_get(0).to_int()
  if !((first >= 65 && first <= 90) || (first >= 97 && first <= 122)) {
    return false
  }
  let mut i = 1
  while i < length {
    if !is_uri_scheme_character(value.unsafe_get(i).to_int()) {
      return false
    }
    i = i + 1
  }
  true
}

///|
/// Whether `value` is a scheme a request to this HTTP server can actually
/// use. Forwarded protocol headers are client-controlled, so a syntactically
/// valid but unrelated scheme such as `javascript` or `file` must not be
/// spliced into an absolute URL by `Context::full_url`.
fn is_http_request_scheme(value : StringView) -> Bool {
  value.equal_ignore_ascii_case("http".view()) ||
  value.equal_ignore_ascii_case("https".view())
}

///|
/// Validate an authority (host plus optional port) before echoing a forwarded
/// value. The original spelling is preserved, including an explicit port.
fn valid_forwarded_authority(value : StringView) -> String? {
  let authority = trim_ascii_space(value)
  if authority.is_empty() {
    return None
  }
  match host_authority_host(authority) {
    Some(_) => Some(authority.to_owned())
    None => None
  }
}

///|
/// The URL scheme of the request, honoring the RFC 7239 `Forwarded` `proto=`
/// parameter first, then `X-Forwarded-Proto`, and defaulting to `"http"`.
/// Malformed forwarded values are ignored so `Context::full_url` cannot be
/// steered into another scheme.
pub fn Context::protocol(self : Context) -> String {
  let forwarded = self.header("Forwarded")
  if forwarded != "" {
    match forwarded_first_param(forwarded.view(), "proto".view()) {
      Some(value) =>
        if valid_url_scheme(value.view()) &&
          is_http_request_scheme(value.view()) {
          return value
        }
      None => ()
    }
  }
  let proto = trim_ascii_space(self.header("X-Forwarded-Proto").view())
  if proto != "" {
    let value = match proto.find(",") {
      Some(index) => trim_ascii_space(proto[:index])
      None => proto
    }
    if valid_url_scheme(value.view()) &&
      is_http_request_scheme(value.view()) {
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
/// The authority (host and optional port) to use in absolute URLs, honoring
/// the RFC 7239 `Forwarded` `host=` parameter first, then the first value of
/// `X-Forwarded-Host`, then the `Host` header. Returns `""` when none is
/// present. Use `Context::host` for the port-less host name.
pub fn Context::forwarded_authority(self : Context) -> String {
  let forwarded = self.header("Forwarded")
  if forwarded != "" {
    match forwarded_first_param(forwarded.view(), "host".view()) {
      Some(value) =>
        match valid_forwarded_authority(value.view()) {
          Some(authority) => return authority
          None => ()
        }
      None => ()
    }
  }
  let xfh = trim_ascii_space(self.header("X-Forwarded-Host").view())
  if xfh != "" {
    let first = match xfh.find(",") {
      Some(index) => trim_ascii_space(xfh[:index])
      None => xfh
    }
    match valid_forwarded_authority(first) {
      Some(authority) => return authority
      None => ()
    }
  }
  match valid_forwarded_authority(self.header("Host").view()) {
    Some(authority) => authority
    None => ""
  }
}

///|
/// The full URL of the request, for example `https://example.com/users/1?q=x`.
///
/// Honors `Forwarded`/`X-Forwarded-Proto` and
/// `Forwarded`/`X-Forwarded-Host` when building the URL, so links stay
/// correct behind a reverse proxy.
pub fn Context::full_url(self : Context) -> String {
  let raw_path = self.request.path
  let path = match raw_path.find("#") {
    Some(index) => raw_path[:index].to_owned()
    None => raw_path
  }
  // Asterisk-form names the whole server, not a URL path.
  if path == "*" {
    return path
  }
  let authority = self.forwarded_authority()
  if authority.is_empty() {
    return path
  }
  // With an authority the result is an absolute URL, whose path must be
  // absolute-path (and not concatenate onto the authority).
  let path = if path.is_empty() {
    "/"
  } else if path.has_prefix("/") {
    path
  } else {
    "/" + path
  }
  let scheme = self.protocol()
  let builder = StringBuilder(
    size_hint=scheme.length() + authority.length() + path.length() + 3,
  )
  builder.write_string(scheme)
  builder.write_string("://")
  builder.write_string(authority)
  builder.write_string(path)
  builder.to_string()
}

///|
/// Address of the client that opened the connection, without the ephemeral
/// port. When the request is served by `App::serve` this is the peer IP
/// recorded by the server; contexts built by hand report `"127.0.0.1"` unless
/// `remote_addr` was set in the state.
///
/// When the application declares trusted proxies with `App::trust_proxy`, the
/// address of the real client is reported instead: the forwarded chain is
/// walked `hops` steps back from the peer, so one trusted proxy reports the
/// address that proxy saw. A selected hop that recorded no address falls back
/// to the peer address. Without a trusted-proxy configuration the peer address
/// is reported, and `Context::forwarded_ip` remains the way to read the
/// forwarded headers directly.
pub fn Context::ip(self : Context) -> String {
  let peer = match self.state.get("remote_addr") {
    Some(value) => value
    None => "127.0.0.1"
  }
  let hops = match self.state.get(TRUST_PROXY_HOPS_KEY) {
    Some(value) =>
      match parse_int_value(value.view()) {
        Some(hops) => hops
        None => 0
      }
    None => 0
  }
  trusted_client_address(peer, forwarded_chain(self), hops)
}

///|
/// The client address, honoring the RFC 7239 `Forwarded` `for=` parameter
/// first, then the first value of `X-Forwarded-For`, then `X-Real-IP`, and
/// finally the peer address. An optional source port (and the brackets around
/// an IPv6 literal) is stripped, so the returned value is a bare address.
/// Obfuscated or unknown `for=` nodes are skipped.
pub fn Context::forwarded_ip(self : Context) -> String {
  let forwarded = self.header("Forwarded")
  if forwarded != "" {
    match forwarded_first_param(forwarded.view(), "for".view()) {
      Some(value) =>
        match normalize_forwarded_for(value.view()) {
          Some(ip) => return ip
          None => ()
        }
      None => ()
    }
  }
  let chain = self.header("X-Forwarded-For")
  if chain != "" {
    let first = match chain.find(",") {
      Some(index) => trim_ascii_space(chain[:index])
      None => trim_ascii_space(chain.view())
    }
    if !first.is_empty() {
      return normalize_legacy_forwarded_address(first)
    }
  }
  let real_ip = trim_ascii_space(self.header("X-Real-IP").view())
  if !real_ip.is_empty() {
    return normalize_legacy_forwarded_address(real_ip)
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
/// Parse a `Cookie` request header into a name-to-value map.
///
/// User agents order same-name cookies with the longest (most specific) path
/// first (RFC 6265 §5.4), so the first occurrence is the one to use. Later
/// duplicates are ignored instead of shadowing a more specific cookie (such as
/// a session scoped to `/app`).
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
        while name_end > start &&
              is_cookie_whitespace(header.unsafe_get(name_end - 1)) {
          name_end = name_end - 1
        }
        if name_end > start {
          let name = header[start:name_end].to_owned()
          // A cookie name that is not an HTTP token cannot have been written
          // by `set_cookie` (which sanitizes names), so ignore it instead of
          // exposing a spelling that `Context::cookie` can never look up.
          let mut valid_name = true
          let mut name_index = start
          while name_index < name_end {
            if !is_cookie_name_character(header.unsafe_get(name_index)) {
              valid_name = false
              break
            }
            name_index = name_index + 1
          }
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
          if valid_name && !cookies.contains(name) {
            cookies.set(name, value)
          }
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
/// Deep-copy a map of multi-value parameters, so callers cannot mutate the
/// arrays held by the parse cache.
fn copy_values_map(
  source : Map[String, Array[String]],
) -> Map[String, Array[String]] {
  let copy : Map[String, Array[String]] = Map(
    [],
    capacity=source.length(),
  )
  for key, values in source {
    copy.set(key, values.copy())
  }
  copy
}

///|
/// Maximum number of entries kept in the parse caches.
const PARSE_CACHE_LIMIT : Int32 = 128

///|
/// Maximum key length stored in the parse caches.
const PARSE_CACHE_MAX_KEY : Int32 = 4096

///|
/// Monotonic tick used by the bounded caches to approximate LRU eviction.
let cache_clock : Ref[Int32] = Ref(0)

///|
/// How many entries an eviction samples before dropping the oldest one seen.
const CACHE_EVICT_SAMPLE : Int32 = 4

///|
/// Refresh a hit entry's recency tick only once the clock has moved this far
/// past it.
const CACHE_TOUCH_INTERVAL : Int32 = 16

///|
/// Return a fresh tick, marking the entry that uses it as most recent.
fn cache_advance() -> Int32 {
  cache_clock.val = cache_clock.val + 1
  cache_clock.val
}

///|
/// Record `key` as recently used unless its recorded tick is still close to the
/// current clock.
fn[K : Hash + Eq] cache_touch(ages : Map[K, Int32], key : K) -> Unit {
  let now = cache_clock.val
  match ages.get(key) {
    Some(tick) => if now - tick < CACHE_TOUCH_INTERVAL { return }
    None => ()
  }
  ages.set(key, cache_advance())
}

///|
/// Evict one entry, sampling a few candidates and dropping the one with the
/// oldest tick. The victim is approximate rather than exact LRU.
fn[K : Hash + Eq, V] cache_evict(
  cache : Map[K, V],
  ages : Map[K, Int32],
) -> Unit {
  let mut oldest : K? = None
  let mut oldest_tick = 0
  let mut sampled = 0
  for key, tick in ages {
    if sampled >= CACHE_EVICT_SAMPLE {
      break
    }
    let replace = match oldest {
      None => true
      Some(_) => tick < oldest_tick
    }
    if replace {
      oldest = Some(key)
      oldest_tick = tick
    }
    sampled = sampled + 1
  }
  match oldest {
    Some(key) => {
      ignore(cache.remove(key))
      ignore(ages.remove(key))
    }
    None =>
      match cache.keys().next() {
        Some(key) => ignore(cache.remove(key))
        None => ()
      }
  }
}

///|
/// Insert into a bounded cache, evicting the least recently used entry when
/// the cache is full.
fn[K : Hash + Eq, V] cache_set(
  cache : Map[K, V],
  ages : Map[K, Int32],
  limit : Int32,
  key : K,
  value : V,
) -> Unit {
  if cache.length() >= limit && !cache.contains(key) {
    cache_evict(cache, ages)
  }
  cache.set(key, value)
  ages.set(key, cache_advance())
}

///|
/// Insert into one of the parse caches.
fn[K : Hash + Eq, V] parse_cache_set(
  cache : Map[K, V],
  ages : Map[K, Int32],
  key : K,
  value : V,
) -> Unit {
  cache_set(cache, ages, PARSE_CACHE_LIMIT, key, value)
}

///|
/// Last parsed `Cookie` header, keyed by its raw value.
let cookies_cache : Map[String, Map[String, String]] = Map([])

///|
/// Recency ticks for `cookies_cache`.
let cookies_cache_ages : Map[String, Int32] = Map([])

///|
/// Last parsed query strings, keyed by the raw text after `?`.
let queries_cache : Map[StringView, Map[String, String]] = Map([])

///|
/// Recency ticks for `queries_cache`.
let queries_cache_ages : Map[StringView, Int32] = Map([])

///|
/// Most recently resolved `Cookie` header and its parsed map.
let last_cookie_header : Ref[String?] = Ref(None)

///|
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
    Some(cached) => {
      cache_touch(cookies_cache_ages, header)
      cached
    }
    None => {
      let parsed = parse_cookie_map(header.view())
      if header.length() <= PARSE_CACHE_MAX_KEY {
        parse_cache_set(cookies_cache, cookies_cache_ages, header, parsed)
      }
      parsed
    }
  }
  last_cookie_header.val = Some(header)
  last_cookie_map.val = Some(parsed)
  parsed
}

///|
/// Most recently scanned path and the position of its `?`.
let last_query_index_path : Ref[String?] = Ref(None)

///|
let last_query_index : Ref[Int32] = Ref(-1)

///|
/// Position of `?` in `path` for the most recent path, or `None` when there is
/// no query or a fragment starts before it.
fn path_query_index(path : String) -> Int32? {
  match last_query_index_path.val {
    Some(cached) =>
      if physical_equal(cached, path) {
        let index = last_query_index.val
        return if index < 0 { None } else { Some(index) }
      }
    None => ()
  }
  let result = match path.find("?") {
    Some(index) =>
      match path.find("#") {
        Some(fragment) => if fragment < index { None } else { Some(index) }
        None => Some(index)
      }
    None => None
  }
  last_query_index_path.val = Some(path)
  match result {
    Some(index) => {
      last_query_index.val = index
      Some(index)
    }
    None => {
      last_query_index.val = -1
      None
    }
  }
}

///|
/// The raw query text after `?`, stopping at a fragment delimiter. The path
/// fragment is never part of the query string, even when a hand-built request
/// carries one.
fn query_source_view(path : String, index : Int32) -> StringView {
  let source = path.view()[index + 1:]
  match source.find("#") {
    Some(fragment) => source[:fragment]
    None => source
  }
}

///|
/// Most recently resolved query string and its parsed map.
let last_query_path : Ref[String?] = Ref(None)

///|
let last_query_start : Ref[Int32] = Ref(-1)

///|
let last_query_map : Ref[Map[String, String]?] = Ref(None)

///|
fn query_map_lookup(path : String, index : Int32) -> Map[String, String] {
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
  let source = query_source_view(path, index)
  let parsed = match queries_cache.get(source) {
    Some(cached) => {
      cache_touch(queries_cache_ages, source)
      cached
    }
    None => {
      let parsed = parse_urlencoded_view(source)
      if source.length() <= PARSE_CACHE_MAX_KEY {
        parse_cache_set(queries_cache, queries_cache_ages, source, parsed)
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

///|
let last_query_multi_start : Ref[Int32] = Ref(-1)

///|
let last_query_multi_map : Ref[Map[String, Array[String]]?] = Ref(None)

///|
/// Parsed multi-value query strings, keyed by the raw text after `?`.
let queries_multi_cache : Map[StringView, Map[String, Array[String]]] = Map([])

///|
/// Recency ticks for `queries_multi_cache`.
let queries_multi_cache_ages : Map[StringView, Int32] = Map([])

///|
fn query_multi_lookup(
  path : String,
  index : Int32,
) -> Map[String, Array[String]] {
  match last_query_multi_path.val {
    Some(cached_path) =>
      if physical_equal(cached_path, path) &&
        last_query_multi_start.val == index {
        match last_query_multi_map.val {
          Some(cached_map) => return cached_map
          None => ()
        }
      }
    None => ()
  }
  let source = query_source_view(path, index)
  let parsed = match queries_multi_cache.get(source) {
    Some(cached) => {
      cache_touch(queries_multi_cache_ages, source)
      cached
    }
    None => {
      let parsed = parse_urlencoded_multi(source)
      if source.length() <= PARSE_CACHE_MAX_KEY {
        parse_cache_set(
          queries_multi_cache, queries_multi_cache_ages, source, parsed,
        )
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

///|
let last_form_map : Ref[Map[String, String]?] = Ref(None)

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
  let parsed = parse_urlencoded_view(body.view())
  if body.length() <= PARSE_CACHE_MAX_KEY {
    last_form_body.val = Some(body)
    last_form_map.val = Some(parsed)
  }
  parsed
}

///|
/// Most recently resolved multi-value url-encoded form body and its parsed map.
/// Kept under the same size guard as `form_map_lookup`.
let last_form_values_body : Ref[String?] = Ref(None)

///|
let last_form_values_map : Ref[Map[String, Array[String]]?] = Ref(None)

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
  let parsed = parse_urlencoded_multi(body.view())
  if body.length() <= PARSE_CACHE_MAX_KEY {
    last_form_values_body.val = Some(body)
    last_form_values_map.val = Some(parsed)
  }
  parsed
}

///|
/// Most recently resolved multipart body, the content type it was parsed with
/// and its parsed parts.
let last_multipart_body : Ref[String?] = Ref(None)

///|
let last_multipart_content_type : Ref[String?] = Ref(None)

///|
let last_multipart_parts : Ref[Array[MultipartPart]?] = Ref(None)

///|
let last_multipart_raw_body : Ref[String?] = Ref(None)

///|
/// Copy one parsed part so callers get their own header map.
fn copy_multipart_part(part : MultipartPart) -> MultipartPart {
  {
    name: part.name,
    filename: part.filename,
    content_type: part.content_type,
    headers: part.headers.copy(),
    data: part.data,
    data_bytes: part.data_bytes,
  }
}

///|
/// Copy a parsed multipart result so callers get their own top-level array.
/// The parts and their header maps are shared with the parse cache and must be
/// treated as read-only.
fn copy_multipart_parts(parts : Array[MultipartPart]) -> Array[MultipartPart] {
  let copy : Array[MultipartPart] = Array(capacity=parts.length())
  for part in parts {
    copy.push(part)
  }
  copy
}

///|
/// Deep-copy a parsed multipart result, including each part's header map, so
/// callers can mutate the result without disturbing the parse cache.
fn clone_multipart_parts(parts : Array[MultipartPart]) -> Array[MultipartPart] {
  let copy : Array[MultipartPart] = Array(capacity=parts.length())
  for part in parts {
    copy.push(copy_multipart_part(part))
  }
  copy
}

///|
fn multipart_parts_lookup(
  body : String,
  content_type : String,
  raw_body~ : String? = None,
) -> Array[MultipartPart]? {
  match last_multipart_body.val {
    Some(cached_body) =>
      if physical_equal(cached_body, body) &&
        last_multipart_content_type.val is Some(cached_type) &&
        cached_type == content_type &&
        last_multipart_raw_body.val == raw_body {
        match last_multipart_parts.val {
          Some(cached) => return Some(cached)
          None => ()
        }
      }
    None => ()
  }
  let parsed = parse_multipart_uncached(body, content_type, raw_body~)
  match parsed {
    Some(parts) =>
      if body.length() <= PARSE_CACHE_MAX_KEY {
        last_multipart_body.val = Some(body)
        last_multipart_content_type.val = Some(content_type)
        last_multipart_parts.val = Some(parts)
        last_multipart_raw_body.val = raw_body
      }
    None => ()
  }
  parsed
}

///|
/// The parsed `Cookie` header, keyed by name. Callers receive their own copy,
/// so mutating the result cannot disturb a later request that carries the same
/// header and hits the parse cache.
pub fn Context::cookies(self : Context) -> Map[String, String] {
  let header = self.header("Cookie")
  if header == "" {
    return Map([])
  }
  cookie_map_lookup(header).copy()
}

///|
pub fn Context::cookie(self : Context, name : String) -> String? {
  if name == "" {
    return None
  }
  // `set_cookie` stores the sanitized name, so look up the same spelling to
  // keep the write and read sides symmetric.
  let lookup = sanitize_cookie_token(name, true)
  if lookup == "" {
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
          Some(cached_map) => return cached_map.get(lookup)
          None => ()
        }
      }
    None => ()
  }
  match cookies_cache.get(header) {
    Some(cached) => {
      cache_touch(cookies_cache_ages, header)
      last_cookie_header.val = Some(header)
      last_cookie_map.val = Some(cached)
      cached.get(lookup)
    }
    None => {
      let parsed = parse_cookie_map(header.view())
      if header.length() <= PARSE_CACHE_MAX_KEY {
        parse_cache_set(cookies_cache, cookies_cache_ages, header, parsed)
      }
      last_cookie_header.val = Some(header)
      last_cookie_map.val = Some(parsed)
      parsed.get(lookup)
    }
  }
}

///|
/// Drop unpaired UTF-16 surrogates, keeping valid surrogate pairs intact. Such
/// lone code units cannot be encoded as UTF-8 and would otherwise abort when a
/// header or cookie is written.
fn drop_lone_surrogates(value : String) -> String {
  let view = value.view()
  let length = view.length()
  let mut i = 0
  let mut needs_clean = false
  while i < length {
    let unit = view.unsafe_get(i)
    if unit.is_leading_surrogate() {
      if i + 1 < length && view.unsafe_get(i + 1).is_trailing_surrogate() {
        i = i + 2
        continue
      }
      needs_clean = true
      break
    } else if unit.is_trailing_surrogate() {
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
    let unit = view.unsafe_get(index)
    if unit.is_leading_surrogate() {
      if index + 1 < length &&
        view.unsafe_get(index + 1).is_trailing_surrogate() {
        builder.write_char(unit.to_int().unsafe_to_char())
        builder.write_char(
          view.unsafe_get(index + 1).to_int().unsafe_to_char(),
        )
        index = index + 2
      } else {
        index = index + 1
      }
    } else if unit.is_trailing_surrogate() {
      index = index + 1
    } else {
      builder.write_char(unit.to_int().unsafe_to_char())
      index = index + 1
    }
  }
  builder.to_string()
}

///|
fn strip_control_characters(value : String) -> String {
  let value = drop_lone_surrogates(value)
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
/// Whether `unit` is an RFC 6265 cookie-name character.
///
/// A cookie name is an HTTP `token`: visible ASCII except for the `separators`
/// set from RFC 2616, which includes whitespace, `=`, `;`, `,`, quotes,
/// slashes, brackets and braces. Dropping anything else keeps a caller-supplied
/// name from producing an invalid or ambiguous `Set-Cookie` field.
fn is_cookie_name_character(unit : UInt16) -> Bool {
  let code = unit.to_int()
  if code < 0x21 || code > 0x7E {
    return false
  }
  !(unit == ('(' : UInt16) ||
    unit == (')' : UInt16) ||
    unit == ('<' : UInt16) ||
    unit == ('>' : UInt16) ||
    unit == ('@' : UInt16) ||
    unit == (',' : UInt16) ||
    unit == (';' : UInt16) ||
    unit == (':' : UInt16) ||
    unit == ('\\' : UInt16) ||
    unit == ('"' : UInt16) ||
    unit == ('/' : UInt16) ||
    unit == ('[' : UInt16) ||
    unit == (']' : UInt16) ||
    unit == ('?' : UInt16) ||
    unit == ('=' : UInt16) ||
    unit == ('{' : UInt16) ||
    unit == ('}' : UInt16))
}

///|
/// Whether `unit` is an RFC 6265 cookie-value character.
///
/// `cookie-octet` excludes whitespace, control characters, `"`, `,`, `;` and
/// `\`. `=` and other ASCII punctuation are valid inside a value, which keeps
/// base64 padding intact. Spaces and non-ASCII text are retained to preserve
/// the existing cookie-value behaviour; they cannot forge another header line
/// once control characters are removed.
fn is_cookie_value_character(unit : UInt16) -> Bool {
  let code = unit.to_int()
  code >= 0x20 &&
  code != 0x7F &&
  unit != (',' : UInt16) &&
  unit != (';' : UInt16) &&
  unit != ('"' : UInt16) &&
  unit != ('\\' : UInt16)
}

///|
/// Whether `unit` may not appear in a cookie name or value.
///
/// `name_mode` selects the stricter HTTP token grammar for cookie names; the
/// value path only rejects characters that break the `cookie-octet` grammar.
fn is_cookie_character_unsafe(unit : UInt16, name_mode : Bool) -> Bool {
  if name_mode {
    !is_cookie_name_character(unit)
  } else {
    !is_cookie_value_character(unit)
  }
}

///|
/// Drop characters that are invalid or dangerous in a cookie name/value.
fn sanitize_cookie_token(value : String, name_mode : Bool) -> String {
  let value = drop_lone_surrogates(value)
  let view = value.view()
  let length = view.length()
  let mut i = 0
  let mut needs_clean = false
  while i < length {
    if is_cookie_character_unsafe(view.unsafe_get(i), name_mode) {
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
    let unit = view.unsafe_get(index)
    if !is_cookie_character_unsafe(unit, name_mode) {
      builder.write_char(unit.to_int().unsafe_to_char())
    }
    index = index + 1
  }
  builder.to_string()
}

///|
/// Drop characters that would break a cookie attribute value, such as the
/// `;` that separates the attributes in a `Set-Cookie` header.
fn sanitize_cookie_attribute(value : String) -> String {
  let value = drop_lone_surrogates(value)
  let view = value.view()
  let length = view.length()
  let mut i = 0
  let mut needs_clean = false
  while i < length {
    let unit = view.unsafe_get(i)
    let code = unit.to_int()
    if code < 0x20 ||
      code == 0x7F ||
      unit == (';' : UInt16) ||
      unit == (',' : UInt16) {
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
    let unit = view.unsafe_get(index)
    let code = unit.to_int()
    if !(code < 0x20 ||
      code == 0x7F ||
      unit == (';' : UInt16) ||
      unit == (',' : UInt16)) {
      builder.write_char(code.unsafe_to_char())
    }
    index = index + 1
  }
  builder.to_string()
}

///|
/// Restrict a cookie `Domain` attribute to the characters that can appear in
/// a host name or an IP literal.
fn sanitize_cookie_domain(value : String) -> String {
  let view = value.view()
  let length = view.length()
  let builder = StringBuilder(size_hint=length)
  let mut i = 0
  while i < length {
    let unit = view.unsafe_get(i)
    let code = unit.to_int()
    let keep = (code >= 'a' && code <= 'z') ||
      (code >= 'A' && code <= 'Z') ||
      (code >= '0' && code <= '9') ||
      unit == ('.' : UInt16) ||
      unit == ('-' : UInt16) ||
      unit == ('_' : UInt16) ||
      unit == (':' : UInt16) ||
      unit == ('[' : UInt16) ||
      unit == (']' : UInt16)
    if keep {
      builder.write_char(code.unsafe_to_char())
    }
    i = i + 1
  }
  builder.to_string()
}

///|
/// Canonical spelling of a valid `SameSite` attribute value, or `None` when
/// the value is not one of the three tokens browsers understand.
fn canonical_same_site(value : String) -> String? {
  let trimmed = trim_ascii_space(value.view())
  if trimmed.equal_ignore_ascii_case("strict".view()) {
    Some("Strict")
  } else if trimmed.equal_ignore_ascii_case("lax".view()) {
    Some("Lax")
  } else if trimmed.equal_ignore_ascii_case("none".view()) {
    Some("None")
  } else {
    None
  }
}

///|
/// Build a cookie with every name, value and attribute sanitized, so caller
/// input cannot forge additional `Set-Cookie` attributes or header bytes.
fn build_cookie(
  name : String,
  value : String,
  path? : String,
  max_age? : Int64,
  expires? : Int64,
  domain? : String,
  same_site? : String,
  http_only : Bool,
  secure : Bool,
  partitioned : Bool,
) -> @http.Cookie {
  let clean_path = match path {
    Some(value) => Some(sanitize_cookie_attribute(value))
    None => None
  }
  let expires_raw = match expires {
    Some(seconds) => Some(format_http_date(seconds))
    None => None
  }
  // RFC 6265 `delta-seconds` is non-negative. A negative caller value still
  // means "expire now", so render it as the canonical zero rather than an
  // invalid negative `Max-Age`.
  let clean_max_age = match max_age {
    Some(seconds) => Some(if seconds < 0L { 0L } else { seconds })
    None => None
  }
  let clean_domain = match domain {
    Some(value) => {
      let cleaned = sanitize_cookie_domain(value)
      if cleaned == "" {
        None
      } else {
        Some(cleaned)
      }
    }
    None => None
  }
  let extensions : Array[String] = []
  match same_site {
    Some(value) =>
      match canonical_same_site(value) {
        Some(token) => extensions.push("SameSite=" + token)
        None => ()
      }
    None => ()
  }
  if partitioned {
    extensions.push("Partitioned")
  }
  @http.Cookie(
    sanitize_cookie_token(name, true),
    sanitize_cookie_token(value, false),
    path?=clean_path,
    expires_raw?,
    max_age?=clean_max_age,
    domain?=clean_domain,
    http_only~,
    secure~,
    extensions~,
  )
}

///|
pub fn Context::add_cookie(
  self : Context,
  name : String,
  value : String,
  path? : String,
  max_age? : Int64,
  expires? : Int64,
  domain? : String,
  same_site? : String,
  http_only~ : Bool = false,
  secure~ : Bool = false,
  partitioned~ : Bool = false,
) -> Unit {
  let cookie = build_cookie(
    name,
    value,
    path?,
    max_age?,
    expires?,
    domain?,
    same_site?,
    http_only,
    secure,
    partitioned,
  )
  if cookie.name == "" {
    return
  }
  self.response.cookies.push(cookie)
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
  match cookie.expires_raw {
    Some(expires) => {
      builder.write_string("; Expires=")
      builder.write_string(expires)
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
  expires? : Int64,
  domain? : String,
  same_site? : String,
  http_only~ : Bool = false,
  secure~ : Bool = false,
  partitioned~ : Bool = false,
) -> Unit {
  let cookie = build_cookie(
    name,
    value,
    path?,
    max_age?,
    expires?,
    domain?,
    same_site?,
    http_only,
    secure,
    partitioned,
  )
  if cookie.name == "" {
    return
  }
  set_header_ignore_case(
    self.response.headers,
    "Set-Cookie",
    render_cookie(cookie),
  )
  self.response.cookies.push(cookie)
}

///|
pub fn Context::clear_cookie(
  self : Context,
  name : String,
  path? : String,
  domain? : String,
  same_site? : String,
  http_only~ : Bool = false,
  secure~ : Bool = false,
  partitioned~ : Bool = false,
) -> Unit {
  // Deletion keeps the attributes that are part of a cookie's storage key,
  // most notably `Partitioned` for CHIPS cookies, so the browser removes the
  // same cookie that was set earlier.
  self.set_cookie(
    name,
    "",
    path?,
    max_age=0L,
    domain?,
    same_site?,
    http_only~,
    secure~,
    partitioned~,
  )
}

///|
fn is_bearer_token_base_char(code : Int) -> Bool {
  (code >= 65 && code <= 90) ||
  (code >= 97 && code <= 122) ||
  (code >= 48 && code <= 57) ||
  code == 45 ||
  code == 46 ||
  code == 95 ||
  code == 126 ||
  code == 43 ||
  code == 47
}

///|
/// Whether `view` is an RFC 6750 `token68` credential: one or more base
/// characters followed by zero or more `=` padding characters.
fn bearer_token_is_valid(view : StringView) -> Bool {
  let length = view.length()
  if length == 0 {
    return false
  }
  let mut i = 0
  let mut has_base = false
  let mut padding = false
  while i < length {
    let code = view.unsafe_get(i).to_int()
    if code == 61 {
      padding = true
    } else {
      if padding || !is_bearer_token_base_char(code) {
        return false
      }
      has_base = true
    }
    i += 1
  }
  has_base
}

///|
/// Parse an `Authorization: Bearer ...` header into the opaque bearer token.
/// Returns `None` when the header is missing or the credential is not a valid
/// RFC 6750 `token68` value.
pub fn Context::bearer_token(self : Context) -> String? {
  let authorization = self.header("Authorization")
  let view = authorization.view()
  if !starts_with_ignore_ascii_case(view, "Bearer".view()) {
    return None
  }
  let rest = view[6:]
  let len = rest.length()
  let mut i = 0
  while i < len {
    let c = rest.unsafe_get(i).to_int()
    if c == 32 || c == 9 {
      i += 1
    } else {
      break
    }
  }
  if i == 0 {
    return None
  }
  let token = trim_ascii_space(rest[i:])
  if bearer_token_is_valid(token) {
    Some(token.to_owned())
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
  if !starts_with_ignore_ascii_case(view, "Basic".view()) {
    return None
  }
  let rest = view[5:]
  let mut i = 0
  let len = rest.length()
  while i < len {
    let c = rest.unsafe_get(i).to_int()
    if c == 32 || c == 9 {
      i += 1
    } else {
      break
    }
  }
  if i == 0 {
    return None
  }
  let encoded = trim_ascii_space(rest[i:])
  if encoded.is_empty() {
    return None
  }
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
fn parse_int_value(value : StringView) -> Int32? {
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
/// Parse a signed decimal integer into a 64-bit value.
///
/// Unlike `parse_int_value`, the magnitude is accumulated in `UInt64` so the
/// full `Int64` range, including `-9223372036854775808`, can be represented
/// without overflowing before the sign is applied. Leading `+`/`-` signs are
/// accepted; any other non-digit character, an empty body or a value outside
/// the signed 64-bit range yields `None`.
fn parse_int64_value(value : StringView) -> Int64? {
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
  let limit : UInt64 = if negative {
    9223372036854775808UL
  } else {
    9223372036854775807UL
  }
  let mut magnitude = 0UL
  while index < length {
    let digit = value.unsafe_get(index).to_int() - 48
    if digit < 0 || digit > 9 {
      return None
    }
    let digit64 = digit.to_uint64()
    if magnitude > (limit - digit64) / 10UL {
      return None
    }
    magnitude = magnitude * 10UL + digit64
    index = index + 1
  }
  let signed = if negative {
    (0UL - magnitude).to_int64()
  } else {
    magnitude.to_int64()
  }
  Some(signed)
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
///|
/// The percent-decoded route parameter `name` parsed as a signed 32-bit
/// integer. Returns `None` when the parameter is absent or out of range.
pub fn Context::param_int(self : Context, name : String) -> Int32? {
  parse_int_value(self.param_decoded(name).view())
}

///|
/// The percent-decoded route parameter `name` parsed as a signed 64-bit
/// integer. Returns `None` when the parameter is absent or does not fit in
/// `Int64`.
pub fn Context::param_int64(self : Context, name : String) -> Int64? {
  parse_int64_value(self.param_decoded(name).view())
}

///|
/// The percent-decoded route parameter `name` parsed as a boolean.
pub fn Context::param_bool(self : Context, name : String) -> Bool? {
  parse_bool_value(self.param_decoded(name).view())
}

///|
pub fn Context::query_int(self : Context, name : String) -> Int32? {
  parse_int_value(self.query(name).view())
}

///|
/// The query parameter `name` parsed as a signed 64-bit integer. Returns
/// `None` when the parameter is absent or does not fit in `Int64`.
pub fn Context::query_int64(self : Context, name : String) -> Int64? {
  parse_int64_value(self.query(name).view())
}

///|
pub fn Context::query_bool(self : Context, name : String) -> Bool? {
  parse_bool_value(self.query(name).view())
}

///|
/// Parse a finite decimal floating-point value, rejecting malformed input and
/// the non-finite spellings (`nan`, `inf`, `-inf`) that JSON cannot represent.
fn parse_float_value(value : StringView) -> Double? {
  let length = value.length()
  if length == 0 {
    return None
  }
  // Validate the literal before delegating to `parse_double`, which also
  // accepts leading signs and digit separators such as underscores. Accept an
  // optional leading sign, digits with an optional fractional part, and an
  // optional exponent; at least one mantissa digit is required.
  let mut index = 0
  let first = value.unsafe_get(0)
  if first == ('+' : UInt16) || first == ('-' : UInt16) {
    index = 1
  }
  let mut digits = 0
  while index < length {
    let code = value.unsafe_get(index).to_int()
    if code < 48 || code > 57 {
      break
    }
    digits = digits + 1
    index = index + 1
  }
  if index < length && value.unsafe_get(index) == ('.' : UInt16) {
    index = index + 1
    while index < length {
      let code = value.unsafe_get(index).to_int()
      if code < 48 || code > 57 {
        break
      }
      digits = digits + 1
      index = index + 1
    }
  }
  if digits == 0 {
    return None
  }
  if index < length &&
    (
      value.unsafe_get(index) == ('e' : UInt16) ||
      value.unsafe_get(index) == ('E' : UInt16)
    ) {
    index = index + 1
    if index < length &&
      (
        value.unsafe_get(index) == ('+' : UInt16) ||
        value.unsafe_get(index) == ('-' : UInt16)
      ) {
      index = index + 1
    }
    let mut exponent_digits = 0
    while index < length {
      let code = value.unsafe_get(index).to_int()
      if code < 48 || code > 57 {
        break
      }
      exponent_digits = exponent_digits + 1
      index = index + 1
    }
    if exponent_digits == 0 {
      return None
    }
  }
  if index != length {
    return None
  }
  // `parse_double` otherwise expects the first character to be a digit, `-` or
  // `.`; the explicit plus sign is only stripped for the actual conversion.
  let normalized = if first == ('+' : UInt16) { value[1:] } else { value }
  let parsed = @string.parse_double(normalized) catch { _ => return None }
  if parsed.is_nan() || parsed.is_inf() {
    None
  } else {
    Some(parsed)
  }
}

///|
/// The percent-decoded route parameter `name` parsed as a finite
/// floating-point number.
pub fn Context::param_float(self : Context, name : String) -> Double? {
  parse_float_value(self.param_decoded(name).view())
}

///|
/// The query parameter `name` parsed as a finite floating-point number.
pub fn Context::query_float(self : Context, name : String) -> Double? {
  parse_float_value(self.query(name).view())
}

///|
/// The url-encoded form field `name` parsed as an integer. Returns `None`
/// when the request body is not a form, the field is absent, or the value is
/// not a valid 32-bit integer.
pub fn Context::form_int(self : Context, name : String) -> Int32? {
  parse_int_value(self.form(name).view())
}

///|
/// The url-encoded form field `name` parsed as a signed 64-bit integer.
/// Returns `None` when the request body is not a form, the field is absent, or
/// the value does not fit in `Int64`.
pub fn Context::form_int64(self : Context, name : String) -> Int64? {
  parse_int64_value(self.form(name).view())
}

///|
/// The url-encoded form field `name` parsed as a boolean. Accepts the same
/// spellings as `Context::query_bool` (`true`/`false` and `1`/`0`).
pub fn Context::form_bool(self : Context, name : String) -> Bool? {
  parse_bool_value(self.form(name).view())
}

///|
/// The url-encoded form field `name` parsed as a finite floating-point number.
pub fn Context::form_float(self : Context, name : String) -> Double? {
  parse_float_value(self.form(name).view())
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
/// Whether JSON state contains `key`, including keys seeded from application
/// state. Unlike `Context::get_json`, this treats a stored JSON null as
/// present.
pub fn Context::has_json_state(self : Context, key : String) -> Bool {
  self.json_state.contains(key)
}

///|
/// Remove `key` from JSON state. Returns whether the key was present. Removing
/// a key seeded from application state only affects this request.
pub fn Context::remove_json_state(self : Context, key : String) -> Bool {
  match self.json_state.remove_and_get(key) {
    Some(_) => true
    None => false
  }
}

///|
/// Register `cleanup` to run when the request finishes, whether the handler
/// succeeded or failed. Cleanups run in reverse registration order and are
/// best-effort: a cleanup that raises does not stop the others.
pub fn Context::defer_cleanup(
  self : Context,
  cleanup : () -> Unit raise,
) -> Unit {
  self.cleanups.push(cleanup)
}

///|
/// Percent-encode an RFC 5987 `ext-value` payload. `url_encode` leaves the
/// RFC 3986 sub-delimiters `'` and `*` unescaped, but neither is an RFC 5987
/// `attr-char`, so a filename containing one would produce a malformed
/// `filename*` parameter.
fn encode_rfc5987_value(value : String) -> String {
  let encoded = url_encode(value)
  let view = encoded.view()
  let length = view.length()
  let mut needs_escape = false
  let mut scan = 0
  while scan < length {
    let code = view.unsafe_get(scan).to_int()
    if code == 39 || code == 42 {
      needs_escape = true
      break
    }
    scan = scan + 1
  }
  if !needs_escape {
    return encoded
  }
  let builder = StringBuilder(size_hint=length + 8)
  let mut i = 0
  while i < length {
    let code = view.unsafe_get(i).to_int()
    if code == 39 {
      builder.write_string("%27")
    } else if code == 42 {
      builder.write_string("%2A")
    } else {
      builder.write_char(code.unsafe_to_char())
    }
    i = i + 1
  }
  builder.to_string()
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
    encode_rfc5987_value(clean)
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
      Some(cleanup) => cleanup() catch { _ => () }
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
  clear_replaced_body_headers(self.response.headers)
  set_header_ignore_case(self.response.headers, "Content-Type", resolved_type)
  match download_name {
    Some(name) =>
      set_header_ignore_case(
        self.response.headers,
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
  set_header_ignore_case(
    self.response.headers,
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
  set_header_ignore_case(
    self.response.headers,
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
#inline
fn hex_digit(value : Int32) -> Int32 {
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
/// Encode `source` as UTF-8, replacing unpaired surrogates with U+FFFD so the
/// conversion is total for any `String`.
fn encode_utf8_lossy(source : StringView) -> Bytes {
  let length = source.length()
  let out : Array[Byte] = Array(capacity=length)
  let mut i = 0
  while i < length {
    let code = source.unsafe_get(i).to_int()
    if code >= 0xD800 &&
      code <= 0xDBFF &&
      i + 1 < length &&
      source.unsafe_get(i + 1).to_int() >= 0xDC00 &&
      source.unsafe_get(i + 1).to_int() <= 0xDFFF {
      let low = source.unsafe_get(i + 1).to_int()
      let full = 0x10000 + ((code - 0xD800) << 10) + (low - 0xDC00)
      out.push(((full >> 18) | 0xF0).to_byte())
      out.push((((full >> 12) & 0x3F) | 0x80).to_byte())
      out.push((((full >> 6) & 0x3F) | 0x80).to_byte())
      out.push(((full & 0x3F) | 0x80).to_byte())
      i = i + 2
      continue
    }
    let scalar = if code >= 0xD800 && code <= 0xDFFF { 0xFFFD } else { code }
    if scalar < 0x80 {
      out.push(scalar.to_byte())
    } else if scalar < 0x800 {
      out.push(((scalar >> 6) | 0xC0).to_byte())
      out.push(((scalar & 0x3F) | 0x80).to_byte())
    } else {
      out.push(((scalar >> 12) | 0xE0).to_byte())
      out.push((((scalar >> 6) & 0x3F) | 0x80).to_byte())
      out.push(((scalar & 0x3F) | 0x80).to_byte())
    }
    i = i + 1
  }
  Bytes::from_array(out)
}

///|
fn decode_url_impl(source : StringView, plus_as_space : Bool) -> String {
  let length = source.length()
  let mut ascii_only = true
  let mut needs_decoding = false
  let mut needs_surrogate_repair = false
  let mut i = 0
  // Scan once to choose between the ASCII and UTF-8 decoding paths.
  while i < length {
    let value = source.unsafe_get(i).to_int()
    if value > 127 {
      ascii_only = false
    } else if value == 37 || (value == 43 && plus_as_space) {
      needs_decoding = true
    }
    if value >= 0xD800 && value <= 0xDBFF {
      if i + 1 < length &&
        source.unsafe_get(i + 1).to_int() >= 0xDC00 &&
        source.unsafe_get(i + 1).to_int() <= 0xDFFF {
        i = i + 1
      } else {
        needs_surrogate_repair = true
      }
    } else if value >= 0xDC00 && value <= 0xDFFF {
      needs_surrogate_repair = true
    }
    i = i + 1
  }
  if !needs_decoding {
    // Without escapes the common case is a pure copy. A lone surrogate is not
    // valid text, so repair it the same way the percent-decoding path does.
    if !needs_surrogate_repair {
      return source.to_owned()
    }
    return @utf8.decode_lossy(encode_utf8_lossy(source))
  }
  if !ascii_only {
    return decode_url_bytes(encode_utf8_lossy(source), plus_as_space)
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
#inline
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
#inline
fn percent_hex_byte(value : Int32) -> Byte {
  if value < 10 {
    (b'0'.to_int() + value).to_byte()
  } else {
    (b'A'.to_int() + (value - 10)).to_byte()
  }
}

///|
#inline
fn write_percent_to(
  out : FixedArray[Byte],
  offset : Int32,
  value : Int32,
) -> Unit {
  out[offset] = b'%'
  out[offset + 1] = percent_hex_byte(value / 16)
  out[offset + 2] = percent_hex_byte(value % 16)
}

///|
/// Most recently encoded source string and its result.
let last_url_encode_source : Ref[String?] = Ref(None)

///|
let last_url_encode_value : Ref[String] = Ref("")

///|
pub fn url_encode(source : String) -> String {
  match last_url_encode_source.val {
    Some(cached) =>
      if physical_equal(cached, source) {
        return last_url_encode_value.val
      }
    None => ()
  }
  let view = source.view()
  let length = view.length()
  let mut start = 0
  while start < length && is_url_unreserved(view.unsafe_get(start).to_int()) {
    start = start + 1
  }
  if start == length {
    last_url_encode_source.val = Some(source)
    last_url_encode_value.val = source
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
  let result = @utf8.decode_lossy(out.unsafe_reinterpret_as_bytes()[:out_index])
  last_url_encode_source.val = Some(source)
  last_url_encode_value.val = result
  result
}

///|
let base64_alphabet : Bytes = b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"

///|
/// Character code (0-255) to 6-bit value for standard base64; `-1` marks every
/// character outside the alphabet.
let base64_lookup : FixedArray[Int32] = {
  let table = FixedArray::make(256, -1)
  for i = 0; i < 26; i = i + 1 {
    table[65 + i] = i
    table[97 + i] = i + 26
  }
  for i = 0; i < 10; i = i + 1 {
    table[48 + i] = i + 52
  }
  table[43] = 62
  table[47] = 63
  table
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
fn own_bytes_prefix(out : FixedArray[Byte], length : Int32) -> Bytes {
  if length == out.length() {
    out.unsafe_reinterpret_as_bytes()
  } else {
    Bytes::from_array(out[:length])
  }
}

///|
/// Most recently decoded base64 text and its result.
let last_base64_text : Ref[String?] = Ref(None)

///|
let last_base64_result : Ref[Bytes?] = Ref(None)

///|
let last_base64_valid : Ref[Bool] = Ref(false)

///|
/// Decode standard base64 text. Returns `None` for malformed input.
///
/// Padding may be omitted, but a stray `=` in the middle of the text is
/// rejected.
pub fn base64_decode(text : String) -> Bytes? {
  match last_base64_text.val {
    Some(cached) =>
      if last_base64_valid.val &&
        (physical_equal(cached, text) || cached == text) {
        return last_base64_result.val
      }
    None => ()
  }
  let result = base64_decode_view(text.view())
  last_base64_text.val = Some(text)
  last_base64_result.val = result
  last_base64_valid.val = true
  result
}

///|
/// Look up a character code in a base64 value table. Characters outside the
/// table (anything past Latin-1) are not part of any base64 alphabet, so they
/// map to `-1` instead of indexing out of bounds.
#inline
fn base64_table_value(table : FixedArray[Int32], code : UInt16) -> Int32 {
  let index = code.to_int()
  if index < table.length() {
    table[index]
  } else {
    -1
  }
}

///|
/// `base64_decode` core: `table` maps a character code to its 6-bit value, or
/// `-1` when the character is not in the alphabet.
fn base64_decode_core(view : StringView, table : FixedArray[Int32]) -> Bytes? {
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
  // Decode four alphabet characters at a time. Invalid or padded groups fall
  // back below.
  while i + 4 <= length {
    let first_code = view.unsafe_get(i).to_int()
    let second_code = view.unsafe_get(i + 1).to_int()
    let third_code = view.unsafe_get(i + 2).to_int()
    let fourth_code = view.unsafe_get(i + 3).to_int()
    if first_code >= 256 ||
      second_code >= 256 ||
      third_code >= 256 ||
      fourth_code >= 256 {
      break
    }
    let first = table[first_code]
    let second = table[second_code]
    let third = table[third_code]
    let fourth = table[fourth_code]
    if first < 0 || second < 0 || third < 0 || fourth < 0 {
      break
    }
    out[out_index] = ((first << 2) | (second >> 4)).to_byte()
    out[out_index + 1] = (((second & 15) << 4) | (third >> 2)).to_byte()
    out[out_index + 2] = (((third & 3) << 6) | fourth).to_byte()
    i = i + 4
    out_index = out_index + 3
  }
  while i < length {
    let remaining = length - i
    let first = base64_table_value(table, view.unsafe_get(i))
    let second = if remaining >= 2 {
      base64_table_value(table, view.unsafe_get(i + 1))
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
      let third = base64_table_value(table, third_raw)
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
    let third = base64_table_value(table, third_raw)
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
    let fourth = base64_table_value(table, fourth_raw)
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
/// `base64_decode` for a `StringView`.
fn base64_decode_view(view : StringView) -> Bytes? {
  base64_decode_core(view, base64_lookup)
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
    "docx", "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
  ),
  ("xls", "application/vnd.ms-excel"),
  ("xlsx", "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"),
  ("ppt", "application/vnd.ms-powerpoint"),
  (
    "pptx", "application/vnd.openxmlformats-officedocument.presentationml.presentation",
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
/// Most recently resolved file path and its media type.
let last_mime_path : Ref[String?] = Ref(None)

///|
let last_mime_value : Ref[String] = Ref("")

///|
/// The media type associated with the extension of `path`.
///
/// Matching is case-insensitive and only the last path segment is considered.
/// A URL query string or fragment is ignored, so `mime_type_for` works for both
/// filesystem paths (`"public/app.js"`) and URLs (`"/app.js?v=1"`). Paths
/// without an extension get `"application/octet-stream"`.
pub fn mime_type_for(path : String) -> String {
  match last_mime_path.val {
    Some(cached) =>
      if physical_equal(cached, path) {
        return last_mime_value.val
      }
    None => ()
  }
  let view = path.view()
  // A query or fragment is not part of the extension, even though it may
  // itself contain a dot (`app.js?v=1.2`).
  let mut end = view.length()
  let mut scan = 0
  while scan < end {
    let code = view.unsafe_get(scan)
    if code == ('?' : UInt16) || code == ('#' : UInt16) {
      end = scan
      break
    }
    scan = scan + 1
  }
  let mut dot = -1
  let mut i = end - 1
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
  let result = if dot >= 0 {
    let extension = view[dot + 1:end]
    if has_ascii_upper(extension) {
      let lower = extension.to_lower().view()
      mime_for_extension(lower)
    } else {
      mime_for_extension(extension)
    }
  } else {
    mime_for_extension("")
  }
  last_mime_path.val = Some(path)
  last_mime_value.val = result
  result
}

///|
/// Estimated capacity for a url-encoded result map, based on the source length.
fn urlencoded_capacity(source : StringView) -> Int32 {
  let estimate = source.length() >> 3
  if estimate < 4 {
    4
  } else if estimate > 256 {
    256
  } else {
    estimate
  }
}

///|
fn parse_urlencoded_view(source : StringView) -> Map[String, String] {
  let result : Map[String, String] = Map(
    [],
    capacity=urlencoded_capacity(source),
  )
  let length = source.length()
  let mut pos = 0
  while pos <= length {
    let mut end = pos
    let mut eq = -1
    let mut key_escaped = false
    let mut value_escaped = false
    while end < length {
      let code = source.unsafe_get(end)
      if code == ('&' : UInt16) {
        break
      }
      if code == ('=' : UInt16) {
        if eq < 0 {
          eq = end
        }
      } else if code == ('%' : UInt16) || code == ('+' : UInt16) {
        if eq < 0 {
          key_escaped = true
        } else {
          value_escaped = true
        }
      }
      end = end + 1
    }
    if end > pos {
      if eq >= 0 {
        let key = if key_escaped {
          decode_url(source[pos:eq])
        } else {
          source[pos:eq].to_owned()
        }
        let value = if value_escaped {
          decode_url(source[eq + 1:end])
        } else {
          source[eq + 1:end].to_owned()
        }
        result.set(key, value)
      } else {
        let key = if key_escaped {
          decode_url(source[pos:end])
        } else {
          source[pos:end].to_owned()
        }
        result.set(key, "")
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
/// Most recently parsed url-encoded text and the owned map it produced.
/// Callers always receive a copy so the cached parse cannot be mutated.
let last_parsed_urlencoded_source : Ref[String?] = Ref(None)

///|
let last_parsed_urlencoded_map : Ref[Map[String, String]?] = Ref(None)

///|
let last_parsed_urlencoded_valid : Ref[Bool] = Ref(false)

///|
pub fn parse_urlencoded(source : String) -> Map[String, String] {
  match last_parsed_urlencoded_source.val {
    Some(cached) =>
      if last_parsed_urlencoded_valid.val &&
        (physical_equal(cached, source) || cached == source) {
        match last_parsed_urlencoded_map.val {
          Some(map) => return map.copy()
          None => ()
        }
      }
    None => ()
  }
  let parsed = parse_urlencoded_view(source)
  if source.length() <= PARSE_CACHE_MAX_KEY {
    last_parsed_urlencoded_source.val = Some(source)
    last_parsed_urlencoded_map.val = Some(parsed.copy())
    last_parsed_urlencoded_valid.val = true
  }
  parsed
}

///|
/// Parse a url-encoded source into every value of each key, preserving the
/// order in which the pairs appear.
fn parse_urlencoded_multi(source : StringView) -> Map[String, Array[String]] {
  let result : Map[String, Array[String]] = Map(
    [],
    capacity=urlencoded_capacity(source),
  )
  // Decoded spelling of keys that contain `%` or `+`. Keys without either
  // character keep their raw spelling.
  let escaped_keys : Map[StringView, String] = Map([], capacity=4)
  let length = source.length()
  let mut pos = 0
  while pos <= length {
    let mut end = pos
    let mut eq = -1
    let mut key_escaped = false
    let mut value_escaped = false
    while end < length {
      let code = source.unsafe_get(end)
      if code == ('&' : UInt16) {
        break
      }
      if code == ('=' : UInt16) {
        if eq < 0 {
          eq = end
        }
      } else if code == ('%' : UInt16) || code == ('+' : UInt16) {
        if eq < 0 {
          key_escaped = true
        } else {
          value_escaped = true
        }
      }
      end = end + 1
    }
    if end > pos {
      let raw_key = if eq >= 0 { source[pos:eq] } else { source[pos:end] }
      let value = if eq >= 0 {
        if value_escaped {
          decode_url(source[eq + 1:end])
        } else {
          source[eq + 1:end].to_owned()
        }
      } else {
        ""
      }
      // A key with neither `%` nor `+` uses its raw spelling; escaped keys are
      // decoded before the lookup, since the map stores decoded spellings.
      if !key_escaped {
        match result.get_from_string(raw_key) {
          Some(values) => values.push(value)
          None => result.set(raw_key.to_owned(), [value])
        }
      } else {
        let key = match escaped_keys.get(raw_key) {
          Some(key) => key
          None => {
            let key = decode_url(raw_key)
            escaped_keys.set(raw_key, key)
            key
          }
        }
        match result.get(key) {
          Some(values) => values.push(value)
          None => result.set(key, [value])
        }
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
  start : Int32,
  end : Int32,
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
  if !name_needs_raw(key) {
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
  match path_query_index(path) {
    Some(index) =>
      if name_needs_raw(name.view()) {
        query_param(query_source_view(path, index), name)
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
  match path_query_index(self.request.path) {
    Some(index) =>
      if name_needs_raw(name.view()) {
        match query_param_opt(
          query_source_view(self.request.path, index),
          name,
        ) {
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
/// The parsed query string, keyed by name. The result is a fresh copy, so
/// mutating it cannot disturb a later request that carries the same query.
pub fn Context::queries(self : Context) -> Map[String, String] {
  let path = self.request.path
  match path_query_index(path) {
    Some(index) => query_map_lookup(path, index).copy()
    None => Map([])
  }
}

///|
/// All query parameters, keyed by name, with every repeated value preserved in
/// appearance order. Unlike `Context::queries`, which keeps only the first
/// value of a repeated parameter, this lets a caller enumerate the complete
/// query without knowing its keys in advance.
///
/// Both the map and its arrays are fresh copies, so mutating the result cannot
/// disturb a later request that carries the same query.
pub fn Context::query_all(
  self : Context,
) -> Map[String, Array[String]] {
  let path = self.request.path
  match path_query_index(path) {
    Some(index) => copy_values_map(query_multi_lookup(path, index))
    None => Map([])
  }
}

///|
/// Whether the query string carries `name`, matching the same decoded and raw
/// spellings as `Context::query`.
///
/// Unlike `Context::query`, this distinguishes an absent parameter from one
/// that is present with an empty value (`?flag` or `?flag=`).
pub fn Context::has_query(self : Context, name : String) -> Bool {
  if name == "" {
    return false
  }
  let path = self.request.path
  match path_query_index(path) {
    Some(index) =>
      if name_needs_raw(name.view()) {
        query_param_opt(query_source_view(path, index), name) is Some(_)
      } else {
        query_map_lookup(path, index).contains(name)
      }
    None => false
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
/// they appear in the query string. The result is a fresh array, so mutating
/// it cannot disturb a later request that carries the same query.
pub fn Context::query_values(self : Context, name : String) -> Array[String] {
  match path_query_index(self.request.path) {
    Some(index) =>
      if name_needs_raw(name.view()) {
        collect_values(query_source_view(self.request.path, index), name)
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
/// `application/x-www-form-urlencoded`. The result is a fresh array, so
/// mutating it cannot disturb a later request that carries the same body.
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
/// The parsed url-encoded form body, keyed by name. The result is a fresh
/// copy, so mutating it cannot disturb a later request that carries the same
/// body.
pub fn Context::form_map(self : Context) -> Map[String, String] {
  if !self.is_form() {
    return Map([])
  }
  form_map_lookup(self.request.body).copy()
}

///|
/// All url-encoded form fields, keyed by name, with every repeated value
/// preserved in appearance order. Returns an empty map when the body is not
/// `application/x-www-form-urlencoded`.
///
/// Both the map and its arrays are fresh copies, so mutating the result cannot
/// disturb a later request that carries the same body.
pub fn Context::form_all(
  self : Context,
) -> Map[String, Array[String]] {
  if !self.is_form() {
    return Map([])
  }
  copy_values_map(form_values_lookup(self.request.body))
}

///|
/// Whether the url-encoded form body carries `name`, matching the same decoded
/// and raw spellings as `Context::form`. Returns `false` for another content
/// type, just like the other form accessors.
///
/// Unlike `Context::form`, this distinguishes an absent field from one that is
/// present with an empty value (`flag` or `flag=`).
pub fn Context::has_form(self : Context, name : String) -> Bool {
  if name == "" || !self.is_form() {
    return false
  }
  if name_needs_raw(name.view()) {
    query_param_opt(self.request.body.view(), name) is Some(_)
  } else {
    form_map_lookup(self.request.body).contains(name)
  }
}

///|
/// Most recently normalized `Content-Type` header value.
let last_content_type_header : Ref[String?] = Ref(None)

///|
let last_content_type_value : Ref[String] = Ref("")

///|
/// Normalized media types keyed by their raw `Content-Type` header value.
let content_type_cache : Map[String, String] = Map([])

///|
/// Recency ticks for `content_type_cache`.
let content_type_cache_ages : Map[String, Int32] = Map([])

///|
fn parsed_content_type(header : String) -> String {
  match last_content_type_header.val {
    Some(cached_header) =>
      if physical_equal(cached_header, header) {
        return last_content_type_value.val
      }
    None => ()
  }
  match content_type_cache.get(header) {
    Some(cached) => {
      cache_touch(content_type_cache_ages, header)
      last_content_type_header.val = Some(header)
      last_content_type_value.val = cached
      return cached
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
  if header.length() <= PARSE_CACHE_MAX_KEY {
    parse_cache_set(content_type_cache, content_type_cache_ages, header, result)
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
/// The `name` and `filename` parameters of a `Content-Disposition` value,
/// extracted in one pass. `filename` prefers a well-formed RFC 8187
/// `filename*`, falling back to the plain parameter.
priv struct DispositionNames {
  name : String
  filename : String
}

///|
fn unescape_quoted_parameter(raw : StringView) -> String {
  let length = raw.length()
  let builder = StringBuilder(size_hint=length)
  let mut i = 0
  while i < length {
    let unit = raw.unsafe_get(i)
    if unit == ('\\' : UInt16) && i + 1 < length {
      builder.write_char(raw.unsafe_get(i + 1).to_int().unsafe_to_char())
      i = i + 2
    } else {
      builder.write_char(unit.to_int().unsafe_to_char())
      i = i + 1
    }
  }
  builder.to_string()
}

///|
fn disposition_names(value : StringView) -> DispositionNames {
  let length = value.length()
  let mut pos = 0
  while pos < length && value.unsafe_get(pos) != (';' : UInt16) {
    pos = pos + 1
  }
  let mut name : String? = None
  let mut filename : String? = None
  let mut filename_ext : String? = None
  while pos < length {
    pos = pos + 1
    while pos < length &&
          (
            value.unsafe_get(pos) == (' ' : UInt16) ||
            value.unsafe_get(pos) == ('\t' : UInt16)
          ) {
      pos = pos + 1
    }
    let name_start = pos
    while pos < length &&
          value.unsafe_get(pos) != ('=' : UInt16) &&
          value.unsafe_get(pos) != (';' : UInt16) {
      pos = pos + 1
    }
    let attribute = trim_ascii_space(value[name_start:pos])
    if pos < length && value.unsafe_get(pos) == ('=' : UInt16) {
      pos = pos + 1
      while pos < length &&
            (
              value.unsafe_get(pos) == (' ' : UInt16) ||
              value.unsafe_get(pos) == ('\t' : UInt16)
            ) {
        pos = pos + 1
      }
      let parsed : String? = if pos < length &&
        value.unsafe_get(pos) == ('"' : UInt16) {
        let quoted_start = pos + 1
        let mut end = quoted_start
        while end < length {
          let unit = value.unsafe_get(end)
          if unit == ('\\' : UInt16) && end + 1 < length {
            end = end + 2
          } else if unit == ('"' : UInt16) {
            break
          } else {
            end = end + 1
          }
        }
        let result = unescape_quoted_parameter(value[quoted_start:end])
        pos = if end < length { end + 1 } else { end }
        Some(result)
      } else {
        let value_start = pos
        while pos < length && value.unsafe_get(pos) != (';' : UInt16) {
          pos = pos + 1
        }
        Some(trim_ascii_space(value[value_start:pos]).to_owned())
      }
      if attribute.equal_ignore_ascii_case("name".view()) {
        if name is None {
          name = parsed
        }
      } else if attribute.equal_ignore_ascii_case("filename".view()) {
        if filename is None {
          filename = parsed
        }
      } else if attribute.equal_ignore_ascii_case("filename*".view()) {
        if filename_ext is None {
          filename_ext = parsed
        }
      }
    }
    while pos < length && value.unsafe_get(pos) != (';' : UInt16) {
      pos = pos + 1
    }
  }
  let plain_filename = match filename {
    Some(value) => value
    None => ""
  }
  let resolved_filename = match filename_ext {
    Some(raw) => {
      let raw_view = raw.view()
      match raw_view.find("'") {
        Some(first) =>
          if raw_view[:first].equal_ignore_ascii_case("utf-8".view()) {
            let rest = raw_view[first + 1:]
            match rest.find("'") {
              Some(second) => decode_url_path(rest[second + 1:])
              None => plain_filename
            }
          } else {
            plain_filename
          }
        None => plain_filename
      }
    }
    None => plain_filename
  }
  {
    name: match name {
      Some(value) => value
      None => ""
    },
    filename: resolved_filename,
  }
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
  /// The part's payload as bytes, exactly as it arrived. `data` is the lossy
  /// text view of the same bytes.
  data_bytes : Bytes
}

///|
/// Decode bytes without losing any information.
///
/// Well-formed UTF-8 becomes the text it encodes. A byte that is not part of a
/// valid sequence is mapped to the private code unit `0xDC00 + byte`, the same
/// escaping `WTF-8` uses, which `encode_utf8_lossless` turns back into that
/// byte. Unlike the standard decoders the result may therefore hold lone
/// surrogates, so it must only be re-encoded with the matching encoder.
fn decode_utf8_lossless(bytes : Bytes) -> String {
  let result = StringBuilder()
  let length = bytes.length()
  let mut i = 0
  while i < length {
    let b0 = bytes[i].to_int()
    if b0 < 0x80 {
      result.write_char(b0.unsafe_to_char())
      i = i + 1
    } else if b0 >= 0xC2 && b0 <= 0xDF {
      if i + 1 < length {
        let b1 = bytes[i + 1].to_int()
        if b1 >= 0x80 && b1 <= 0xBF {
          let code = ((b0 & 0x1F) << 6) | (b1 & 0x3F)
          result.write_char(code.unsafe_to_char())
          i = i + 2
        } else {
          result.write_char((0xDC00 + b0).unsafe_to_char())
          i = i + 1
        }
      } else {
        result.write_char((0xDC00 + b0).unsafe_to_char())
        i = i + 1
      }
    } else if b0 >= 0xE0 &&
      b0 <= 0xEF &&
      i + 2 < length &&
      !(b0 == 0xE0 && bytes[i + 1].to_int() < 0xA0) &&
      !(b0 == 0xED && bytes[i + 1].to_int() > 0x9F) &&
      bytes[i + 1].to_int() >= 0x80 &&
      bytes[i + 1].to_int() <= 0xBF &&
      bytes[i + 2].to_int() >= 0x80 &&
      bytes[i + 2].to_int() <= 0xBF {
      let b1 = bytes[i + 1].to_int()
      let b2 = bytes[i + 2].to_int()
      let code = ((b0 & 0x0F) << 12) | ((b1 & 0x3F) << 6) | (b2 & 0x3F)
      result.write_char(code.unsafe_to_char())
      i = i + 3
    } else if b0 >= 0xF0 &&
      b0 <= 0xF4 &&
      i + 3 < length &&
      !(b0 == 0xF0 && bytes[i + 1].to_int() < 0x90) &&
      !(b0 == 0xF4 && bytes[i + 1].to_int() > 0x8F) &&
      bytes[i + 1].to_int() >= 0x80 &&
      bytes[i + 1].to_int() <= 0xBF &&
      bytes[i + 2].to_int() >= 0x80 &&
      bytes[i + 2].to_int() <= 0xBF &&
      bytes[i + 3].to_int() >= 0x80 &&
      bytes[i + 3].to_int() <= 0xBF {
      let b1 = bytes[i + 1].to_int()
      let b2 = bytes[i + 2].to_int()
      let b3 = bytes[i + 3].to_int()
      let code = ((b0 & 0x07) << 18) |
        ((b1 & 0x3F) << 12) |
        ((b2 & 0x3F) << 6) |
        (b3 & 0x3F)
      let code = code - 0x10000
      result.write_char(((code >> 10) + 0xD800).unsafe_to_char())
      result.write_char(((code & 0x3FF) + 0xDC00).unsafe_to_char())
      i = i + 4
    } else {
      result.write_char((0xDC00 + b0).unsafe_to_char())
      i = i + 1
    }
  }
  result.to_string()
}

///|
/// Recover a part's exact bytes and its well-formed text.
///
/// `raw_data` is the lossless slice from the raw body (supplementary code
/// units intact, invalid bytes escaped), so `data_bytes` returns the payload
/// byte for byte while `data` is the lossy text handlers already expect. A
/// part parsed from `Request::body` (no raw body available) falls back to
/// re-encoding its text.
/// Preserve a part's exact bytes together with its well-formed text.
///
/// `raw_data` is the lossless slice from the raw body (supplementary code
/// units intact, invalid bytes escaped), so the bytes come back byte for byte
/// while the text is the lossy view handlers already expect. A part parsed
/// without a raw body falls back to re-encoding its text.
fn resolve_part_bytes(data : String, raw_data : String?) -> (Bytes, String) {
  match raw_data {
    Some(raw) => {
      let bytes = encode_utf8_lossless(raw)
      (bytes, @utf8.decode_lossy(bytes))
    }
    None => {
      let bytes = encode_utf8_lossy(data.view())
      (bytes, @utf8.decode_lossy(bytes))
    }
  }
}

///|
/// A high surrogate followed by a low surrogate is a supplementary character;
/// any other code unit in `0xDC00..=0xDCFF` stands for the single byte
/// `code - 0xDC00`. Valid text that contains no such escape encodes to its
/// normal UTF-8 bytes.
fn encode_utf8_lossless(text : String) -> Bytes {
  let out : Array[Byte] = Array(capacity=text.length())
  let length = text.length()
  let mut i = 0
  while i < length {
    let code = text.unsafe_get(i).to_int()
    if code >= 0xD800 &&
      code <= 0xDBFF &&
      i + 1 < length &&
      text.unsafe_get(i + 1).to_int() >= 0xDC00 &&
      text.unsafe_get(i + 1).to_int() <= 0xDFFF {
      let low = text.unsafe_get(i + 1).to_int()
      let full = 0x10000 + ((code - 0xD800) << 10) + (low - 0xDC00)
      out.push(((full >> 18) | 0xF0).to_byte())
      out.push((((full >> 12) & 0x3F) | 0x80).to_byte())
      out.push((((full >> 6) & 0x3F) | 0x80).to_byte())
      out.push(((full & 0x3F) | 0x80).to_byte())
      i = i + 2
    } else if code >= 0xDC00 && code <= 0xDCFF {
      out.push((code - 0xDC00).to_byte())
      i = i + 1
    } else if code < 0x80 {
      out.push(code.to_byte())
      i = i + 1
    } else if code < 0x800 {
      out.push(((code >> 6) | 0xC0).to_byte())
      out.push(((code & 0x3F) | 0x80).to_byte())
      i = i + 1
    } else {
      out.push(((code >> 12) | 0xE0).to_byte())
      out.push((((code >> 6) & 0x3F) | 0x80).to_byte())
      out.push(((code & 0x3F) | 0x80).to_byte())
      i = i + 1
    }
  }
  Bytes::from_array(out)
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
        (
          view.unsafe_get(index) == (' ' : UInt16) ||
          view.unsafe_get(index) == ('\t' : UInt16)
        ) {
    index = index + 1
  }
  if index >= length {
    // A bare delimiter at end of input is neither a part separator followed
    // by headers nor a close-delimiter (`--boundary--`), so it cannot
    // terminate a multipart body.
    return false
  }
  let code = view.unsafe_get(index)
  if code == ('\r' : UInt16) {
    // A delimiter line ends with CRLF, not with a bare CR. Data can legitimately
    // contain CR bytes, so treating a lone CR as a line break would split a
    // payload whose text merely starts with the boundary spelling.
    return index + 1 < length && view.unsafe_get(index + 1) == ('\n' : UInt16)
  }
  if code == ('\n' : UInt16) {
    return true
  }
  if code == ('-' : UInt16) {
    if index + 1 >= length || view.unsafe_get(index + 1) != ('-' : UInt16) {
      return false
    }
    let mut tail = index + 2
    while tail < length &&
          (
            view.unsafe_get(tail) == (' ' : UInt16) ||
            view.unsafe_get(tail) == ('\t' : UInt16)
          ) {
      tail = tail + 1
    }
    if tail >= length {
      return true
    }
    let tail_code = view.unsafe_get(tail)
    if tail_code == ('\r' : UInt16) {
      return tail + 1 < length &&
        view.unsafe_get(tail + 1) == ('\n' : UInt16)
    }
    return tail_code == ('\n' : UInt16)
  }
  false
}

///|
/// Prefix-function table for the delimiter scans below: entry `i` is the length
/// of the longest proper prefix of `needle[:i+1]` that is also a suffix of it.
fn delimiter_match_table(needle : StringView) -> Array[Int32] {
  let length = needle.length()
  let table : Array[Int32] = Array::make(length, 0)
  let mut matched = 0
  let mut index = 1
  while index < length {
    while matched > 0 && needle.unsafe_get(index) != needle.unsafe_get(matched) {
      matched = table[matched - 1]
    }
    if needle.unsafe_get(index) == needle.unsafe_get(matched) {
      matched = matched + 1
    }
    table[index] = matched
    index = index + 1
  }
  table
}

///|
/// First index at or after `start` where `needle` starts a line and is
/// terminated by whitespace, a line break or `--`. The precomputed
/// prefix-function `table` guides a single forward scan.
fn find_terminated_delimiter(
  view : StringView,
  needle : StringView,
  table : Array[Int32],
  start : Int32,
) -> Int32? {
  let needle_length = needle.length()
  if needle_length == 0 {
    return Some(start)
  }
  let length = view.length()
  let mut matched = 0
  let mut index = start
  while index < length {
    let code = view.unsafe_get(index)
    while matched > 0 && code != needle.unsafe_get(matched) {
      matched = table[matched - 1]
    }
    if code == needle.unsafe_get(matched) {
      matched = matched + 1
    }
    if matched == needle_length {
      let match_start = index + 1 - needle_length
      if (match_start == 0 ||
          view.unsafe_get(match_start - 1) == ('\n' : UInt16)) &&
        delimiter_is_terminated(view, index + 1) {
        return Some(match_start)
      }
      matched = table[matched - 1]
    }
    index = index + 1
  }
  None
}

///|
/// Find the earliest position where either the CRLF-prefixed or the LF-prefixed
/// part delimiter starts and is properly terminated. Both needles are matched
/// in a single forward pass; because the CRLF prefix is one byte longer, a CRLF
/// match ending no later than an LF match also starts no later than it, so the
/// first terminated completion in scan order is the earliest match.
fn find_part_delimiter(
  view : StringView,
  crlf_delimiter : StringView,
  lf_delimiter : StringView,
  crlf_table : Array[Int32],
  lf_table : Array[Int32],
  start : Int32,
) -> Int32? {
  let lf_length = lf_delimiter.length()
  if lf_length == 0 {
    return Some(start)
  }
  let crlf_length = crlf_delimiter.length()
  let length = view.length()
  let mut lf_matched = 0
  let mut crlf_matched = 0
  let mut index = start
  while index < length {
    let code = view.unsafe_get(index)
    while crlf_matched > 0 && code != crlf_delimiter.unsafe_get(crlf_matched) {
      crlf_matched = crlf_table[crlf_matched - 1]
    }
    if code == crlf_delimiter.unsafe_get(crlf_matched) {
      crlf_matched = crlf_matched + 1
    }
    if crlf_matched == crlf_length {
      let match_start = index + 1 - crlf_length
      if delimiter_is_terminated(view, index + 1) {
        return Some(match_start)
      }
      crlf_matched = crlf_table[crlf_matched - 1]
    }
    while lf_matched > 0 && code != lf_delimiter.unsafe_get(lf_matched) {
      lf_matched = lf_table[lf_matched - 1]
    }
    if code == lf_delimiter.unsafe_get(lf_matched) {
      lf_matched = lf_matched + 1
    }
    if lf_matched == lf_length {
      let match_start = index + 1 - lf_length
      if delimiter_is_terminated(view, index + 1) {
        return Some(match_start)
      }
      lf_matched = lf_table[lf_matched - 1]
    }
    index = index + 1
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
  let lower_first = if first >= 65 && first <= 90 { first + 32 } else { first }
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
          let lower_left = if left >= 65 && left <= 90 {
            left + 32
          } else {
            left
          }
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
/// Look up a `;`-separated parameter such as `boundary` or `filename` in a
/// header value, honoring quoted string values.
///
/// The first segment (the media type or disposition itself) is skipped and
/// attribute names are read as whole tokens, so a name that only appears
/// inside another quoted value is never mistaken for a parameter.
fn header_parameter(value : StringView, name : String) -> String? {
  let length = value.length()
  let target = name.view()
  let mut pos = 0
  while pos < length && value.unsafe_get(pos) != (';' : UInt16) {
    pos = pos + 1
  }
  while pos < length {
    pos = pos + 1
    while pos < length &&
          (
            value.unsafe_get(pos) == (' ' : UInt16) ||
            value.unsafe_get(pos) == ('\t' : UInt16)
          ) {
      pos = pos + 1
    }
    let name_start = pos
    while pos < length &&
          value.unsafe_get(pos) != ('=' : UInt16) &&
          value.unsafe_get(pos) != (';' : UInt16) {
      pos = pos + 1
    }
    let attribute = trim_ascii_space(value[name_start:pos])
    if pos < length && value.unsafe_get(pos) == ('=' : UInt16) {
      pos = pos + 1
      while pos < length &&
            (
              value.unsafe_get(pos) == (' ' : UInt16) ||
              value.unsafe_get(pos) == ('\t' : UInt16)
            ) {
        pos = pos + 1
      }
      let parsed : String? = if pos < length &&
        value.unsafe_get(pos) == ('"' : UInt16) {
        let quoted_start = pos + 1
        let mut end = quoted_start
        while end < length {
          let unit = value.unsafe_get(end)
          if unit == ('\\' : UInt16) && end + 1 < length {
            end = end + 2
          } else if unit == ('"' : UInt16) {
            break
          } else {
            end = end + 1
          }
        }
        let result = unescape_quoted_parameter(value[quoted_start:end])
        pos = if end < length { end + 1 } else { end }
        Some(result)
      } else {
        let value_start = pos
        while pos < length && value.unsafe_get(pos) != (';' : UInt16) {
          pos = pos + 1
        }
        Some(trim_ascii_space(value[value_start:pos]).to_owned())
      }
      if attribute.equal_ignore_ascii_case(target) {
        return parsed
      }
    }
    while pos < length && value.unsafe_get(pos) != (';' : UInt16) {
      pos = pos + 1
    }
  }
  None
}

///|
/// Most recently parsed `Content-Type` value and the boundary it resolved to.
let last_boundary_content_type : Ref[String?] = Ref(None)

///|
let last_boundary_value : Ref[String?] = Ref(None)

///|
pub fn multipart_boundary(content_type : String) -> String? {
  match last_boundary_content_type.val {
    Some(cached) =>
      if physical_equal(cached, content_type) {
        return last_boundary_value.val
      }
    None => ()
  }
  let view = content_type.view()
  let length = view.length()
  let mut pos = 0
  while pos < length && view.unsafe_get(pos) != (';' : UInt16) {
    pos = pos + 1
  }
  let media_type = trim_ascii_space(view[:pos])
  let result = if media_type.equal_ignore_ascii_case(
      "multipart/form-data".view(),
    ) {
    header_parameter(view, "boundary")
  } else {
    None
  }
  last_boundary_content_type.val = Some(content_type)
  last_boundary_value.val = result
  result
}

///|
/// Two most recently indexed header maps, their sizes and their lower-cased
/// name indexes. The index maps a lower-cased header name to the spelling
/// stored in the map. Only positive entries are cached: the map can be mutated
/// in place with its size unchanged, so a remembered absence could be stale,
/// while a remembered spelling is always re-validated against the map before it
/// is trusted.
let header_index_map0 : Ref[Map[String, String]?] = Ref(None)

///|
let header_index_size0 : Ref[Int32] = Ref(-1)

///|
let header_index_value0 : Ref[Map[String, String]?] = Ref(None)

///|
let header_index_map1 : Ref[Map[String, String]?] = Ref(None)

///|
let header_index_size1 : Ref[Int32] = Ref(-1)

///|
let header_index_value1 : Ref[Map[String, String]?] = Ref(None)

///|
/// Slot that receives the next rebuilt index.
let header_index_next : Ref[Int32] = Ref(0)

///|
/// Lower-cased spellings of recently seen header names.
let header_lower_cache : Map[String, String] = Map([])

///|
/// Recency ticks for `header_lower_cache`.
let header_lower_cache_ages : Map[String, Int32] = Map([])

///|
/// Maximum number of header names tracked by `header_lower_cache`.
const HEADER_LOWER_CACHE_LIMIT : Int32 = 128

///|
/// Lower-case a header name only when it contains upper-case letters. The
/// lower-cased form is kept in a bounded cache.
fn header_name_lower(name : String) -> String {
  if !has_ascii_upper(name.view()) {
    return name
  }
  match header_lower_cache.get(name) {
    Some(lower) => {
      cache_touch(header_lower_cache_ages, name)
      lower
    }
    None => {
      let lower = name.to_lower()
      cache_set(
        header_lower_cache,
        header_lower_cache_ages,
        HEADER_LOWER_CACHE_LIMIT,
        name,
        lower,
      )
      lower
    }
  }
}

///|
/// The lower-cased name index for `headers`, plus whether it was built during
/// this call (in which case it reflects the map's current contents exactly).
fn header_index_for(
  headers : Map[String, String],
) -> (Map[String, String], Bool) {
  match header_index_map0.val {
    Some(cached) =>
      if physical_equal(cached, headers) &&
        header_index_size0.val == headers.length() {
        match header_index_value0.val {
          Some(index) => return (index, false)
          None => ()
        }
      }
    None => ()
  }
  match header_index_map1.val {
    Some(cached) =>
      if physical_equal(cached, headers) &&
        header_index_size1.val == headers.length() {
        match header_index_value1.val {
          Some(index) => return (index, false)
          None => ()
        }
      }
    None => ()
  }
  let index : Map[String, String] = Map([], capacity=headers.length())
  for name, _ in headers {
    let lower = header_name_lower(name)
    if !index.contains(lower) {
      index.set(lower, name)
    }
  }
  let size = headers.length()
  if header_index_next.val == 0 {
    header_index_map0.val = Some(headers)
    header_index_size0.val = size
    header_index_value0.val = Some(index)
    header_index_next.val = 1
  } else {
    header_index_map1.val = Some(headers)
    header_index_size1.val = size
    header_index_value1.val = Some(index)
    header_index_next.val = 0
  }
  (index, true)
}

///|
fn get_header_ignore_case(
  headers : Map[String, String],
  name : String,
) -> String? {
  if headers.is_empty() {
    return None
  }
  match headers.get(name) {
    Some(value) => return Some(value)
    None => ()
  }
  let (index, fresh) = header_index_for(headers)
  let lower = header_name_lower(name)
  match index.get(lower) {
    Some(actual) =>
      match headers.get(actual) {
        Some(value) => return Some(value)
        None => ()
      }
    None =>
      // The index was built from the current contents, so a miss there means
      // no spelling of `name` is present.
      if fresh {
        return None
      }
  }
  // A `None` from `cached_header_spelling` proves the header is absent.
  match cached_header_spelling(headers, name) {
    Some(actual) =>
      match headers.get(actual) {
        Some(value) => {
          index.set(lower, actual)
          return Some(value)
        }
        None => ()
      }
    None => return None
  }
  None
}

///|
/// Canonical spellings of recently encountered header names, keyed by their
/// lower-cased form.
let header_spelling_cache : Map[String, String] = Map([])

///|
/// Recency ticks for `header_spelling_cache`.
let header_spelling_cache_ages : Map[String, Int32] = Map([])

///|
/// Find the spelling under which `name` is stored, ignoring case, and
/// re-validate it against the map so in-place replacements are picked up.
fn cached_header_spelling(
  headers : Map[String, String],
  name : String,
) -> String? {
  let lower = header_name_lower(name)
  match header_spelling_cache.get(lower) {
    Some(actual) => {
      cache_touch(header_spelling_cache_ages, lower)
      if headers.contains(actual) &&
        actual.view().equal_ignore_ascii_case(name.view()) {
        return Some(actual)
      }
    }
    None => ()
  }
  let target = name.view()
  let target_length = target.length()
  let mut found : String? = None
  for key in headers.keys() {
    if key.length() == target_length &&
      key.view().equal_ignore_ascii_case(target) {
      found = Some(key)
      break
    }
  }
  match found {
    Some(key) => {
      parse_cache_set(
        header_spelling_cache, header_spelling_cache_ages, lower, key,
      )
      Some(key)
    }
    None => None
  }
}

///|
/// Whether `code` may appear in an HTTP field name (RFC 9110 §5.6.2 `token`).
fn is_http_field_name_character(code : Int32) -> Bool {
  (code >= 48 && code <= 57) ||
  (code >= 65 && code <= 90) ||
  (code >= 97 && code <= 122) ||
  code == 33 ||
  code == 35 ||
  code == 36 ||
  code == 37 ||
  code == 38 ||
  code == 39 ||
  code == 42 ||
  code == 43 ||
  code == 45 ||
  code == 46 ||
  code == 94 ||
  code == 95 ||
  code == 96 ||
  code == 124 ||
  code == 126
}

///|
/// Return `name` when it is a non-empty HTTP field name, or `""` when it could
/// inject separators, whitespace or a whole extra header line.
fn sanitize_response_header_name(name : String) -> String {
  if name.is_empty() {
    return ""
  }
  for i = 0; i < name.length(); i = i + 1 {
    if !is_http_field_name_character(name[i].to_int()) {
      return ""
    }
  }
  name
}

///|
/// Set a header under its canonical spelling, dropping any existing entry whose
/// name differs only by case so the outgoing response has exactly one of it.
///
/// Header names and values are checked here because every response helper
/// funnels through this function. An invalid field name is ignored rather than
/// written, and control characters are removed from the value, so a handler
/// that forwards client-controlled text cannot forge an extra header line.
fn set_header_ignore_case(
  headers : Map[String, String],
  name : String,
  value : String,
) -> Unit {
  let name = sanitize_response_header_name(name)
  if name == "" {
    return
  }
  let value = strip_control_characters(value)
  let stale : Array[String] = []
  for key in headers.keys() {
    if key.view().equal_ignore_ascii_case(name.view()) {
      stale.push(key)
    }
  }
  for key in stale {
    ignore(headers.remove(key))
  }
  headers.set(name, value)
}

///|
/// Remove a header by name regardless of case. Returns whether one was found.
fn remove_header_ignore_case(
  headers : Map[String, String],
  name : String,
) -> Bool {
  let stale : Array[String] = []
  for key in headers.keys() {
    if key.view().equal_ignore_ascii_case(name.view()) {
      stale.push(key)
    }
  }
  if stale.is_empty() {
    return false
  }
  for key in stale {
    ignore(headers.remove(key))
  }
  true
}

///|
fn parse_part_headers(
  header_text : StringView,
) -> (Map[String, String], String?, Int32, String?, Int32) {
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
    headers, disposition, disposition_matches, content_type, content_type_matches,
  )
}

///|
fn skip_line_break(view : StringView, pos : Int32) -> Int32 {
  let length = view.length()
  let mut index = pos
  while index < length &&
        (
          view.unsafe_get(index) == (' ' : UInt16) ||
          view.unsafe_get(index) == ('\t' : UInt16)
        ) {
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
/// One-entry cache of the delimiters and their prefix tables, keyed by the
/// boundary they were built from.
priv struct MultipartDelimiters {
  boundary : String
  delimiter : String
  crlf_delimiter : String
  lf_delimiter : String
  delimiter_table : Array[Int32]
  crlf_delimiter_table : Array[Int32]
  lf_delimiter_table : Array[Int32]
}

///|
let last_multipart_delimiters : Ref[MultipartDelimiters?] = Ref(None)

///|
/// Delimiters and prefix tables for `boundary`.
fn multipart_delimiters(boundary : String) -> MultipartDelimiters {
  match last_multipart_delimiters.val {
    Some(cached) => if cached.boundary == boundary { return cached }
    None => ()
  }
  let delimiter = "--" + boundary
  let crlf_delimiter = "\r\n" + delimiter
  let lf_delimiter = "\n" + delimiter
  let cached : MultipartDelimiters = {
    boundary,
    delimiter,
    crlf_delimiter,
    lf_delimiter,
    delimiter_table: delimiter_match_table(delimiter.view()),
    crlf_delimiter_table: delimiter_match_table(crlf_delimiter.view()),
    lf_delimiter_table: delimiter_match_table(lf_delimiter.view()),
  }
  last_multipart_delimiters.val = Some(cached)
  cached
}

///|
/// Most recent body and content type passed to `parse_multipart`, with the
/// owned parse they produced. Callers receive a copy of the parts, including
/// their header maps, so they can mutate the result freely.
let last_parsed_multipart_body : Ref[String?] = Ref(None)

///|
let last_parsed_multipart_content_type : Ref[String?] = Ref(None)

///|
let last_parsed_multipart_result : Ref[Array[MultipartPart]?] = Ref(None)

///|
let last_parsed_multipart_valid : Ref[Bool] = Ref(false)

///|
pub fn parse_multipart(
  body : String,
  content_type : String,
) -> Array[MultipartPart]? {
  match last_parsed_multipart_body.val {
    Some(cached_body) =>
      if last_parsed_multipart_valid.val &&
        (physical_equal(cached_body, body) || cached_body == body) &&
        last_parsed_multipart_content_type.val is Some(cached_type) &&
        (
          physical_equal(cached_type, content_type) ||
          cached_type == content_type
        ) {
        return match last_parsed_multipart_result.val {
          Some(parts) => Some(clone_multipart_parts(parts))
          None => None
        }
      }
    None => ()
  }
  let parsed = parse_multipart_uncached(body, content_type)
  if body.length() <= PARSE_CACHE_MAX_KEY {
    last_parsed_multipart_body.val = Some(body)
    last_parsed_multipart_content_type.val = Some(content_type)
    last_parsed_multipart_result.val = parsed
    last_parsed_multipart_valid.val = true
  }
  match parsed {
    Some(parts) => Some(clone_multipart_parts(parts))
    None => None
  }
}

///|
fn parse_multipart_uncached(
  body : String,
  content_type : String,
  raw_body~ : String? = None,
) -> Array[MultipartPart]? {
  let boundary = match multipart_boundary(content_type) {
    Some(boundary) if boundary != "" => boundary
    _ => return None
  }
  let delimiters = multipart_delimiters(boundary)
  let delimiter = delimiters.delimiter
  let delimiter_view = delimiter.view()
  let delimiter_length = delimiter.length()
  let crlf_delimiter = delimiters.crlf_delimiter
  let crlf_delimiter_view = crlf_delimiter.view()
  let lf_delimiter = delimiters.lf_delimiter
  let lf_delimiter_view = lf_delimiter.view()
  let delimiter_table = delimiters.delimiter_table
  let crlf_delimiter_table = delimiters.crlf_delimiter_table
  let lf_delimiter_table = delimiters.lf_delimiter_table
  // With a raw body available the parse runs over its lossless text, where
  // every received byte is still represented (supplementary characters intact,
  // invalid bytes escaped); the resulting slices can then be encoded back to
  // the exact payload. Without one the parse only sees well-formed text.
  let lossless = raw_body is Some(_)
  let source = match raw_body {
    Some(raw) => raw
    None => body
  }
  let view = source.view()
  let mut pos = match
    find_terminated_delimiter(view, delimiter_view, delimiter_table, 0) {
    Some(index) => index + delimiter_length
    // A multipart body always contains at least one dash-boundary (a valid
    // empty body is `--boundary--`). Without one the body is malformed, not
    // an empty list of parts.
    None => return None
  }
  let estimate = source.length() / (crlf_delimiter.length() + 8)
  let parts : Array[MultipartPart] = Array(
    capacity=if estimate > 64 { 64 } else { estimate + 1 },
  )
  let mut closed = false
  while pos <= view.length() {
    if pos + 1 < view.length() &&
      view.unsafe_get(pos) == ('-' : UInt16) &&
      view.unsafe_get(pos + 1) == ('-' : UInt16) {
      closed = true
      break
    }
    pos = skip_line_break(view, pos)
    let data_end = match
      find_part_delimiter(
        view, crlf_delimiter_view, lf_delimiter_view, crlf_delimiter_table, lf_delimiter_table,
        pos,
      ) {
      Some(index) => index
      None => break
    }
    // A part may carry no headers at all, in which case its blank line comes
    // immediately after the delimiter line.
    let (header_end, separator_length) = if pos + 1 < view.length() &&
      view.unsafe_get(pos) == ('\r' : UInt16) &&
      view.unsafe_get(pos + 1) == ('\n' : UInt16) {
      (pos, 2)
    } else if pos < view.length() && view.unsafe_get(pos) == ('\n' : UInt16) {
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
    let (name, filename) = match disposition {
      Some(disposition) => {
        let names = disposition_names(disposition.view())
        (names.name, names.filename)
      }
      None => ("", "")
    }
    let part_content_type = if content_type_matches == 1 {
      tracked_content_type.unwrap_or("")
    } else if content_type_matches == 0 {
      ""
    } else {
      get_header_ignore_case(headers, "Content-Type").unwrap_or("")
    }
    let part_data = data.to_owned()
    let (data_bytes, data_text) = resolve_part_bytes(
      part_data,
      if lossless {
        Some(part_data)
      } else {
        None
      },
    )
    parts.push({
      name,
      filename,
      content_type: part_content_type,
      headers,
      data: data_text,
      data_bytes,
    })
    pos = skip_line_break(view, data_end) + delimiter_length
  }
  // A truncated body that stops after part data (or after a bare delimiter)
  // must not be reported as a successful, complete multipart payload. Every
  // valid multipart/form-data body ends with `--boundary--`.
  if !closed {
    return None
  }
  Some(parts)
}

///|
/// Cached parts of a multipart request, or `None` when the body is not
/// multipart. Reads and normalizes the `Content-Type` header.
fn Context::multipart_entries(self : Context) -> Array[MultipartPart]? {
  let header = self.header("Content-Type")
  if parsed_content_type(header) != "multipart/form-data" {
    return None
  }
  // A binary body was preserved verbatim, so parse its lossless text and let
  // each part recover its exact bytes; otherwise the well-formed body is used
  // directly.
  let raw_body = match self.state.get(RAW_BODY_STATE_KEY) {
    Some(encoded) =>
      match base64_decode(encoded) {
        Some(bytes) => Some(decode_utf8_lossless(bytes))
        None => None
      }
    None => None
  }
  multipart_parts_lookup(self.request.body, header, raw_body~)
}

///|
/// The parsed multipart body. The result array is a copy, but its parts and
/// their header maps are shared with the parse cache and must be treated as
/// read-only.
pub fn Context::multipart(self : Context) -> Array[MultipartPart] {
  match self.multipart_entries() {
    Some(parts) => copy_multipart_parts(parts)
    None => []
  }
}

///|
/// Whether a part carries a `filename` (or RFC 8187 `filename*`) parameter.
/// The parameter's presence marks a file part even when its value is empty,
/// which is what browsers submit for an empty file input.
fn multipart_part_is_file(part : MultipartPart) -> Bool {
  match get_header_ignore_case(part.headers, "Content-Disposition") {
    Some(value) =>
      header_parameter(value.view(), "filename") is Some(_) ||
      header_parameter(value.view(), "filename*") is Some(_)
    None => false
  }
}

///|
pub fn Context::multipart_value(self : Context, name : String) -> String {
  match self.multipart_entries() {
    Some(parts) => {
      for part in parts {
        if !multipart_part_is_file(part) && part.name == name {
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
  match self.multipart_entries() {
    Some(parts) => {
      for part in parts {
        if part.name == name && multipart_part_is_file(part) {
          return Some(copy_multipart_part(part))
        }
      }
      None
    }
    None => None
  }
}

///|
/// Every text field named `name`, in the order the parts appear in the body.
/// File parts with the same name are skipped; use `multipart_files` for those.
/// Returns an empty array when the request is not multipart or carries no such
/// field.
pub fn Context::multipart_values(
  self : Context,
  name : String,
) -> Array[String] {
  let values : Array[String] = []
  match self.multipart_entries() {
    Some(parts) =>
      for part in parts {
        if !multipart_part_is_file(part) && part.name == name {
          values.push(part.data)
        }
      }
    None => ()
  }
  values
}

///|
/// Every uploaded file named `name`, in the order the parts appear in the body.
/// Each returned part owns a copy of its header map, so callers may mutate the
/// result without disturbing the parse cache. A part with an empty `filename`
/// parameter is still a file part. Returns an empty array when the request is
/// not multipart or carries no such file.
pub fn Context::multipart_files(
  self : Context,
  name : String,
) -> Array[MultipartPart] {
  let files : Array[MultipartPart] = []
  match self.multipart_entries() {
    Some(parts) =>
      for part in parts {
        if part.name == name && multipart_part_is_file(part) {
          files.push(copy_multipart_part(part))
        }
      }
    None => ()
  }
  files
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
fn days_in_month(year : Int64, month : Int32) -> Int32 {
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
fn days_from_civil(year : Int64, month : Int32, day : Int32) -> Int64 {
  let y = if month <= 2 { year - 1 } else { year }
  let era = (if y >= 0 { y } else { y - 399 }) / 400
  let yoe = y - era * 400
  let mp = if month > 2 { month - 3 } else { month + 9 }
  let doy = (153L * mp.to_int64() + 2L) / 5L + day.to_int64() - 1L
  let doe = yoe * 365L + yoe / 4L - yoe / 100L + doy
  era * 146097L + doe - 719468L
}

///|
fn civil_from_days(days : Int64) -> (Int64, Int32, Int32) {
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
fn civil_from_days_wide(days : Int64) -> (Int64, Int32, Int32) {
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
  "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec",
]

///|
/// Full weekday names accepted by the obsolete `rfc850-date` grammar.
let http_weekdays_full : Array[String] = [
  "Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday",
]

///|
/// Whether `name` is one of the three-letter weekday abbreviations or one of
/// the full names used by `rfc850-date`, matched case-insensitively.
fn is_http_weekday(name : StringView) -> Bool {
  let length = name.length()
  if length == 3 {
    for weekday in http_weekdays {
      if name.equal_ignore_ascii_case(weekday.view()) {
        return true
      }
    }
  } else {
    for weekday in http_weekdays_full {
      if name.equal_ignore_ascii_case(weekday.view()) {
        return true
      }
    }
  }
  false
}

///|
fn write_two_digits(builder : StringBuilder, value : Int32) -> Unit {
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
  // HTTP-date spells the year with exactly four digits. Clamp values outside
  // the proleptic Gregorian years 0000..9999 so this infallible formatter never
  // emits a date that `parse_http_date` (or an HTTP recipient) must reject.
  let min_seconds = days_from_civil(0L, 1, 1) * 86400L
  let max_seconds = days_from_civil(9999L, 12, 31) * 86400L + 86399L
  let unix_seconds = if unix_seconds < min_seconds {
    min_seconds
  } else if unix_seconds > max_seconds {
    max_seconds
  } else {
    unix_seconds
  }
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
    minute = (time_of_day % 3600L / 60L).to_int()
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
fn parse_decimal(view : StringView) -> Int32? {
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
fn month_from_name(name : StringView) -> Int32? {
  let length = name.length()
  if length != 3 {
    return None
  }
  for i, month in http_months {
    // RFC 9110's HTTP-date grammar uses case-insensitive ABNF literals, so a
    // recipient must accept `nov` as well as `Nov` (and any other casing).
    if name.equal_ignore_ascii_case(month.view()) {
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
  let hour_text = time[:first_colon]
  let minute_text = time[first_colon + 1:second_colon]
  let second_text = time[second_colon + 1:]
  // HTTP-date's time-of-day grammar is fixed-width: `HH:MM:SS`. A one- or
  // three-digit field is malformed and must be ignored rather than treated as
  // a validator.
  if hour_text.length() != 2 ||
    minute_text.length() != 2 ||
    second_text.length() != 2 {
    return None
  }
  let hour = match parse_decimal(hour_text) {
    Some(hour) => hour
    None => return None
  }
  let minute = match parse_decimal(minute_text) {
    Some(minute) => minute
    None => return None
  }
  let second = match parse_decimal(second_text) {
    Some(second) => second
    None => return None
  }
  if hour > 23 || minute > 59 || second > 60 {
    return None
  }
  Some((hour * 3600 + minute * 60 + second).to_int64())
}

///|
fn imf_fixdate_two_digits(view : StringView, at : Int32) -> Int32 {
  let a = view.unsafe_get(at).to_int() - 48
  let b = view.unsafe_get(at + 1).to_int() - 48
  if a < 0 || a > 9 || b < 0 || b > 9 {
    return -1
  }
  a * 10 + b
}

///|
fn imf_fixdate_four_digits(view : StringView, at : Int32) -> Int32 {
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
  while weekday_start < 4 && view.unsafe_get(weekday_start) == (' ' : UInt16) {
    weekday_start = weekday_start + 1
  }
  let mut weekday_end = weekday_start
  while weekday_end < 4 && view.unsafe_get(weekday_end) != (' ' : UInt16) {
    weekday_end = weekday_end + 1
  }
  if weekday_end != 4 || !is_http_weekday(view[:3]) {
    return None
  }
  // HTTP-date carries the GMT zone; anything else is not a valid date.
  if !view[26:29].equal_ignore_ascii_case("GMT".view()) {
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
    hour > 23 ||
    minute > 59 ||
    second > 60 {
    return None
  }
  Some(
    days_from_civil(year.to_int64(), month, day) * 86400L +
    (hour * 3600 + minute * 60 + second).to_int64(),
  )
}

///|
/// The current Gregorian year, used to expand the obsolete two-digit years of
/// `rfc850-date` values.
fn http_current_year() -> Int64 {
  let (year, _, _) = civil_from_days(@async.now() / 86_400_000L)
  year
}

///|
/// Expand an `rfc850-date` two-digit year as RFC 9110 §5.6.7 requires: a
/// timestamp that would appear more than 50 years in the future is read as the
/// most recent year in the past with the same last two digits.
fn expand_two_digit_year(two_digit : Int32) -> Int64 {
  let current = http_current_year()
  let candidate = current / 100L * 100L + two_digit.to_int64()
  if candidate > current + 50L {
    candidate - 100L
  } else {
    candidate
  }
}

///|
/// Expand an `rfc850-date` two-digit year using the full timestamp.
///
/// RFC 9110 §5.6.7 applies the 50-year rule to the timestamp, not merely to
/// the year: `31-Dec-76` is already more than 50 years in the future when
/// today is in October 2026, even though 2076 is only exactly 50 years ahead.
fn expand_two_digit_year_for_date(
  two_digit : Int32,
  month : Int32,
  day : Int32,
  seconds_of_day : Int64,
) -> Int64 {
  let now = @async.now() / 1000L
  let now_days = now / 86400L
  let now_time_of_day = now - now_days * 86400L
  let (current_year, current_month, current_day) = civil_from_days(now_days)
  let candidate = current_year / 100L * 100L + two_digit.to_int64()
  let threshold = days_from_civil(
    current_year + 50L,
    current_month,
    current_day,
  ) *
  86400L +
  now_time_of_day
  let candidate_seconds = days_from_civil(candidate, month, day) * 86400L +
    seconds_of_day
  if candidate_seconds > threshold {
    candidate - 100L
  } else {
    candidate
  }
}

///|
pub fn parse_http_date(value : String) -> Int64? {
  parse_http_date_view(value.view())
}

///|
/// `parse_http_date` for a view.
fn parse_http_date_view(view : StringView) -> Int64? {
  match parse_imf_fixdate(view) {
    Some(seconds) => return Some(seconds)
    None => ()
  }
  let length = view.length()
  // Count tokens to reject RFC-850 / asctime dates with unusual whitespace.
  let mut token_count = 0
  let mut probe = 0
  while probe < length {
    while probe < length && view.unsafe_get(probe) == (' ' : UInt16) {
      probe = probe + 1
    }
    if probe >= length {
      break
    }
    token_count = token_count + 1
    while probe < length && view.unsafe_get(probe) != (' ' : UInt16) {
      probe = probe + 1
    }
  }
  if token_count < 4 {
    return None
  }
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
  let mut two_digit_year : Int32? = None
  let mut time = parts[0]
  if parts[1].contains("-") {
    let weekday = parts[0]
    if !weekday.has_suffix(",") ||
      !is_http_weekday(weekday[:weekday.length() - 1]) {
      return None
    }
    let date = parts[1]
    let first_dash = match date.find("-") {
      Some(index) => index
      None => return None
    }
    let second_dash = match date[first_dash + 1:].find("-") {
      Some(index) => first_dash + 1 + index
      None => return None
    }
    // HTTP-date spells the day with exactly two digits in both IMF-fixdate
    // and rfc850-date; a short token is a malformed date, not a validator.
    if first_dash != 2 {
      return None
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
      // The final expansion depends on the full date and time, which is parsed
      // below; start from the current-century candidate here.
      let current = http_current_year()
      year = current / 100L * 100L + parsed_year.to_int64()
      two_digit_year = Some(parsed_year)
    } else if year_text.length() == 4 {
      year = parsed_year.to_int64()
    } else {
      return None
    }
    if token_count != 4 || !parts[3].equal_ignore_ascii_case("GMT".view()) {
      return None
    }
    time = parts[2]
  } else if parts[0].contains(",") {
    if count < 6 || token_count != 6 {
      return None
    }
    let weekday = parts[0]
    // The IMF-fixdate and RFC 1123 grammars spell the day-name with exactly
    // three letters; the full weekday names belong only to rfc850-date.
    if !weekday.has_suffix(",") ||
      weekday.length() != 4 ||
      !is_http_weekday(weekday[:3]) {
      return None
    }
    // IMF-fixdate uses a fixed two-digit day. The tokenizing fallback is only
    // for tolerated whitespace variations, not for malformed field widths.
    if parts[1].length() != 2 {
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
    // Both the IMF-fixdate and the legacy RFC 1123 form spell the year with
    // exactly four digits; a longer or zero-padded token is not an HTTP-date
    // and must not be mistaken for a far-future validator.
    if parts[3].length() != 4 {
      return None
    }
    year = match parse_decimal(parts[3]) {
      Some(year) => year.to_int64()
      None => return None
    }
    if !parts[5].equal_ignore_ascii_case("GMT".view()) {
      return None
    }
    time = parts[4]
  } else {
    if count < 5 || token_count != 5 {
      return None
    }
    // asctime-date also uses the three-letter day-name, not the full name
    // accepted by the obsolete rfc850-date form.
    if parts[0].length() != 3 || !is_http_weekday(parts[0]) {
      return None
    }
    month = match month_from_name(parts[1]) {
      Some(month) => month
      None => return None
    }
    // asctime pads a one-digit day with an extra space, so its token has one
    // or two digits; longer tokens are not part of the grammar.
    if parts[2].length() < 1 || parts[2].length() > 2 {
      return None
    }
    day = match parse_decimal(parts[2]) {
      Some(day) => day
      None => return None
    }
    time = parts[3]
    if parts[4].length() != 4 {
      return None
    }
    year = match parse_decimal(parts[4]) {
      Some(year) => year.to_int64()
      None => return None
    }
  }
  let seconds_of_day = match parse_time_of_day(time) {
    Some(seconds) => seconds
    None => return None
  }
  match two_digit_year {
    Some(two_digit) =>
      year = expand_two_digit_year_for_date(
        two_digit, month, day, seconds_of_day,
      )
    None => ()
  }
  if day < 1 || day > days_in_month(year, month) {
    return None
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
    if i == length || (value.unsafe_get(i) == (',' : UInt16) && !in_quotes) {
      let token = trim_ascii_space(value[start:i])
      if token == "*" {
        return true
      }
      let token_opaque = if token.has_prefix("W/") { token[2:] } else { token }
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
/// second, matching the one-second granularity of HTTP dates. The epoch is a
/// real validator, so `None` (not `0`) marks an unknown modification date.
fn if_unmodified_since_ok(value : StringView, mtime_secs : Int64?) -> Bool {
  match mtime_secs {
    None => true
    Some(mtime_secs) =>
      match parse_http_date_view(trim_ascii_space(value)) {
        Some(since) => mtime_secs <= since
        None => true
      }
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
/// The four precondition request headers `evaluate_preconditions` consults,
/// shared by the server and the offline `App::respond` path.
priv struct PreconditionInput {
  if_match : String?
  if_none_match : String?
  if_modified_since : String?
  if_unmodified_since : String?
}

///|
fn precondition_input_from_http(request : @http.Request) -> PreconditionInput {
  {
    if_match: request.headers.get(header_if_match),
    if_none_match: request.headers.get(header_if_none_match),
    if_modified_since: request.headers.get(header_if_modified_since),
    if_unmodified_since: request.headers.get(header_if_unmodified_since),
  }
}

///|
/// The four precondition header names, resolved once.
let precondition_if_match_name : StringView = "If-Match".view()

///|
let precondition_if_none_match_name : StringView = "If-None-Match".view()

///|
let precondition_if_modified_since_name : StringView = "If-Modified-Since".view()

///|
let precondition_if_unmodified_since_name : StringView = "If-Unmodified-Since".view()

///|
/// Collect the precondition request headers from the map.
///
/// The map is mutable and can be changed in place without its length changing,
/// so the result is not cached.
fn precondition_input_from_map(
  headers : Map[String, String],
) -> PreconditionInput {
  if headers.is_empty() {
    return {
      if_match: None,
      if_none_match: None,
      if_modified_since: None,
      if_unmodified_since: None,
    }
  }
  let mut if_match : String? = None
  let mut if_none_match : String? = None
  let mut if_modified_since : String? = None
  let mut if_unmodified_since : String? = None
  headers.each(fn(key, value) {
    let key_view = key.view()
    let length = key_view.length()
    if length == 8 || length == 13 || length == 17 || length == 19 {
      let first = key_view.unsafe_get(0)
      if first == ('I' : UInt16) || first == ('i' : UInt16) {
        if length == 8 {
          if if_match is None &&
            key_view.equal_ignore_ascii_case(precondition_if_match_name) {
            if_match = Some(value)
          }
        } else if length == 13 {
          if if_none_match is None &&
            key_view.equal_ignore_ascii_case(precondition_if_none_match_name) {
            if_none_match = Some(value)
          }
        } else if length == 17 {
          if if_modified_since is None &&
            key_view.equal_ignore_ascii_case(
              precondition_if_modified_since_name,
            ) {
            if_modified_since = Some(value)
          }
        } else if if_unmodified_since is None &&
          key_view.equal_ignore_ascii_case(
            precondition_if_unmodified_since_name,
          ) {
          if_unmodified_since = Some(value)
        }
      }
    }
  })
  { if_match, if_none_match, if_modified_since, if_unmodified_since, }
}

///|
/// Evaluate `If-Match`, `If-Unmodified-Since`, `If-None-Match` and
/// `If-Modified-Since` in the order required by RFC 9110 §13.2.2.
///
/// `etag` and `mtime_secs` describe the selected representation; either may be
/// absent (empty tag / `0`). `allows_not_modified` is true for `GET`/`HEAD`,
/// the only methods that `304 Not Modified` may be sent for.
fn evaluate_preconditions_input(
  input : PreconditionInput,
  etag : String,
  mtime_secs : Int64?,
  allows_not_modified : Bool,
) -> PreconditionOutcome {
  match input.if_match {
    Some(value) =>
      if !if_match_header_matches(value.view(), etag) {
        return PreconditionFailed
      }
    None =>
      match input.if_unmodified_since {
        Some(value) =>
          if !if_unmodified_since_ok(value.view(), mtime_secs) {
            return PreconditionFailed
          }
        None => ()
      }
  }
  match input.if_none_match {
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
        match input.if_modified_since {
          Some(value) =>
            match mtime_secs {
              Some(mtime_secs) =>
                match parse_http_date_view(trim_ascii_space(value.view())) {
                  Some(since) =>
                    if mtime_secs <= since {
                      return PreconditionNotModified
                    }
                  None => ()
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
fn evaluate_preconditions(
  request : @http.Request,
  etag : String,
  mtime_secs : Int64,
  allows_not_modified : Bool,
) -> PreconditionOutcome {
  evaluate_preconditions_input(
    precondition_input_from_http(request),
    etag,
    Some(mtime_secs),
    allows_not_modified,
  )
}

///|
/// Drop a satisfied `If-Match` (and the `If-Unmodified-Since` it suppresses)
/// before a transformation weakens the response validator.
///
/// Compression turns a strong handler ETag into a weak one. Re-evaluating the
/// original strong comparison after that would fail a request whose `If-Match`
/// matched the representation when it was selected. File responses run after
/// the dynamic pipeline's pre-compression check, so they apply this directly.
fn drop_satisfied_if_match(
  input : PreconditionInput,
  etag : String,
) -> PreconditionInput {
  match input.if_match {
    Some(value) =>
      if if_match_header_matches(value.view(), etag) {
        {
          if_match: None,
          if_none_match: input.if_none_match,
          if_modified_since: input.if_modified_since,
          if_unmodified_since: None,
        }
      } else {
        input
      }
    None => input
  }
}

///|
/// Request-state keys remembering the validators that made the last
/// `Context::fresh` call report the representation as fresh.
const FRESH_ETAG_STATE_KEY : String = "__feather_fresh_etag"
const FRESH_LAST_MODIFIED_STATE_KEY : String = "__feather_fresh_last_modified"

///|
fn Context::remember_fresh_validators(
  self : Context,
  etag : String,
  last_modified : String?,
) -> Unit {
  if etag != "" {
    self.state.set(FRESH_ETAG_STATE_KEY, etag)
  }
  match last_modified {
    Some(value) => if value != "" {
      self.state.set(FRESH_LAST_MODIFIED_STATE_KEY, value)
    }
    None => ()
  }
}

///|
/// Whether the request's conditional headers report that the representation
/// described by `etag` and/or `last_modified` is still fresh.
///
/// A present `If-None-Match` is evaluated first and takes precedence over
/// `If-Modified-Since`, as RFC 9110 requires. Both conditions only apply to
/// `GET` and `HEAD`, the methods for which a `304` is defined; on any other
/// method this returns `false` so a handler cannot accidentally answer a
/// conditional `POST`/`PUT` with `304`. Pass `last_modified` (an HTTP-date such
/// as the value returned by `format_http_date`) to also answer date-only
/// `If-Modified-Since` requests. Returns `false` when neither validator matches
/// or both are absent/invalid.
///
/// When the answer is `true`, the validators are remembered so a following
/// `Context::not_modified()` without arguments can repeat the same `ETag` and
/// `Last-Modified` that the matching `200` response would carry.
pub fn Context::fresh(
  self : Context,
  etag : String,
  last_modified? : String,
) -> Bool {
  ignore(self.state.remove(FRESH_ETAG_STATE_KEY))
  ignore(self.state.remove(FRESH_LAST_MODIFIED_STATE_KEY))
  let http_method = normalize_method(self.request.method)
  let allows_not_modified = http_method == "GET" || http_method == "HEAD"
  let none_match = self.header("If-None-Match")
  // Presence matters, not just a non-empty value: an empty or malformed
  // `If-None-Match` field still takes precedence over `If-Modified-Since`
  // (RFC 9110 §13.1.3), so it must not fall through to the date condition.
  // A `304` is only valid for a retrieval, so an unsafe method never reports
  // the representation as fresh even when the tag matches.
  if self.has_header("If-None-Match") {
    if !allows_not_modified {
      return false
    }
    // A present but non-matching tag must not fall back to the date
    // condition. Without a representation ETag only the wildcard can match:
    // `*` names any existing representation, so it stays true even when the
    // caller does not have a validator to pass.
    let matched = if etag == "" {
      etag_header_matches(none_match.view(), "")
    } else {
      etag_header_matches(none_match.view(), etag)
    }
    if matched {
      self.remember_fresh_validators(etag, last_modified)
    }
    return matched
  }
  // A date validator only makes sense for the safe retrieval methods.
  if !allows_not_modified {
    return false
  }
  let modified = match last_modified {
    Some(value) =>
      match parse_http_date_view(trim_ascii_space(value.view())) {
        Some(seconds) => Some(seconds)
        None => None
      }
    None => None
  }
  let since = match modified {
    Some(_) =>
      match parse_http_date_view(
        trim_ascii_space(self.header("If-Modified-Since").view()),
      ) {
        Some(seconds) => Some(seconds)
        None => None
      }
    None => None
  }
  let matched = match (modified, since) {
    (Some(modified), Some(since)) => modified <= since
    _ => false
  }
  if matched {
    self.remember_fresh_validators(etag, last_modified)
  }
  matched
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
  ignore(remove_header_ignore_case(self.response.headers, "Content-Type"))
  ignore(remove_header_ignore_case(self.response.headers, "Content-Length"))
  ignore(remove_header_ignore_case(self.response.headers, "Content-Range"))
  ignore(remove_header_ignore_case(self.response.headers, "Content-Disposition"))
  let resolved_etag = match etag {
    Some(value) => Some(value)
    None => self.state.get(FRESH_ETAG_STATE_KEY)
  }
  let resolved_last_modified = match last_modified {
    Some(value) => Some(value)
    None => self.state.get(FRESH_LAST_MODIFIED_STATE_KEY)
  }
  match resolved_etag {
    Some(etag) => set_header_ignore_case(self.response.headers, "ETag", etag)
    None => ()
  }
  match resolved_last_modified {
    Some(last_modified) =>
      set_header_ignore_case(
        self.response.headers,
        "Last-Modified",
        last_modified,
      )
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
/// Whether `view` is a non-empty run of decimal digits. Used to distinguish a
/// syntactically valid but out-of-range byte offset from a malformed one.
fn is_decimal_offset(view : StringView) -> Bool {
  let length = view.length()
  if length == 0 {
    return false
  }
  let mut i = 0
  while i < length {
    let digit = view.unsafe_get(i).to_int() - 48
    if digit < 0 || digit > 9 {
      return false
    }
    i = i + 1
  }
  true
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
      // A numeric suffix larger than Int64 is still a valid suffix that
      // selects the whole representation, not malformed syntax to ignore.
      None =>
        if is_decimal_offset(end_text) {
          if total <= 0L {
            return ByteRangeInvalid
          }
          return ByteRangeSpec(0L, total - 1L)
        } else {
          return ByteRangeFull
        }
    }
    if suffix <= 0L || total <= 0L {
      return ByteRangeInvalid
    }
    let start = if suffix >= total { 0L } else { total - suffix }
    return ByteRangeSpec(start, total - 1L)
  }
  let start = match parse_byte_offset(start_text) {
    Some(start) => start
    // Any numeric start that does not fit in Int64 is beyond every possible
    // representation size, so the range is unsatisfiable rather than invalid
    // syntax.
    None =>
      if is_decimal_offset(start_text) {
        return ByteRangeInvalid
      } else {
        return ByteRangeFull
      }
  }
  if end_text.is_empty() {
    if start >= total {
      return ByteRangeInvalid
    }
    return ByteRangeSpec(start, total - 1L)
  }
  let end = match parse_byte_offset(end_text) {
    Some(end) => end
    // An overflowing last-byte position is clamped to the end below.
    None => if is_decimal_offset(end_text) { 9223372036854775807L } else {
      return ByteRangeFull
    }
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
/// Whether an `If-Range` condition still describes the buffered response, so a
/// `Range` request may be served partially. Entity tags use the strong
/// comparison function, so a weak tag never matches; an HTTP-date must match
/// `Last-Modified` exactly. With neither validator present the range cannot be
/// proven to apply to the current representation, so the full response is sent.
fn buffered_if_range_allows(
  if_range : String?,
  response : Response,
) -> Bool {
  let raw = match if_range {
    Some(value) => value
    None => return true
  }
  let token = trim_ascii_space(raw.view())
  let etag = match get_header_ignore_case(response.headers, "ETag") {
    Some(value) => value
    None => ""
  }
  if etag != "" &&
    !etag.view().has_prefix("W/") &&
    !token.has_prefix("W/") &&
    token == etag.view() {
    return true
  }
  match get_header_ignore_case(response.headers, "Last-Modified") {
    Some(value) =>
      match (parse_http_date_view(value.view()), parse_http_date_view(token)) {
        (Some(modified), Some(since)) => modified == since
        _ => false
      }
    None => false
  }
}

///|
/// Apply a `Range` request to a fully buffered dynamic response.
///
/// Static files have always supported byte ranges; this gives ordinary
/// handlers, middleware short-circuits and streaming/SSE/WebSocket middleware
/// responses the same treatment when the body is already in memory. Only a
/// successful `GET` is eligible, so a `HEAD` keeps advertising the full
/// representation and other methods are untouched. `If-Range` is evaluated
/// against the response's own validators before the range is used.
///
/// A satisfiable range becomes `206 Partial Content` with the sliced bytes and
/// a `Content-Range`; an unsatisfiable one becomes `416 Range Not Satisfiable`
/// describing the full length. A malformed or multi-range request is ignored
/// (the full representation is sent), which RFC 9110 permits.
fn apply_buffered_range_core(
  method : StringView,
  range : String?,
  if_range : String?,
  response : Response,
  head : Bool,
) -> Unit {
  if head || !method.equal_ignore_ascii_case("GET".view()) {
    return
  }
  if response.status != 200 {
    return
  }
  let range_value = match range {
    Some(value) => value
    None => return
  }
  if get_header_ignore_case(response.headers, "Content-Range") is Some(_) {
    return
  }
  if !buffered_if_range_allows(if_range, response) {
    return
  }
  let original_is_bytes = response.data is Some(_)
  let data = match response.data {
    Some(data) => data
    None => encode_utf8_lossy(response.body.view())
  }
  let total = data.length().to_int64()
  match parse_byte_range(range_value, total) {
    ByteRangeFull =>
      set_header_ignore_case(response.headers, "Accept-Ranges", "bytes")
    ByteRangeInvalid => {
      response.status = 416
      clear_replaced_body_headers(response.headers)
      clear_replaced_representation_headers(response.headers)
      set_header_ignore_case(
        response.headers,
        "Content-Type",
        "text/plain; charset=utf-8",
      )
      set_header_ignore_case(
        response.headers,
        "Content-Range",
        "bytes */" + total.to_string(),
      )
      set_header_ignore_case(response.headers, "Accept-Ranges", "bytes")
      response.body = "416 Range Not Satisfiable"
      response.data = None
    }
    ByteRangeSpec(start, end) => {
      let first = start.to_int()
      let sliced = data[first:end.to_int() + 1].to_bytes()
      response.status = 206
      if original_is_bytes {
        response.data = Some(sliced)
        response.body = ""
      } else {
        // A range can split a multi-byte UTF-8 sequence. Keep the exact bytes
        // in that case; only a slice that is still valid text can travel in
        // `Response.body`, whose server encoding must reproduce the same bytes.
        let text : String? = Some(@utf8.decode(sliced)) catch {
          @utf8.Malformed(_) => None
        }
        match text {
          Some(text) => {
            response.body = text
            response.data = None
          }
          None => {
            response.body = ""
            response.data = Some(sliced)
          }
        }
      }
      set_header_ignore_case(
        response.headers,
        "Content-Range",
        "bytes " +
        start.to_string() +
        "-" +
        end.to_string() +
        "/" +
        total.to_string(),
      )
      set_header_ignore_case(response.headers, "Accept-Ranges", "bytes")
    }
  }
}

///|
/// Apply a byte range from a framework `Request` to a buffered response.
fn apply_buffered_range(
  request : Request,
  response : Response,
  head : Bool,
) -> Unit {
  apply_buffered_range_core(
    request.method.view(),
    get_header_ignore_case(request.headers, "Range"),
    get_header_ignore_case(request.headers, "If-Range"),
    response,
    head,
  )
}

///|
fn normalize_prefix(prefix : String) -> String {
  let view = clean_path_view(prefix)
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
/// Whether `path` is `prefix` itself or lies below it as a whole path segment.
///
/// Both sides are compared using the router's segment model: empty segments
/// from repeated or leading slashes are ignored and each segment is decoded the
/// same way a static route segment is. That keeps a scoped middleware attached
/// to `/admin` from being skipped by a request for `/ad%6Din/panel` or
/// `//admin/panel`, which the router still resolves to the same route. Only
/// whole segments are decoded, so an encoded slash stays inside its segment
/// instead of creating a new one.
fn path_is_within_prefix(path : StringView, prefix : StringView) -> Bool {
  let prefix_segments = split_segments(prefix)
  if prefix_segments.length() == 0 {
    return true
  }
  let path_segments = split_segments(path)
  if path_segments.length() < prefix_segments.length() {
    return false
  }
  for i = 0; i < prefix_segments.length(); i = i + 1 {
    if normalize_static_route_segment(path_segments[i]) !=
      normalize_static_route_segment(prefix_segments[i]) {
      return false
    }
  }
  true
}

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
        let base_segments = split_segments(base.view())
        if base_segments.length() == 0 {
          path
        } else {
          let length = path.length()
          let mut pos = 0
          let mut matched = 0
          while matched < base_segments.length() {
            let base_segment = base_segments[matched]
            // Mount prefixes are route patterns, so `:param` captures any one
            // segment and `*wildcard` consumes the rest of the path. Comparing
            // the literal `:id` spelling would make a child's scoped
            // middleware miss every dynamically mounted request.
            if base_segment.has_prefix("*") {
              return ""
            }
            pos = skip_slashes(path, pos)
            if pos >= length {
              return path
            }
            let end = segment_end(path, pos)
            let segment = path[pos:end]
            let segment_matches = if base_segment.has_prefix(":") {
              !segment.is_empty()
            } else {
              normalize_static_route_segment(segment) ==
              normalize_static_route_segment(base_segment)
            }
            if !segment_matches {
              return path
            }
            matched = matched + 1
            pos = end
          }
          path[pos:]
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
}

///|
pub fn Router::group(self : Router, prefix : String) -> RouteGroup {
  {
    router: self,
    prefix: normalize_prefix(prefix),
    middlewares: [],
    app: None,
  }
}

///|
pub fn RouteGroup::group(self : RouteGroup, prefix : String) -> RouteGroup {
  {
    router: self.router,
    prefix: normalize_prefix(join_paths(self.prefix, prefix)),
    middlewares: self.middlewares.copy(),
    app: self.app,
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
  self.router.add_route(
    meth,
    join_paths(self.prefix, path),
    self.wrap(apply_middleware(middlewares, handler)),
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
  self.router.add_named_route(
    name,
    meth,
    join_paths(self.prefix, path),
    self.wrap(handler),
  )
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
  self.router.add_named_route(
    name,
    meth,
    join_paths(self.prefix, path),
    self.wrap(apply_middleware(middlewares, handler)),
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
/// `consumed` is the path position just after the matched prefix and
/// `relative_start` is where the path relative to the mount root begins. They
/// differ for a mount whose prefix ends in a wildcard, where the captured
/// remainder is itself part of the child-relative path.
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
        consumed: length,
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

///|
/// Middleware that rejects request bodies larger than `max_bytes` with
/// `413 Payload Too Large` before the handler runs.
///
/// The server already refuses bodies above `App::max_body_size` while they are
/// read; this middleware adds a per-route or per-group limit that can be
/// smaller, and also applies on the offline `App::respond` path, which does
/// not enforce the application-wide limit. Sizes are measured in bytes, so a
/// limit counts the encoded length of text bodies. Negative limits are clamped
/// to zero, rejecting every non-empty body.
pub fn middleware_body_limit(max_bytes : Int32) -> Middleware {
  let limit = if max_bytes < 0 { 0 } else { max_bytes }
  fn(next) {
    fn(ctx) raise {
      if ctx.body_bytes().length() > limit {
        clear_replaced_body_headers(ctx.response.headers)
        clear_replaced_representation_headers(ctx.response.headers)
        ctx.text(413, "413 Payload Too Large")
      } else {
        next(ctx)
      }
    }
  }
}

///|
/// Middleware that turns errors escaping the handler chain into responses:
/// `HttpError` / `HttpErrorPayload` become their status and JSON body,
/// `HttpProblem` becomes its RFC 7807 problem-details body, while any other
/// error becomes a `500` (and is reported through `log` when one is given,
/// since the client only sees a generic body).
pub fn middleware_recover(log? : (String) -> Unit) -> Middleware {
  fn(next) {
    fn(ctx) {
      next(ctx) catch {
        HttpError(status, message) => error_response(ctx, status, message)
        HttpErrorPayload(status, message, payload) =>
          error_response_with_payload(ctx, status, message, payload)
        HttpProblem(status, type_name, title, detail, instance) =>
          problem_response(ctx, status, type_name, title, detail, instance)
        err => {
          let detail = "\{err}"
          match log {
            Some(log) =>
              log("\{ctx.request.method} \{ctx.request.path} failed: \{detail}")
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
        HttpProblem(status, type_name, title, detail, instance) =>
          problem_response(ctx, status, type_name, title, detail, instance)
        err => error_response(ctx, 500, "\{err}")
      }
    }
  }
}

///|
fn logger_record(
  log : (String) -> Unit,
  ctx : Context,
  started : Int64,
  with_duration : Bool,
) -> Unit {
  let buf = StringBuilder(size_hint=if with_duration { 64 } else { 32 })
  buf.write_char('[')
  buf.write_object(ctx.response.status)
  buf.write_string("] ")
  buf.write_string(ctx.request.method)
  buf.write_char(' ')
  buf.write_string(ctx.request.path)
  if with_duration {
    let elapsed = @async.now() - started
    buf.write_string(" (")
    buf.write_object(elapsed)
    buf.write_string("ms)")
  }
  log(buf.to_string())
}

///|
/// Middleware that logs one line per request after the response is known.
///
/// The default line is `[status] METHOD request-target`; pass
/// `with_duration=true` to append the elapsed milliseconds. `skip` is evaluated
/// before the handler, so it can silence health checks or static noise based on
/// the request, including state established by earlier middleware. Skipped
/// requests still run normally; only the log line is omitted.
pub fn middleware_logger(
  log~ : (String) -> Unit = println,
  with_duration~ : Bool = false,
  skip? : (Context) -> Bool,
) -> Middleware {
  fn(next) {
    fn(ctx) raise {
      match skip {
        Some(skip) =>
          if skip(ctx) {
            next(ctx)
            return
          }
        None => ()
      }
      let started = if with_duration { @async.now() } else { 0L }
      next(ctx) catch {
        HttpError(status, message) => {
          ctx.response.status = status
          logger_record(log, ctx, started, with_duration)
          raise HttpError(status, message)
        }
        HttpErrorPayload(status, message, payload) => {
          ctx.response.status = status
          logger_record(log, ctx, started, with_duration)
          raise HttpErrorPayload(status, message, payload)
        }
        HttpProblem(status, type_name, title, detail, instance) => {
          ctx.response.status = status
          logger_record(log, ctx, started, with_duration)
          raise HttpProblem(status, type_name, title, detail, instance)
        }
        err => {
          ctx.response.status = 500
          logger_record(log, ctx, started, with_duration)
          raise err
        }
      }
      // Static files are written after the middleware chain returns, so their
      // real status (200/206/304/404/...) is not known yet. Defer the record
      // until request cleanup, after `handle_static` has filled it in.
      if ctx.state.get(STATIC_CHAIN_PASS_KEY) is Some(_) {
        ctx.defer_cleanup(fn() {
          logger_record(log, ctx, started, with_duration)
        })
      } else {
        logger_record(log, ctx, started, with_duration)
      }
    }
  }
}

///|
/// Normalize a request id: trim surrounding whitespace, remove control
/// characters, and reject a value longer than `max_length` (`0` means no
/// limit). Rejecting rather than truncating avoids splitting a surrogate pair
/// or silently changing an id that upstream services may correlate.
fn normalize_request_id(value : String, max_length : Int32) -> String {
  let clean = trim_ascii_space(
    strip_control_characters(value).view(),
  ).to_owned()
  if max_length > 0 && clean.length() > max_length {
    ""
  } else {
    clean
  }
}

///|
/// Middleware that assigns a request id, reusing an incoming `header` value when
/// present and otherwise generating a process-local `feather-<n>` value.
///
/// The id is stored in request state (read it with `Context::request_id`) and
/// echoed in the response under the same header name. Control characters are
/// stripped from a client-supplied id, so it cannot inject another header or
/// smuggle bytes into logs.
///
/// Pass `generate` to mint ids in another format (a UUID, ULID or a value from
/// a tracing library). The generated value is sanitized like an incoming one;
/// an empty or over-long result falls back to the built-in `feather-<n>`
/// counter. `max_length` caps accepted and generated ids, which bounds the
/// state and response header an untrusted client can force; `0` disables the
/// cap.
///
/// `trust_incoming` defaults to `true`, which is useful behind a gateway that
/// already assigns ids. Set it to `false` on a public endpoint so a client
/// cannot choose the id that appears in logs and tracing systems; a generated
/// id is used instead.
pub fn middleware_request_id(
  header~ : String = "X-Request-Id",
  generate? : () -> String,
  max_length~ : Int32 = 0,
  trust_incoming~ : Bool = true,
) -> Middleware {
  let counter = Ref(0)
  let limit = if max_length < 0 { 0 } else { max_length }
  fn(next) {
    fn(ctx) raise {
      // An incoming id is client-controlled, so control characters must not
      // reach the response header or the request state even on the offline
      // facade, which does not pass through the server's header sanitizer.
      // Public endpoints can set `trust_incoming=false` so a client cannot
      // choose the id that appears in logs and correlation systems.
      let incoming = if trust_incoming {
        normalize_request_id(ctx.header(header), limit)
      } else {
        ""
      }
      let id = if incoming != "" {
        incoming
      } else {
        let candidate = match get_header_ignore_case(ctx.response.headers, header) {
          Some(value) => normalize_request_id(value, limit)
          None => ""
        }
        let candidate = if candidate != "" {
          candidate
        } else {
          match generate {
            Some(generate) => normalize_request_id(generate(), limit)
            None => ""
          }
        }
        if candidate != "" {
          candidate
        } else {
          counter.val = counter.val + 1
          "feather-" + counter.val.to_string()
        }
      }
      set_header_ignore_case(ctx.response.headers, header, id)
      ctx.state.set("request_id", id)
      next(ctx)
    }
  }
}

///|
/// Whether a comma-separated header list such as `Vary` contains `token` as a
/// complete entry, compared case-insensitively. Checking element boundaries
/// keeps `Accept` from matching an existing `Accept-Encoding` entry. A `*`
/// entry covers every token (RFC 9110 §12.5.5), so it counts as a match.
fn header_list_has_token(list : StringView, token : StringView) -> Bool {
  let length = list.length()
  let mut start = 0
  let mut i = 0
  while i <= length {
    if i == length || list.unsafe_get(i) == (',' : UInt16) {
      let entry = trim_ascii_space(list[start:i])
      if entry == ("*" : StringView) || entry.equal_ignore_ascii_case(token) {
        return true
      }
      start = i + 1
    }
    i = i + 1
  }
  false
}

///|
/// Whether a `Cache-Control` field value contains `directive` as a complete
/// directive, compared case-insensitively. A directive may carry arguments
/// after `=`; quoted argument values may contain commas.
fn cache_control_has_directive(
  value : StringView,
  directive : StringView,
) -> Bool {
  let length = value.length()
  let directive_length = directive.length()
  let mut start = 0
  let mut i = 0
  let mut in_quotes = false
  while i <= length {
    let at_end = i == length
    if at_end || (value.unsafe_get(i) == (',' : UInt16) && !in_quotes) {
      let entry = trim_ascii_space(value[start:i])
      if entry.length() >= directive_length &&
        entry[:directive_length].equal_ignore_ascii_case(directive) &&
        (
          entry.length() == directive_length ||
          entry.unsafe_get(directive_length) == ('=' : UInt16)
        ) {
        return true
      }
      start = i + 1
    } else if in_quotes && value.unsafe_get(i) == ('\\' : UInt16) {
      // RFC 9110 §5.6.4 lets a quoted-string escape any character with a
      // backslash; the escaped character (often a quote or a comma) must not
      // affect the quote balance or the directive split.
      i = i + 1
    } else if value.unsafe_get(i) == ('"' : UInt16) {
      in_quotes = !in_quotes
    }
    i = i + 1
  }
  false
}

///|
/// Append the field names in `value` to the response's `Vary` header unless
/// they are already listed.
///
/// `value` may name more than one field, separated by commas. Each field is
/// matched case-insensitively against the existing list, so passing
/// `"Origin, Accept-Encoding"` in pieces does not create duplicate entries.
pub fn Context::vary(self : Context, value : String) -> Unit {
  // `Vary` is a list of field names, so split the caller's value into complete
  // entries. Empty entries (for example a trailing comma) are ignored.
  let names : Array[String] = []
  for part in value.view().split(",") {
    let name = trim_ascii_space(part)
    if !name.is_empty() {
      names.push(name.to_owned())
    }
  }
  if names.is_empty() {
    return
  }
  // RFC 9110 §12.5.5 defines `*` as the entire field value, so a wildcard
  // replaces whatever was already listed instead of being appended to it.
  for name in names {
    if name.view().equal_ignore_ascii_case("*".view()) {
      set_header_ignore_case(self.response.headers, "Vary", "*")
      return
    }
  }
  let existing = match get_header_ignore_case(self.response.headers, "Vary") {
    Some(existing) => existing
    None => ""
  }
  let additions : Array[String] = []
  for name in names {
    if !header_list_has_token(existing.view(), name.view()) &&
      !header_list_has_token(additions.join(", ").view(), name.view()) {
      additions.push(name)
    }
  }
  if additions.length() == 0 {
    return
  }
  if trim_ascii_space(existing.view()).is_empty() {
    set_header_ignore_case(self.response.headers, "Vary", additions.join(", "))
  } else {
    set_header_ignore_case(
      self.response.headers,
      "Vary",
      existing + ", " + additions.join(", "),
    )
  }
}

///|
/// Set an optional hardening header, leaving the response untouched when the
/// caller did not configure a value.
fn set_optional_hardening_header(
  headers : Map[String, String],
  name : String,
  value : String?,
) -> Unit {
  match value {
    Some(value) => set_header_ignore_case(headers, name, value)
    None => ()
  }
}

///|
/// Middleware that adds hardening headers to every response: `nosniff`,
/// clickjacking protection and a referrer policy by default.
///
/// Pass `hsts` to also advertise `Strict-Transport-Security` (only meaningful
/// over HTTPS), `content_security_policy` to lock down which resources the
/// browser may load, or the corresponding `*_report_only` /
/// `permissions_policy` / `cross_origin_*` options for the modern policy
/// headers. Optional values are only emitted when supplied, so a minimal
/// installation keeps the same response headers as before.
pub fn middleware_secure_headers(
  content_type_options~ : String = "nosniff",
  frame_options~ : String = "DENY",
  referrer_policy~ : String = "no-referrer",
  hsts? : String,
  content_security_policy? : String,
  content_security_policy_report_only? : String,
  permissions_policy? : String,
  cross_origin_opener_policy? : String,
  cross_origin_embedder_policy? : String,
  cross_origin_resource_policy? : String,
) -> Middleware {
  fn(next) {
    fn(ctx) raise {
      let headers = ctx.response.headers
      set_header_ignore_case(
        headers,
        "X-Content-Type-Options",
        content_type_options,
      )
      set_header_ignore_case(headers, "X-Frame-Options", frame_options)
      set_header_ignore_case(headers, "Referrer-Policy", referrer_policy)
      set_optional_hardening_header(
        headers,
        "Strict-Transport-Security",
        hsts,
      )
      set_optional_hardening_header(
        headers,
        "Content-Security-Policy",
        content_security_policy,
      )
      set_optional_hardening_header(
        headers,
        "Content-Security-Policy-Report-Only",
        content_security_policy_report_only,
      )
      set_optional_hardening_header(
        headers,
        "Permissions-Policy",
        permissions_policy,
      )
      set_optional_hardening_header(
        headers,
        "Cross-Origin-Opener-Policy",
        cross_origin_opener_policy,
      )
      set_optional_hardening_header(
        headers,
        "Cross-Origin-Embedder-Policy",
        cross_origin_embedder_policy,
      )
      set_optional_hardening_header(
        headers,
        "Cross-Origin-Resource-Policy",
        cross_origin_resource_policy,
      )
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
      let raw_authority = match fixed_host {
        Some(value) => value
        None => trim_ascii_space(ctx.header("Host").view()).to_owned()
      }
      // A control character in the authority would forge extra header lines in
      // the `Location` field. An authority that is not a bare host (optionally
      // with a port) would splice extra path, userinfo or scheme characters
      // into the URL, so both cases pass the request through like a missing
      // host instead of emitting a misleading redirect.
      let cleaned = strip_control_characters(raw_authority)
      let authority = trim_ascii_space(cleaned.view()).to_owned()
      if cleaned != raw_authority ||
        authority == "" ||
        host_authority_host(authority.view()) is None {
        next(ctx)
        return
      }
      // The asterisk-form target names the server rather than a URL path, so
      // there is no location to redirect it to.
      if ctx.request.path == "*" {
        next(ctx)
        return
      }
      let path = strip_control_characters(ctx.request.path)
      // Keep the location origin-relative even for hand-built contexts whose
      // request target did not start with a slash.
      let path = if path.has_prefix("/") { path } else { "/" + path }
      ctx.redirect(status, "https://" + authority + path)
    }
  }
}

///|
/// Whether `code` is a character allowed in a host name. Underscores are
/// accepted too because they occur in real deployments even though DNS host
/// labels should not use them.
fn is_host_name_character(code : Int32) -> Bool {
  (code >= 48 && code <= 57) ||
  (code >= 65 && code <= 90) ||
  (code >= 97 && code <= 122) ||
  code == 45 ||
  code == 46 ||
  code == 95
}

///|
/// Value of one hexadecimal digit, or `-1` for any other character.
fn hex_digit_value(unit : UInt16) -> Int32 {
  let code = unit.to_int()
  if code >= 48 && code <= 57 {
    code - 48
  } else if code >= 65 && code <= 70 {
    code - 65 + 10
  } else if code >= 97 && code <= 102 {
    code - 97 + 10
  } else {
    -1
  }
}

///|
/// Whether `view` is a dotted-decimal IPv4 address with four octets in range.
fn valid_ipv4_literal(view : StringView) -> Bool {
  let parts : Array[StringView] = []
  for part in view.split(".") {
    parts.push(part)
  }
  if parts.length() != 4 {
    return false
  }
  for part in parts {
    let length = part.length()
    if length == 0 || length > 3 {
      return false
    }
    if length > 1 && part.unsafe_get(0) == ('0' : UInt16) {
      return false
    }
    let mut value = 0
    let mut i = 0
    while i < length {
      let digit = part.unsafe_get(i).to_int() - 48
      if digit < 0 || digit > 9 {
        return false
      }
      value = value * 10 + digit
      i = i + 1
    }
    if value > 255 {
      return false
    }
  }
  true
}

///|
/// Count the 16-bit groups in one side of an IPv6 address. The optional dotted
/// tail is only valid at the end of the whole address and contributes two
/// groups instead of one.
fn ipv6_group_count(
  view : StringView,
  allow_ipv4_tail : Bool,
) -> Int32? {
  if view.is_empty() {
    return Some(0)
  }
  let parts : Array[StringView] = []
  for part in view.split(":") {
    parts.push(part)
  }
  let last = parts.length() - 1
  let mut groups = 0
  let mut index = 0
  while index < parts.length() {
    let part = parts[index]
    if part.is_empty() {
      return None
    }
    if part.contains(".") {
      if !allow_ipv4_tail || index != last || !valid_ipv4_literal(part) {
        return None
      }
      groups = groups + 2
    } else {
      let length = part.length()
      if length > 4 {
        return None
      }
      let mut i = 0
      while i < length {
        if hex_digit_value(part.unsafe_get(i)) < 0 {
          return None
        }
        i = i + 1
      }
      groups = groups + 1
    }
    index = index + 1
  }
  Some(groups)
}

///|
/// Validate a bracketed IP literal: an IPv6 address with at most one `::`
/// compression (and an optional zone identifier), or an RFC 3986 IPvFuture
/// literal such as `[v1.foo]`.
fn valid_bracketed_host(view : StringView) -> Bool {
  let length = view.length()
  if length == 0 {
    return false
  }
  if view.unsafe_get(0) == ('v' : UInt16) ||
    view.unsafe_get(0) == ('V' : UInt16) {
    let dot = match view.find(".") {
      Some(index) => index
      None => return false
    }
    if dot <= 1 {
      return false
    }
    let mut i = 1
    while i < dot {
      if hex_digit_value(view.unsafe_get(i)) < 0 {
        return false
      }
      i = i + 1
    }
    i = dot + 1
    if i >= length {
      return false
    }
    while i < length {
      let code = view.unsafe_get(i).to_int()
      let allowed = is_host_name_character(code) ||
        code == 58 ||
        code == 33 ||
        (code >= 36 && code <= 38) ||
        code == 39 ||
        code == 40 ||
        code == 41 ||
        code == 42 ||
        code == 43 ||
        code == 44 ||
        code == 59 ||
        code == 61 ||
        code == 126
      if !allowed {
        return false
      }
      i = i + 1
    }
    return true
  }
  // A zone identifier follows `%` and is not part of the IPv6 address. In a
  // URI it is usually percent-encoded (`%25eth0`), so validate the zone text
  // as unreserved characters or complete `%HH` escapes instead of accepting
  // stray percent signs and separators.
  let address = match view.find("%") {
    Some(index) => {
      if index == 0 || index + 1 >= length {
        return false
      }
      let mut i = index + 1
      while i < length {
        let code = view.unsafe_get(i).to_int()
        if code == 37 {
          if i + 2 >= length ||
            hex_digit_value(view.unsafe_get(i + 1)) < 0 ||
            hex_digit_value(view.unsafe_get(i + 2)) < 0 {
            return false
          }
          i = i + 3
        } else if is_host_name_character(code) || code == 126 {
          i = i + 1
        } else {
          return false
        }
      }
      view[:index]
    }
    None => view
  }
  match address.find("::") {
    Some(index) => {
      let left = address[:index]
      let right = address[index + 2:]
      if right.find("::") is Some(_) {
        return false
      }
      let left_groups = match ipv6_group_count(left, false) {
        Some(groups) => groups
        None => return false
      }
      let right_groups = match ipv6_group_count(right, true) {
        Some(groups) => groups
        None => return false
      }
      // `::` represents at least one zero group.
      left_groups + right_groups <= 7
    }
    None =>
      match ipv6_group_count(address, true) {
        Some(groups) => groups == 8
        None => false
      }
  }
}

///|
/// Validate the part of an authority between the brackets (for an IP literal)
/// or the whole host name.
fn valid_host_name(view : StringView, bracketed : Bool) -> Bool {
  if bracketed {
    return valid_bracketed_host(view)
  }
  let length = view.length()
  if length == 0 {
    return false
  }
  let mut i = 0
  while i < length {
    let code = view.unsafe_get(i).to_int()
    if !is_host_name_character(code) {
      return false
    }
    i = i + 1
  }
  if view.unsafe_get(0) == ('.' : UInt16) {
    return false
  }
  // A trailing dot denotes the DNS root and is allowed, but every other label
  // must be non-empty: `example..com` and `example..` are malformed
  // authorities, not subdomains of `example.com`.
  let mut label_start = 0
  let mut index = 0
  while index <= length {
    if index == length ||
      view.unsafe_get(index) == ('.' : UInt16) {
      if index == label_start &&
        !(index == length && label_start > 0) {
        return false
      }
      label_start = index + 1
    }
    index = index + 1
  }
  true
}

///|
/// Whether `value` is a syntactically valid decimal TCP/UDP port. An empty
/// value or one above 65535 is rejected.
fn valid_host_port(value : StringView) -> Bool {
  let length = value.length()
  if length == 0 {
    return false
  }
  let mut port = 0
  let mut i = 0
  while i < length {
    let digit = value.unsafe_get(i).to_int() - 48
    if digit < 0 || digit > 9 {
      return false
    }
    port = port * 10 + digit
    if port > 65535 {
      return false
    }
    i = i + 1
  }
  true
}

///|
/// Parse a `Host` header (or a configured host) into its port-less name.
///
/// A bracketed IPv6 literal keeps its brackets; an optional numeric port is
/// validated and dropped. A malformed authority, embedded whitespace or
/// control character, unbracketed IPv6 literal, or an empty host yields
/// `None`. A single trailing dot, which denotes an absolute DNS name, is
/// removed so `example.com.` matches `example.com`.
fn host_authority_host(value : StringView) -> String? {
  let authority = trim_ascii_space(value)
  let length = authority.length()
  if length == 0 {
    return None
  }
  // Header values must not carry separators or control characters into the
  // parsed host: such values are malformed rather than matchable.
  let mut scan = 0
  while scan < length {
    let code = authority.unsafe_get(scan).to_int()
    if code <= 0x20 || code == 0x7F || code == 44 {
      return None
    }
    scan = scan + 1
  }
  if authority.unsafe_get(0) == ('[' : UInt16) {
    let close = match authority.find("]") {
      Some(index) => index
      None => return None
    }
    if close <= 1 || !valid_host_name(authority[1:close], true) {
      return None
    }
    let rest = authority[close + 1:]
    if rest.length() == 0 {
      return Some(authority[:close + 1].to_owned())
    }
    if rest.unsafe_get(0) != (':' : UInt16) ||
      !valid_host_port(rest[1:]) {
      return None
    }
    return Some(authority[:close + 1].to_owned())
  }
  let mut colons = 0
  let mut last_colon = -1
  let mut i = 0
  while i < length {
    if authority.unsafe_get(i) == (':' : UInt16) {
      colons = colons + 1
      last_colon = i
    }
    i = i + 1
  }
  let host = if colons == 0 {
    authority
  } else if colons == 1 {
    if last_colon <= 0 || !valid_host_port(authority[last_colon + 1:]) {
      return None
    }
    authority[:last_colon]
  } else {
    // More than one colon without brackets is a bare IPv6 literal, which is
    // not a valid HTTP authority.
    return None
  }
  if !valid_host_name(host, false) {
    return None
  }
  let text = host.to_owned()
  if text.length() > 1 && text.has_suffix(".") {
    Some(text[:text.length() - 1].to_owned())
  } else {
    Some(text)
  }
}

///|
/// Normalize one configured host pattern. `"*"` accepts any well-formed host;
/// `"*.example.com"` accepts that domain's subdomains; everything else is an
/// exact host name. A configured port is accepted and ignored.
fn normalize_host_pattern(value : String) -> String? {
  let trimmed = trim_ascii_space(value.view())
  if trimmed == "*" {
    return Some("*")
  }
  if trimmed.has_prefix("*.") {
    match host_authority_host(trimmed[2:]) {
      Some(host) => Some("*." + host)
      None => None
    }
  } else {
    host_authority_host(trimmed)
  }
}

///|
/// Case-insensitive `ends_with` for ASCII host names.
fn host_ends_with_ignore_ascii_case(
  value : StringView,
  suffix : StringView,
) -> Bool {
  if suffix.length() > value.length() {
    return false
  }
  let offset = value.length() - suffix.length()
  let mut i = 0
  while i < suffix.length() {
    let left = value.unsafe_get(offset + i).to_int()
    let right = suffix.unsafe_get(i).to_int()
    let lower_left = if left >= 65 && left <= 90 { left + 32 } else { left }
    let lower_right = if right >= 65 && right <= 90 {
      right + 32
    } else {
      right
    }
    if lower_left != lower_right {
      return false
    }
    i = i + 1
  }
  true
}

///|
/// Whether a validated request `host` matches a normalized configured
/// `pattern`.
fn host_matches_pattern(host : String, pattern : String) -> Bool {
  if pattern == "*" {
    return true
  }
  let pattern_view = pattern.view()
  if pattern_view.has_prefix("*.") {
    let suffix = pattern_view[1:]
    host.length() > suffix.length() &&
    host_ends_with_ignore_ascii_case(host.view(), suffix)
  } else {
    host.view().equal_ignore_ascii_case(pattern_view)
  }
}

///|
/// Middleware that rejects requests whose `Host` header is not in the
/// allowlist with `400 Bad Request`, before the handler runs.
///
/// Host names are matched case-insensitively after an optional port is
/// stripped, so `example.com`, `Example.COM:8080` and `example.com.` all match
/// the entry `"example.com"`. An entry starting with `*.` accepts any
/// subdomain of that domain (`*.example.com` matches `api.example.com` and
/// `a.b.example.com`, but not `example.com` itself), and `"*"` accepts any
/// well-formed authority. Malformed authorities, including embedded control
/// characters, unbracketed IPv6 literals and invalid ports, are rejected.
///
/// The `Host` header is used directly and forwarded-host headers are ignored,
/// so a client cannot bypass the check by setting `X-Forwarded-Host`. A
/// missing `Host` is rejected by default; pass `allow_missing=true` for
/// HTTP/1.0 clients or health checks that do not send one.
pub fn middleware_allowed_hosts(
  hosts : Array[String],
  allow_missing~ : Bool = false,
) -> Middleware {
  let patterns : Array[String] = []
  for host in hosts {
    match normalize_host_pattern(host) {
      Some(pattern) => patterns.push(pattern)
      None => ()
    }
  }
  fn(next) {
    fn(ctx) raise {
      let raw = ctx.header("Host")
      if trim_ascii_space(raw.view()).is_empty() {
        if allow_missing {
          next(ctx)
        } else {
          clear_replaced_representation_headers(ctx.response.headers)
          ctx.text(400, "400 Bad Request")
        }
        return
      }
      let accepted = match host_authority_host(raw.view()) {
        Some(host) => {
          let mut matched = false
          for pattern in patterns {
            if host_matches_pattern(host, pattern) {
              matched = true
            }
          }
          matched
        }
        None => false
      }
      if accepted {
        next(ctx)
      } else {
        clear_replaced_representation_headers(ctx.response.headers)
        ctx.text(400, "400 Bad Request")
      }
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
      if ctx.get_method().view().equal_ignore_ascii_case("POST".view()) {
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
priv enum CorsOriginPolicy {
  CorsOriginFixed(String)
  CorsOriginPredicate((String) -> Bool)
}

///|
/// Shared implementation of the fixed-origin and predicate CORS middleware.
fn cors_middleware(
  policy : CorsOriginPolicy,
  allow_methods : String,
  allow_headers : String,
  expose_headers : String,
  allow_credentials : Bool,
  max_age : Int32,
  allow_private_network : Bool,
) -> Middleware {
  fn(next) {
    fn(ctx) raise {
      let raw_origin = trim_ascii_space(ctx.header("Origin").view()).to_owned()
      // Origins are ASCII tokens without control characters. Reject a malformed
      // value instead of echoing it into a response header, where CR/LF could
      // forge additional fields.
      let origin = strip_control_characters(raw_origin)
      let origin = if origin == raw_origin { origin } else { "" }
      let is_options = ctx.get_method().view().equal_ignore_ascii_case(
        "OPTIONS".view(),
      )
      // A wildcard policy with credentials cannot keep the wildcard grant for
      // an Origin-bearing request; it echoes that Origin instead. The response
      // therefore depends on `Origin` even when the request has none, where it
      // falls back to `*`.
      let wildcard_credentials = if allow_credentials {
        match policy {
          CorsOriginFixed(value) => value == "*"
          CorsOriginPredicate(_) => false
        }
      } else {
        false
      }
      let (allowed_origin, dynamic_origin) = match policy {
        CorsOriginFixed(value) =>
          if value != "*" {
            (value, true)
          } else if wildcard_credentials {
            // A malformed Origin is discarded and answered like an anonymous
            // request. Only a valid Origin, or the absence of the field, can
            // change the representation that a shared cache must separate.
            (
              if origin != "" { origin } else { "*" },
              origin != "" || raw_origin == "",
            )
          } else {
            ("*", false)
          }
        CorsOriginPredicate(check) =>
          if origin != "" && check(origin) {
            (origin, true)
          } else {
            // Rejecting an origin is just as dependent on the request's
            // `Origin` as accepting one: the same URL can return a grant for
            // an allowed origin and none for this request.
            ("", true)
          }
      }
      if allowed_origin != "" {
        set_header_ignore_case(
          ctx.response.headers,
          "Access-Control-Allow-Origin",
          allowed_origin,
        )
      }
      if dynamic_origin {
        // The answer depends on the request's `Origin`, so shared caches must
        // keep origins apart.
        ctx.vary("Origin")
      }
      if allow_credentials &&
        allowed_origin != "" &&
        (origin != "" || !wildcard_credentials) {
        // `Access-Control-Allow-Origin: *` and credentials are an invalid
        // pair. A no-Origin request is not a CORS request, so omit the
        // credentials grant there while still keeping the wildcard for
        // non-credentialed clients.
        set_header_ignore_case(
          ctx.response.headers,
          "Access-Control-Allow-Credentials",
          "true",
        )
      }
      if is_options {
        // A real CORS preflight carries both `Origin` and
        // `Access-Control-Request-Method` and is answered here without running
        // the handler. Other OPTIONS requests (including explicit OPTIONS
        // routes) pass through to the router and are only decorated with the
        // CORS headers below.
        let preflight = origin != "" &&
          ctx.header("Access-Control-Request-Method") != ""
        if preflight {
          ctx.file = None
          ctx.response.status = 204
          ctx.response.data = None
          ctx.response.body = ""
          ignore(
            remove_header_ignore_case(ctx.response.headers, "Content-Type"),
          )
          ignore(
            remove_header_ignore_case(ctx.response.headers, "Content-Length"),
          )
          ignore(
            remove_header_ignore_case(ctx.response.headers, "Content-Encoding"),
          )
          ignore(
            remove_header_ignore_case(ctx.response.headers, "Content-Range"),
          )
          clear_replaced_representation_headers(ctx.response.headers)
          // A rejected origin must not receive any CORS grant. The credentials
          // header is set before the origin decision, so remove it here when
          // this preflight has no accepted origin.
          if allowed_origin == "" {
            ignore(
              remove_header_ignore_case(
                ctx.response.headers,
                "Access-Control-Allow-Credentials",
              ),
            )
          }
          // A denied preflight still depends on `Origin`: its 204 carries no
          // CORS grants, while an accepted one does. Add the key here when the
          // origin itself was not already recorded as dynamic.
          if dynamic_origin || allowed_origin == "" {
            ctx.vary("Origin")
          }
          // The preflight answer depends on the two request headers, so shared
          // caches must key on them as well (Fetch: Vary considerations).
          ctx.vary("Access-Control-Request-Method")
          ctx.vary("Access-Control-Request-Headers")
          if allow_private_network {
            // The grant is conditional on the browser's request header, so a
            // shared cache must not reuse this preflight for another request.
            ctx.vary("Access-Control-Request-Private-Network")
          }
        } else {
          next(ctx)
        }
        if allowed_origin != "" {
          set_header_ignore_case(
            ctx.response.headers,
            "Access-Control-Allow-Methods",
            allow_methods,
          )
          // With credentials the `*` wildcard is a literal header name, so a
          // preflight asking for anything else must see its own list echoed
          // back (Fetch: CORS-preflight fetch).
          let allowed_headers = if allow_headers == "*" && allow_credentials {
            match get_header_ignore_case(
              ctx.request.headers,
              "Access-Control-Request-Headers",
            ) {
              Some(requested) =>
                if requested == "" {
                  allow_headers
                } else {
                  strip_control_characters(requested)
                }
              None => allow_headers
            }
          } else {
            allow_headers
          }
          set_header_ignore_case(
            ctx.response.headers,
            "Access-Control-Allow-Headers",
            allowed_headers,
          )
          if max_age > 0 {
            set_header_ignore_case(
              ctx.response.headers,
              "Access-Control-Max-Age",
              max_age.to_string(),
            )
          }
          if preflight &&
            allow_private_network &&
            trim_ascii_space(
              ctx.header("Access-Control-Request-Private-Network").view(),
            ).equal_ignore_ascii_case("true".view()) {
            // Chrome's Private Network Access preflight asks the public origin
            // to opt in explicitly. Only an accepted origin gets the grant.
            set_header_ignore_case(
              ctx.response.headers,
              "Access-Control-Allow-Private-Network",
              "true",
            )
          }
        }
      } else {
        if expose_headers != "" && allowed_origin != "" {
          set_header_ignore_case(
            ctx.response.headers,
            "Access-Control-Expose-Headers",
            expose_headers,
          )
        }
        next(ctx)
      }
    }
  }
}

///|
/// Middleware that adds CORS response headers and answers preflight requests.
///
/// `allow_origin` is either `"*"` (the default) or a concrete origin to
/// advertise; when credentials are enabled the request's `Origin` is echoed
/// instead, because browsers reject a wildcard with credentials. Use
/// `middleware_cors_with` for a dynamic predicate or
/// `middleware_cors_allowlist` for a fixed set of accepted origins. Pass
/// `allow_private_network=true` to grant a browser's Private Network Access
/// preflight when it asks for it.
pub fn middleware_cors(
  allow_origin~ : String = "*",
  allow_methods~ : String = "GET, POST, PUT, PATCH, DELETE, HEAD, OPTIONS",
  allow_headers~ : String = "*",
  expose_headers~ : String = "",
  allow_credentials~ : Bool = false,
  max_age~ : Int32 = 0,
  allow_private_network~ : Bool = false,
) -> Middleware {
  cors_middleware(
    CorsOriginFixed(allow_origin),
    allow_methods,
    allow_headers,
    expose_headers,
    allow_credentials,
    max_age,
    allow_private_network,
  )
}

///|
/// CORS middleware whose accepted origin is decided per request.
///
/// The predicate receives the request's non-empty `Origin`; returning `true`
/// echoes that origin in `Access-Control-Allow-Origin` and adds `Vary:
/// Origin`. Requests with an origin the predicate rejects (and requests
/// without an `Origin`) are passed through without CORS headers. Preflight
/// requests are still answered with `204`, so a rejected origin never reaches
/// the handler.
pub fn middleware_cors_with(
  allow_origin~ : (String) -> Bool,
  allow_methods~ : String = "GET, POST, PUT, PATCH, DELETE, HEAD, OPTIONS",
  allow_headers~ : String = "*",
  expose_headers~ : String = "",
  allow_credentials~ : Bool = false,
  max_age~ : Int32 = 0,
  allow_private_network~ : Bool = false,
) -> Middleware {
  cors_middleware(
    CorsOriginPredicate(allow_origin),
    allow_methods,
    allow_headers,
    expose_headers,
    allow_credentials,
    max_age,
    allow_private_network,
  )
}

///|
/// CORS middleware that accepts only the listed origins.
///
/// Matching is exact and case-sensitive, which is the right default for the
/// serialized origins browsers send. An empty list rejects every origin while
/// still answering preflight requests.
pub fn middleware_cors_allowlist(
  origins : Array[String],
  allow_methods~ : String = "GET, POST, PUT, PATCH, DELETE, HEAD, OPTIONS",
  allow_headers~ : String = "*",
  expose_headers~ : String = "",
  allow_credentials~ : Bool = false,
  max_age~ : Int32 = 0,
  allow_private_network~ : Bool = false,
) -> Middleware {
  let accepted = origins.copy()
  middleware_cors_with(
    allow_origin=fn(origin) {
      let mut found = false
      for candidate in accepted {
        if candidate == origin {
          found = true
        }
      }
      found
    },
    allow_methods~,
    allow_headers~,
    expose_headers~,
    allow_credentials~,
    max_age~,
    allow_private_network~,
  )
}

///|
fn auth_challenge(scheme : String, realm : String) -> String {
  let clean = strip_control_characters(realm)
  let view = clean.view()
  let length = view.length()
  let builder = StringBuilder(size_hint=scheme.length() + length + 16)
  builder.write_string(scheme)
  builder.write_string(" realm=\"")
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
fn basic_auth_challenge(realm : String) -> String {
  auth_challenge("Basic", realm)
}

///|
fn bearer_auth_challenge(realm : String) -> String {
  auth_challenge("Bearer", realm)
}

///|
fn constant_time_equal(left : String, right : String) -> Bool {
  let left_view = left.view()
  let right_view = right.view()
  let left_length = left_view.length()
  let right_length = right_view.length()
  let mut difference = left_length ^ right_length
  let length = if left_length > right_length {
    left_length
  } else {
    right_length
  }
  for i = 0; i < length; i = i + 1 {
    let a = if i < left_length { left_view.unsafe_get(i) } else { 0 }
    let b = if i < right_length { right_view.unsafe_get(i) } else { 0 }
    difference = difference | (a ^ b).to_int()
  }
  difference == 0
}

///|
fn bearer_auth_middleware(
  check : (String) -> Bool,
  realm : String,
) -> Middleware {
  let challenge = bearer_auth_challenge(realm)
  fn(next) {
    fn(ctx) raise {
      let authorized = match ctx.bearer_token() {
        Some(token) => check(token)
        None => false
      }
      if authorized {
        next(ctx)
      } else {
        ctx.file = None
        ctx.response.status = 401
        clear_replaced_body_headers(ctx.response.headers)
        clear_replaced_representation_headers(ctx.response.headers)
        set_header_ignore_case(
          ctx.response.headers,
          "WWW-Authenticate",
          challenge,
        )
        set_header_ignore_case(
          ctx.response.headers,
          "Content-Type",
          "text/plain; charset=utf-8",
        )
        ctx.response.data = None
        ctx.response.body = "401 Unauthorized"
      }
    }
  }
}

///|
fn basic_auth_middleware(
  check : (String, String) -> Bool,
  realm : String,
) -> Middleware {
  let challenge = basic_auth_challenge(realm)
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
        clear_replaced_body_headers(ctx.response.headers)
        clear_replaced_representation_headers(ctx.response.headers)
        set_header_ignore_case(
          ctx.response.headers,
          "WWW-Authenticate",
          challenge,
        )
        set_header_ignore_case(
          ctx.response.headers,
          "Content-Type",
          "text/plain; charset=utf-8",
        )
        ctx.response.data = None
        ctx.response.body = "401 Unauthorized"
      }
    }
  }
}

///|
/// Middleware that challenges requests with a bearer token and accepts any
/// configured opaque token. Tokens are compared with the same constant-time
/// helper used by basic authentication.
pub fn middleware_bearer_auth(
  tokens : Array[String],
  realm~ : String = "Restricted",
) -> Middleware {
  bearer_auth_middleware(
    fn(token) {
      let mut accepted = false
      for expected in tokens {
        if constant_time_equal(token, expected) {
          accepted = true
        }
      }
      accepted
    },
    realm,
  )
}

///|
/// Middleware that challenges requests with a bearer token and accepts tokens
/// approved by `check`.
pub fn middleware_bearer_auth_with(
  check : (String) -> Bool,
  realm~ : String = "Restricted",
) -> Middleware {
  bearer_auth_middleware(check, realm)
}

///|
/// Middleware that challenges requests with HTTP Basic authentication and
/// accepts credentials listed in `accounts`.
pub fn middleware_basic_auth(
  accounts : Map[String, String],
  realm~ : String = "Restricted",
) -> Middleware {
  basic_auth_middleware(
    fn(username, password) {
      match accounts.get(username) {
        Some(expected) => constant_time_equal(password, expected)
        None => false
      }
    },
    realm,
  )
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
