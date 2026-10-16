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
  method : String
  path : String
  headers : Map[String, String]
  body : String
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
}

///|
pub type Handler = (Context) -> Unit raise

///|
pub type Middleware = (Handler) -> Handler

///|
pub type WebSocketHandler = async (Context, @websocket.Conn) -> Unit raise

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
  mut pattern_kinds : Array[Int]
  mut route_wildcard_name : String
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
    pattern_kinds: [],
    route_wildcard_name: "",
  }
}

///|
pub fn create_router() -> Router {
  { routes: [], trees: Map([]), named: Map([]), }
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
  match path[start:].find("/") {
    Some(offset) => start + offset
    None => path.length()
  }
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
fn extract_route_params(
  node : RouteNode,
  path : StringView,
) -> (Map[String, String], String) {
  let names = node.param_names
  let params : Map[String, String] = Map([], capacity=names.length() + 1)
  let mut path_pos = skip_slashes(path, 0)
  let mut name_index = 0
  let mut wildcard_value = ""
  for kind in node.pattern_kinds {
    if kind == 1 {
      let path_end = segment_end(path, path_pos)
      if name_index < names.length() {
        params.set(names[name_index], path[path_pos:path_end].to_owned())
      }
      name_index = name_index + 1
      path_pos = skip_slashes(path, path_end + 1)
    } else if kind == 0 {
      path_pos = skip_slashes(path, segment_end(path, path_pos) + 1)
    } else {
      wildcard_value = join_wildcard(path, path_pos)
      if node.route_wildcard_name != "" {
        params.set(node.route_wildcard_name, wildcard_value)
      }
      break
    }
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
pub fn Router::add_route(
  self : Router,
  meth : String,
  path : String,
  handler : Handler,
) -> Unit {
  let clean_path = clean_route_path(path)
  let method_key = meth
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
  let pattern_kinds : Array[Int] = []
  let mut route_wildcard_name = ""
  for segment in split_segments(clean_path) {
    if segment.has_prefix(":") {
      param_names.push(segment[1:].to_owned())
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
      route_wildcard_name = segment[1:].to_owned()
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
  node.pattern_kinds = pattern_kinds
  node.route_wildcard_name = route_wildcard_name
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
  self.named.set(name, { method: meth, path: clean_path, })
}

///|
pub fn Router::route_name(self : Router, name : String) -> NamedRoute? {
  self.named.get(name)
}

///|
fn encode_wildcard_path(value : String) -> String {
  let view = value.view()
  let length = view.length()
  let builder = StringBuilder(size_hint=length)
  let mut start = 0
  let mut i = 0
  while i < length {
    if view.unsafe_get(i) == ('/' : UInt16) {
      builder.write_string(url_encode(view[start:i].to_owned()))
      builder.write_char('/')
      start = i + 1
    }
    i = i + 1
  }
  if start < length {
    builder.write_string(url_encode(view[start:].to_owned()))
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
      match values.get_from_string(segment[1:]) {
        Some(value) => builder.write_string(encode_wildcard_path(value))
        None => return None
      }
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
priv enum RouteMatch {
  MatchFound(RouteNode, Map[String, String]?, String)
  MatchMethods(Array[String])
  MatchMissing
}

///|
fn Router::find_node(
  self : Router,
  tree_key : String,
  clean_path : StringView,
) -> (RouteNode, Map[String, String]?, String)? {
  let root = match self.trees.get(tree_key) {
    Some(root) => root
    None => return None
  }
  if !root.has_dynamic {
    match match_static_node(root, clean_path, 0) {
      Some(node) => Some((node, None, ""))
      None => None
    }
  } else {
    match match_dynamic_node(root, clean_path, 0) {
      Some(outcome) => {
        let node = outcome.node
        if outcome.wildcard_start < 0 && node.param_names.length() == 0 {
          Some((node, None, ""))
        } else {
          let (params, wildcard_value) = extract_route_params(node, clean_path)
          Some((node, Some(params), wildcard_value))
        }
      }
      None => None
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
      method: meth,
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
  match self.match_route(ctx.request.method, clean_path) {
    MatchFound(node, params, _) => {
      match params {
        Some(params) =>
          for name, value in params {
            ctx.state.set(PARAM_PREFIX + name, value)
          }
        None => ()
      }
      match node.handler {
        Some(handler) => handler(ctx)
        None => not_found(ctx)
      }
    }
    MatchMethods(methods) => method_not_allowed(ctx, methods)
    MatchMissing =>
      match fallback {
        Some(handler) => handler(ctx)
        None => not_found(ctx)
      }
  }
}

///|
pub fn not_found(ctx : Context) -> Unit {
  ctx.response.status = 404
  ctx.response.headers.set("Content-Type", "text/plain; charset=utf-8")
  ctx.response.data = None
  ctx.response.body = "404 Not Found"
}

///|
pub fn method_not_allowed(ctx : Context, allowed : Array[String]) -> Unit {
  ctx.response.status = 405
  ctx.response.headers.set("Allow", allowed.join(", "))
  ctx.response.headers.set("Content-Type", "text/plain; charset=utf-8")
  ctx.response.data = None
  ctx.response.body = "405 Method Not Allowed"
}

///|
pub fn internal_error(ctx : Context, detail : String) -> Unit {
  ctx.state.set("error", detail)
  ctx.response.status = 500
  ctx.response.headers.set("Content-Type", "text/plain; charset=utf-8")
  ctx.response.data = None
  ctx.response.body = "Internal Server Error"
}

///|
pub fn error_response(ctx : Context, status : Int32, message : String) -> Unit {
  let payload : Map[String, Json] = Map([], capacity=2)
  payload.set("status", Json::number(status.to_double()))
  payload.set("error", Json::string(message))
  ctx.response.status = status
  ctx.response.headers.set("Content-Type", "application/json; charset=utf-8")
  ctx.response.data = None
  ctx.response.body = Json::object(payload).stringify()
}

///|
pub fn error_response_with_payload(
  ctx : Context,
  status : Int32,
  message : String,
  payload : Json,
) -> Unit {
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
pub fn Context::param(self : Context, name : String) -> String {
  match self.state.get(PARAM_PREFIX + name) {
    Some(value) => value
    None => ""
  }
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
  self.response.status = status
  self.response.headers.set("Content-Type", content_type)
  self.response.body = ""
  self.response.data = Some(data)
}

///|
pub fn Context::html(self : Context, status : Int32, body : String) -> Unit {
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
  self.response.status = status
  self.response.headers.set("Content-Type", "application/json; charset=utf-8")
  self.response.data = None
  self.response.body = data.stringify()
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
  self.response.status = status
  self.response.headers.set("Location", location)
  self.response.data = None
  self.response.body = ""
}

///|
pub fn Context::no_content(self : Context) -> Unit {
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
      for name, value in self.request.headers {
        if name.view().equal_ignore_ascii_case(target) {
          return value
        }
      }
      ""
    }
  }
}

///|
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
      Some(index) => forwarded[:index].trim().to_owned()
      None => forwarded.trim().to_owned()
    }
  }
  let real_ip = self.header("X-Real-IP")
  if real_ip != "" {
    return real_ip.trim().to_owned()
  }
  self.ip()
}

///|
pub fn Context::cookies(self : Context) -> Map[String, String] {
  let cookies : Map[String, String] = Map([], capacity=4)
  for pair in self.header("Cookie").view().split(";") {
    let pair = pair.trim()
    if pair.is_empty() {
      continue
    }
    match pair.find("=") {
      Some(index) => {
        let name = pair[:index].trim().to_owned()
        if name != "" {
          cookies.set(name, pair[index + 1:].to_owned())
        }
      }
      None => ()
    }
  }
  cookies
}

///|
pub fn Context::cookie(self : Context, name : String) -> String? {
  self.cookies().get(name)
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
  self.response.cookies.push(
    @http.Cookie(
      name,
      value,
      path?,
      max_age?,
      domain?,
      http_only~,
      secure~,
      extensions=match same_site {
        Some(value) => ["SameSite=" + value]
        None => []
      },
    ),
  )
}

///|
fn render_cookie(cookie : @http.Cookie) -> String {
  let builder = StringBuilder(size_hint=cookie.name.length() + 32)
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
  let cookie = @http.Cookie(
    name,
    value,
    path?,
    max_age?,
    domain?,
    http_only~,
    secure~,
    extensions=match same_site {
      Some(value) => ["SameSite=" + value]
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
) -> Unit {
  self.set_cookie(name, "", path?, max_age=0L)
}

///|
pub fn Context::bearer_token(self : Context) -> String? {
  let authorization = self.header("Authorization")
  let view = authorization.view()
  if starts_with_ignore_ascii_case(view, "Bearer ".view()) {
    Some(view[7:].trim().to_owned())
  } else {
    None
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
fn is_ascii_view(view : StringView) -> Bool {
  let length = view.length()
  let mut i = 0
  while i < length {
    if view.unsafe_get(i).to_int() > 127 {
      return false
    }
    i = i + 1
  }
  true
}

///|
fn decode_url_impl(source : StringView, plus_as_space : Bool) -> String {
  let length = source.length()
  let mut needs_decoding = false
  let mut ascii_only = true
  let mut high_byte = false
  let mut i = 0
  while i < length {
    let value = source.unsafe_get(i).to_int()
    if value > 127 {
      ascii_only = false
    } else if value == 37 {
      needs_decoding = true
      if i + 2 < length {
        let high = hex_digit(source.unsafe_get(i + 1).to_int())
        let low = hex_digit(source.unsafe_get(i + 2).to_int())
        if high >= 8 && low >= 0 {
          high_byte = true
        }
      }
    } else if value == 43 && plus_as_space {
      needs_decoding = true
    }
    i = i + 1
  }
  if !needs_decoding {
    return source.to_owned()
  }
  if ascii_only && !high_byte {
    let builder = StringBuilder(size_hint=length)
    let mut i = 0
    while i < length {
      let value = source.unsafe_get(i).to_int()
      if value == 37 {
        if i + 2 < length {
          let high = hex_digit(source.unsafe_get(i + 1).to_int())
          let low = hex_digit(source.unsafe_get(i + 2).to_int())
          if high >= 0 && low >= 0 {
            builder.write_char((high * 16 + low).unsafe_to_char())
            i = i + 3
            continue
          }
        }
        builder.write_char('%')
        i = i + 1
      } else if value == 43 && plus_as_space {
        builder.write_char(' ')
        i = i + 1
      } else {
        let run_start = i
        i = i + 1
        while i < length {
          let next = source.unsafe_get(i).to_int()
          if next == 37 || (next == 43 && plus_as_space) {
            break
          }
          i = i + 1
        }
        builder.write_stringview(source[run_start:i])
      }
    }
    return builder.to_string()
  }
  let bytes = @utf8.encode(source)
  let buffer = @buffer.Buffer::Buffer(size_hint=bytes.length())
  let mut i = 0
  while i < bytes.length() {
    let byte = bytes[i]
    if byte == b'%' && i + 2 < bytes.length() {
      let high = hex_digit(bytes[i + 1].to_int())
      let low = hex_digit(bytes[i + 2].to_int())
      if high >= 0 && low >= 0 {
        buffer.write_byte((high * 16 + low).to_byte())
        i = i + 2
      } else {
        buffer.write_byte(byte)
      }
    } else if byte == b'+' && plus_as_space {
      buffer.write_byte(b' ')
    } else {
      buffer.write_byte(byte)
    }
    i = i + 1
  }
  @utf8.decode_lossy(buffer.to_bytes())
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
pub fn url_encode(source : String) -> String {
  let hex = "0123456789ABCDEF"
  let view = source.view()
  let length = view.length()
  let mut start = 0
  while start < length && is_url_unreserved(view.unsafe_get(start).to_int()) {
    start = start + 1
  }
  if start == length {
    return source
  }
  if is_ascii_view(view) {
    let builder = StringBuilder(size_hint=length)
    builder.write_stringview(view[:start])
    let mut i = start
    while i < length {
      let value = view.unsafe_get(i).to_int()
      if is_url_unreserved(value) {
        builder.write_char(value.unsafe_to_char())
      } else {
        builder.write_char('%')
        builder.write_char(hex[value / 16].unsafe_to_char())
        builder.write_char(hex[value % 16].unsafe_to_char())
      }
      i = i + 1
    }
    return builder.to_string()
  }
  let bytes = @utf8.encode(source)
  let builder = StringBuilder(size_hint=bytes.length())
  for byte in bytes {
    let value = byte.to_int()
    if is_url_unreserved(value) {
      builder.write_char(value.unsafe_to_char())
    } else {
      builder.write_char('%')
      builder.write_char(hex[value / 16].unsafe_to_char())
      builder.write_char(hex[value % 16].unsafe_to_char())
    }
  }
  builder.to_string()
}

///|
fn has_ascii_upper(view : StringView) -> Bool {
  let length = view.length()
  let mut i = 0
  while i < length {
    let value = view.unsafe_get(i).to_int()
    if value >= 65 && value <= 90 {
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
    let mut left = view.unsafe_get(i).to_int()
    let mut right = prefix.unsafe_get(i).to_int()
    if left >= 65 && left <= 90 {
      left = left + 32
    }
    if right >= 65 && right <= 90 {
      right = right + 32
    }
    if left != right {
      return false
    }
    i = i + 1
  }
  true
}

///|
fn mime_for_extension(extension : StringView) -> String {
  if extension == "html" || extension == "htm" {
    "text/html; charset=utf-8"
  } else if extension == "css" {
    "text/css; charset=utf-8"
  } else if extension == "js" || extension == "mjs" {
    "text/javascript; charset=utf-8"
  } else if extension == "json" || extension == "map" {
    "application/json; charset=utf-8"
  } else if extension == "webmanifest" {
    "application/manifest+json; charset=utf-8"
  } else if extension == "yaml" || extension == "yml" {
    "application/yaml; charset=utf-8"
  } else if extension == "toml" {
    "application/toml; charset=utf-8"
  } else if extension == "txt" || extension == "text" || extension == "log" {
    "text/plain; charset=utf-8"
  } else if extension == "md" || extension == "markdown" {
    "text/markdown; charset=utf-8"
  } else if extension == "csv" {
    "text/csv; charset=utf-8"
  } else if extension == "xml" {
    "application/xml"
  } else if extension == "svg" {
    "image/svg+xml"
  } else if extension == "png" {
    "image/png"
  } else if extension == "jpg" || extension == "jpeg" {
    "image/jpeg"
  } else if extension == "gif" {
    "image/gif"
  } else if extension == "webp" {
    "image/webp"
  } else if extension == "avif" {
    "image/avif"
  } else if extension == "bmp" {
    "image/bmp"
  } else if extension == "ico" {
    "image/x-icon"
  } else if extension == "wasm" {
    "application/wasm"
  } else if extension == "pdf" {
    "application/pdf"
  } else if extension == "zip" {
    "application/zip"
  } else if extension == "gz" {
    "application/gzip"
  } else if extension == "mp3" {
    "audio/mpeg"
  } else if extension == "wav" {
    "audio/wav"
  } else if extension == "ogg" {
    "audio/ogg"
  } else if extension == "mp4" {
    "video/mp4"
  } else if extension == "webm" {
    "video/webm"
  } else if extension == "mov" {
    "video/quicktime"
  } else if extension == "woff" {
    "font/woff"
  } else if extension == "woff2" {
    "font/woff2"
  } else if extension == "ttf" {
    "font/ttf"
  } else if extension == "otf" {
    "font/otf"
  } else {
    "application/octet-stream"
  }
}

///|
pub fn mime_type_for(path : String) -> String {
  let view = path.view()
  let last_slash = match view.rev_find("/") {
    Some(index) => index
    None => -1
  }
  match view.rev_find(".") {
    Some(index) =>
      if index > last_slash {
        let extension = view[index + 1:]
        if has_ascii_upper(extension) {
          mime_for_extension(extension.to_lower().view())
        } else {
          mime_for_extension(extension)
        }
      } else {
        mime_for_extension("")
      }
    None => mime_for_extension("")
  }
}

///|
fn parse_urlencoded_view(source : StringView) -> Map[String, String] {
  let result : Map[String, String] = Map([], capacity=4)
  for pair in source.split("&") {
    if pair.is_empty() {
      continue
    }
    match pair.find("=") {
      Some(index) => {
        let key = decode_url(pair[:index])
        let value = decode_url(pair[index + 1:])
        result.set(key, value)
      }
      None => result.set(decode_url(pair), "")
    }
  }
  result
}

///|
pub fn parse_urlencoded(source : String) -> Map[String, String] {
  parse_urlencoded_view(source)
}

///|
fn encoded_key_matches(key : StringView, name : String) -> Bool {
  if key == name.view() {
    return true
  }
  if !key.contains("%") && !key.contains("+") {
    return false
  }
  decode_url(key) == name
}

///|
fn query_param(source : StringView, name : String) -> String {
  let mut found : StringView? = None
  for pair in source.split("&") {
    if pair.is_empty() {
      continue
    }
    match pair.find("=") {
      Some(index) =>
        if encoded_key_matches(pair[:index], name) {
          found = Some(pair[index + 1:])
        }
      None => if encoded_key_matches(pair, name) { found = Some("") }
    }
  }
  match found {
    Some(value) => decode_url(value)
    None => ""
  }
}

///|
pub fn Context::query(self : Context, name : String) -> String {
  let path = self.request.path
  match path.find("?") {
    Some(index) => query_param(path[index + 1:], name)
    None => ""
  }
}

///|
pub fn Context::form(self : Context, name : String) -> String {
  let content_type = self.header("Content-Type")
  if !starts_with_ignore_ascii_case(
    content_type.view(),
    "application/x-www-form-urlencoded".view(),
  ) {
    return ""
  }
  query_param(self.request.body.view(), name)
}

///|
pub fn Context::queries(self : Context) -> Map[String, String] {
  match self.request.path.find("?") {
    Some(index) => parse_urlencoded_view(self.request.path[index + 1:])
    None => Map([], capacity=0)
  }
}

///|
pub fn Context::query_values(self : Context, name : String) -> Array[String] {
  let values : Array[String] = []
  match self.request.path.find("?") {
    Some(index) => {
      let source = self.request.path[index + 1:]
      for pair in source.view().split("&") {
        if pair.is_empty() {
          continue
        }
        match pair.find("=") {
          Some(split) =>
            if encoded_key_matches(pair[:split], name) {
              values.push(decode_url(pair[split + 1:]))
            }
          None => if encoded_key_matches(pair, name) { values.push("") }
        }
      }
    }
    None => ()
  }
  values
}

///|
pub fn Context::form_map(self : Context) -> Map[String, String] {
  let content_type = self.header("Content-Type")
  if !starts_with_ignore_ascii_case(
    content_type.view(),
    "application/x-www-form-urlencoded".view(),
  ) {
    return Map([], capacity=0)
  }
  parse_urlencoded_view(self.request.body.view())
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
    let lower_value = if value >= 65 && value <= 90 {
      value + 32
    } else {
      value
    }
    if lower_value == lower_first &&
      starts_with_ignore_ascii_case(haystack[i:], needle) {
      return Some(i)
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
  let mut start = 0
  let mut result : String? = None
  let mut done = false
  while !done {
    let index = match find_view_ignore_ascii_case(value, name.view(), start) {
      Some(index) => index
      None => {
        done = true
        continue
      }
    }
    let after = index + name.length()
    let at_boundary = index == 0 ||
      is_parameter_boundary(value.unsafe_get(index - 1))
    if at_boundary &&
      after < value.length() &&
      value.unsafe_get(after) == ('=' : UInt16) {
      let mut pos = after + 1
      while pos < value.length() && value.unsafe_get(pos) == (' ' : UInt16) {
        pos = pos + 1
      }
      if pos < value.length() && value.unsafe_get(pos) == ('"' : UInt16) {
        let quoted_start = pos + 1
        let end = match value[quoted_start:].find("\"") {
          Some(offset) => quoted_start + offset
          None => value.length()
        }
        result = Some(value[quoted_start:end].to_owned())
      } else {
        let end = match value[pos:].find(";") {
          Some(offset) => pos + offset
          None => value.length()
        }
        result = Some(value[pos:end].trim().to_owned())
      }
      done = true
    } else {
      start = index + 1
    }
  }
  result
}

///|
pub fn multipart_boundary(content_type : String) -> String? {
  match find_view_ignore_ascii_case(
    content_type.view(),
    "multipart/form-data".view(),
    0,
  ) {
    None => None
    Some(_) => header_parameter(content_type.view(), "boundary")
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
  for key, value in headers {
    if key.view().equal_ignore_ascii_case(target) {
      return Some(value)
    }
  }
  None
}

///|
fn parse_part_headers(header_text : StringView) -> Map[String, String] {
  let headers : Map[String, String] = Map([], capacity=4)
  for line in header_text.split("\n") {
    let line = if line.has_suffix("\r") {
      line[:line.length() - 1]
    } else {
      line
    }
    if line.is_empty() {
      continue
    }
    match line.find(":") {
      Some(index) => {
        let name = line[:index].trim().to_owned()
        let value = line[index + 1:].trim().to_owned()
        if name != "" {
          headers.set(name, value)
        }
      }
      None => ()
    }
  }
  headers
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
  let crlf_delimiter = "\r\n" + delimiter
  let view = body.view()
  let mut pos = match find_view_from(view, delimiter_view, 0) {
    Some(index) => index + delimiter.length()
    None => return Some([])
  }
  let parts : Array[MultipartPart] = []
  while pos <= view.length() {
    if starts_with_ignore_ascii_case(view[pos:], "--".view()) {
      break
    }
    if view[pos:].has_prefix("\r\n") {
      pos = pos + 2
    } else if view[pos:].has_prefix("\n") {
      pos = pos + 1
    }
    let data_end = match find_view_from(view, crlf_delimiter.view(), pos) {
      Some(index) => index
      None =>
        match find_view_from(view, ("\n" + delimiter).view(), pos) {
          Some(index) => index
          None => break
        }
    }
    let header_end = match find_view_from(view, "\r\n\r\n".view(), pos) {
      Some(index) => index
      None =>
        match find_view_from(view, "\n\n".view(), pos) {
          Some(index) => index
          None => break
        }
    }
    if header_end >= data_end {
      break
    }
    let separator_length = if view[header_end:header_end + 2] == "\r\n" {
      4
    } else {
      2
    }
    if header_end + separator_length > data_end {
      break
    }
    let headers = parse_part_headers(view[pos:header_end])
    let data = view[header_end + separator_length:data_end]
    let disposition = get_header_ignore_case(headers, "Content-Disposition")
    let name = match disposition {
      Some(disposition) => header_parameter(disposition.view(), "name").unwrap_or("")
      None => ""
    }
    let filename = match disposition {
      Some(disposition) =>
        header_parameter(disposition.view(), "filename").unwrap_or("")
      None => ""
    }
    let part_content_type = get_header_ignore_case(headers, "Content-Type").unwrap_or("")
    parts.push({
      name,
      filename,
      content_type: part_content_type,
      headers,
      data: data.to_owned(),
    })
    pos = data_end
    if view[pos:].has_prefix("\r\n") {
      pos = pos + 2
    } else if view[pos:].has_prefix("\n") {
      pos = pos + 1
    }
    pos = pos + delimiter.length()
  }
  Some(parts)
}

///|
pub fn Context::multipart(self : Context) -> Array[MultipartPart] {
  let content_type = self.header("Content-Type")
  if !starts_with_ignore_ascii_case(
    content_type.view(),
    "multipart/form-data".view(),
  ) {
    return []
  }
  match parse_multipart(self.request.body, content_type) {
    Some(parts) => parts
    None => []
  }
}

///|
pub fn Context::multipart_value(self : Context, name : String) -> String {
  for part in self.multipart() {
    if part.filename == "" && part.name == name {
      return part.data
    }
  }
  ""
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
    200 => "OK"
    201 => "Created"
    202 => "Accepted"
    204 => "No Content"
    206 => "Partial Content"
    301 => "Moved Permanently"
    302 => "Found"
    303 => "See Other"
    304 => "Not Modified"
    307 => "Temporary Redirect"
    308 => "Permanent Redirect"
    400 => "Bad Request"
    401 => "Unauthorized"
    403 => "Forbidden"
    404 => "Not Found"
    405 => "Method Not Allowed"
    406 => "Not Acceptable"
    408 => "Request Timeout"
    409 => "Conflict"
    410 => "Gone"
    411 => "Length Required"
    412 => "Precondition Failed"
    413 => "Payload Too Large"
    415 => "Unsupported Media Type"
    416 => "Range Not Satisfiable"
    422 => "Unprocessable Entity"
    429 => "Too Many Requests"
    500 => "Internal Server Error"
    501 => "Not Implemented"
    502 => "Bad Gateway"
    503 => "Service Unavailable"
    504 => "Gateway Timeout"
    _ => "Unknown"
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
fn write_two_digits(builder : StringBuilder, value : Int) -> Unit {
  if value < 10 {
    builder.write_char('0')
  }
  builder.write_string(value.to_string())
}

///|
pub fn format_http_date(unix_seconds : Int64) -> String {
  let days = unix_seconds / 86400L
  let time_of_day = unix_seconds - days * 86400L
  let (year, month, day) = civil_from_days(days)
  let weekday = ((days + 4L) % 7L + 7L) % 7L
  let hour = (time_of_day / 3600L).to_int()
  let minute = ((time_of_day % 3600L) / 60L).to_int()
  let second = (time_of_day % 60L).to_int()
  let weekdays = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
  let months = [
    "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov",
    "Dec",
  ]
  let builder = StringBuilder(size_hint=29)
  builder.write_string(weekdays[weekday.to_int()])
  builder.write_string(", ")
  write_two_digits(builder, day)
  builder.write_char(' ')
  builder.write_string(months[month - 1])
  builder.write_char(' ')
  builder.write_string(year.to_string())
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
  let months = [
    "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov",
    "Dec",
  ]
  for i, month in months {
    if name == month.view() {
      return Some(i + 1)
    }
  }
  None
}

///|
pub fn parse_http_date(value : String) -> Int64? {
  let parts : Array[StringView] = []
  for part in value.view().split(" ") {
    if !part.is_empty() {
      parts.push(part)
    }
  }
  if parts.length() < 5 {
    return None
  }
  let day = match parse_decimal(parts[1]) {
    Some(day) => day
    None => return None
  }
  let month = match month_from_name(parts[2]) {
    Some(month) => month
    None => return None
  }
  let year = match parse_decimal(parts[3]) {
    Some(year) => year.to_int64()
    None => return None
  }
  let time = parts[4]
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
  if day < 1 ||
    day > 31 ||
    year < 1970 ||
    hour > 23 ||
    minute > 59 ||
    second > 60 {
    return None
  }
  let seconds = days_from_civil(year, month, day) * 86400L +
    (hour * 3600 + minute * 60 + second).to_int64()
  Some(seconds)
}

///|
pub(all) enum ByteRange {
  ByteRangeFull
  ByteRangeSpec(Int64, Int64)
  ByteRangeInvalid
}

///|
fn etag_header_matches(value : StringView, etag : String) -> Bool {
  for token in value.split(",") {
    let token = token.trim()
    if token == "*" || token == etag.view() {
      return true
    }
    if token.has_prefix("W/") && token[2:] == etag.view() {
      return true
    }
  }
  false
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
pub fn parse_byte_range(value : String, total : Int64) -> ByteRange {
  let view = value.view().trim()
  if !starts_with_ignore_ascii_case(view, "bytes=".view()) {
    return ByteRangeFull
  }
  let spec = view[6:].trim()
  if spec.contains(",") {
    return ByteRangeFull
  }
  let dash = match spec.find("-") {
    Some(index) => index
    None => return ByteRangeFull
  }
  let start_text = spec[:dash].trim()
  let end_text = spec[dash + 1:].trim()
  if start_text.is_empty() {
    let suffix = match parse_decimal(end_text) {
      Some(suffix) => suffix.to_int64()
      None => return ByteRangeFull
    }
    if suffix <= 0 || total <= 0L {
      return ByteRangeInvalid
    }
    let start = if suffix >= total { 0L } else { total - suffix }
    return ByteRangeSpec(start, total - 1L)
  }
  let start = match parse_decimal(start_text) {
    Some(start) => start.to_int64()
    None => return ByteRangeFull
  }
  if end_text.is_empty() {
    if start >= total {
      return ByteRangeInvalid
    }
    return ByteRangeSpec(start, total - 1L)
  }
  let end = match parse_decimal(end_text) {
    Some(end) => end.to_int64()
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
}

///|
pub fn App::new() -> App {
  {
    router: create_router(),
    middlewares: [],
    max_body_size: DEFAULT_MAX_BODY_SIZE,
    timeout: 0,
    chain: None,
    static_mounts: [],
    no_route_handler: None,
    ws_router: create_router(),
    ws_handlers: Map([]),
  }
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
  self.ws_router.route("GET", path) is RouteFound(_)
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
pub fn App::static_files(
  self : App,
  url_prefix : String,
  root : String,
  index~ : String = "index.html",
  max_age~ : Int32 = 0,
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
  })
  self
}

///|
pub fn App::has_route(self : App, meth : String, path : String) -> Bool {
  match self.router.route(meth, path) {
    RouteFound(_) => true
    _ => false
  }
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
pub fn App::static_file_for(self : App, path : String) -> String? {
  let path_view = clean_path_view(path)
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
      if clean.is_empty() || decoded.has_suffix("/") {
        Some(join_fs_path(join_fs_path(mount.root, clean), mount.index))
      } else {
        Some(join_fs_path(mount.root, clean))
      }
    }
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
  match self.chain {
    Some(chain) => chain(ctx)
    None => {
      let router = self.router
      let terminal : Handler = fn(ctx) raise {
        router.dispatch_with(ctx, self.no_route_handler)
      }
      let chain = apply_middleware(self.middlewares, terminal)
      self.chain = Some(chain)
      chain(ctx)
    }
  }
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
pub fn middleware_recover() -> Middleware {
  fn(next) {
    fn(ctx) {
      next(ctx) catch {
        HttpError(status, message) => error_response(ctx, status, message)
        HttpErrorPayload(status, message, payload) =>
          error_response_with_payload(ctx, status, message, payload)
        err => internal_error(ctx, "\{err}")
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
pub fn middleware_secure_headers(
  content_type_options~ : String = "nosniff",
  frame_options~ : String = "DENY",
  referrer_policy~ : String = "no-referrer",
) -> Middleware {
  fn(next) {
    fn(ctx) raise {
      ctx.response.headers.set("X-Content-Type-Options", content_type_options)
      ctx.response.headers.set("X-Frame-Options", frame_options)
      ctx.response.headers.set("Referrer-Policy", referrer_policy)
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
      ctx.response.headers.set("Access-Control-Allow-Origin", allow_origin)
      if allow_credentials {
        ctx.response.headers.set("Access-Control-Allow-Credentials", "true")
      }
      if allow_origin != "*" {
        ctx.response.headers.set("Vary", "Origin")
      }
      if ctx.request.method == "OPTIONS" {
        ctx.response.status = 204
        ctx.response.data = None
        ctx.response.body = ""
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
pub(all) struct Feather {
  config : Config
  app : App
}

///|
pub fn create_feather(config : Config) -> Feather {
  {
    config,
    app: {
      router: create_router(),
      middlewares: [],
      max_body_size: DEFAULT_MAX_BODY_SIZE,
      timeout: config.timeout,
      chain: None,
      static_mounts: [],
      no_route_handler: None,
      ws_router: create_router(),
      ws_handlers: Map([]),
    },
  }
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
) -> Feather {
  ignore(self.app.static_files(url_prefix, root, index~, max_age~))
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
