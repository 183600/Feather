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

