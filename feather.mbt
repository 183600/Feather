///|
pub const DEFAULT_MAX_BODY_SIZE : Int32 = 1000

///|
pub const PARAM_PREFIX : String = "param:"

///|
pub(all) suberror HttpError {
  HttpError(Int32, String)
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
    response: { status: 200, headers: Map([], capacity=4), body: "", },
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
pub fn Router::url_for(
  self : Router,
  name : String,
  params? : Map[String, String],
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
  if i >= length {
    return Some("/")
  }
  let builder = StringBuilder(size_hint=length)
  while i < length {
    builder.write_char('/')
    let end = segment_end(path, i)
    let segment = path[i:end]
    if segment.has_prefix(":") {
      match values.get_from_string(segment[1:]) {
        Some(value) => builder.write_string(url_encode(value))
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
  allowed
}

///|
fn Router::match_in_tree(
  self : Router,
  tree_key : String,
  method_key : String,
  clean_path : StringView,
) -> RouteOutcome? {
  let root = match self.trees.get(tree_key) {
    Some(root) => root
    None => return None
  }
  if !root.has_dynamic {
    match match_static_node(root, clean_path, 0) {
      Some(node) =>
        Some(
          found_route(
            node.route_path,
            method_key,
            Map([], capacity=0),
            "",
            "",
            node.handler,
          ),
        )
      None => None
    }
  } else {
    match match_dynamic_node(root, clean_path, 0) {
      Some(outcome) => {
        let node = outcome.node
        let (params, wildcard_value) = if outcome.wildcard_start < 0 &&
          node.param_names.length() == 0 {
          (Map([], capacity=0), "")
        } else {
          extract_route_params(node, clean_path)
        }
        Some(
          found_route(
            node.route_path,
            method_key,
            params,
            wildcard_value,
            node.route_wildcard_name,
            node.handler,
          ),
        )
      }
      None => None
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
  let method_key = meth
  match self.match_in_tree(method_key, method_key, clean_path) {
    Some(outcome) => outcome
    None =>
      if method_key == "HEAD" {
        match self.match_in_tree("GET", method_key, clean_path) {
          Some(outcome) => outcome
          None => self.dispatch_miss(clean_path)
        }
      } else {
        self.dispatch_miss(clean_path)
      }
  }
}

///|
fn found_route(
  route_path : String,
  method_key : String,
  params : Map[String, String],
  wildcard : String,
  wildcard_name : String,
  handler : Handler?,
) -> RouteOutcome {
  RouteFound({
    path: route_path,
    method: method_key,
    params,
    wildcard,
    wildcard_name,
    handler,
  })
}

///|
fn Router::dispatch_miss(self : Router, path : StringView) -> RouteOutcome {
  let allowed = self.allowed_methods(path)
  if allowed.length() > 0 {
    RouteMethodNotAllowed(allowed)
  } else {
    RouteNotFound
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
  match self.route(ctx.request.method, ctx.request.path) {
    RouteFound(route) => {
      for name, value in route.params {
        ctx.state.set(PARAM_PREFIX + name, value)
      }
      match route.handler {
        Some(handler) => handler(ctx)
        None => not_found(ctx)
      }
    }
    RouteMethodNotAllowed(methods) => method_not_allowed(ctx, methods)
    RouteNotFound =>
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
  ctx.response.body = "404 Not Found"
}

///|
pub fn method_not_allowed(ctx : Context, allowed : Array[String]) -> Unit {
  ctx.response.status = 405
  ctx.response.headers.set("Allow", allowed.join(", "))
  ctx.response.headers.set("Content-Type", "text/plain; charset=utf-8")
  ctx.response.body = "405 Method Not Allowed"
}

///|
pub fn internal_error(ctx : Context, detail : String) -> Unit {
  ctx.state.set("error", detail)
  ctx.response.status = 500
  ctx.response.headers.set("Content-Type", "text/plain; charset=utf-8")
  ctx.response.body = "Internal Server Error"
}

///|
pub fn error_response(ctx : Context, status : Int32, message : String) -> Unit {
  let payload : Map[String, Json] = Map([], capacity=2)
  payload.set("status", Json::number(status.to_double()))
  payload.set("error", Json::string(message))
  ctx.response.status = status
  ctx.response.headers.set("Content-Type", "application/json; charset=utf-8")
  ctx.response.body = Json::object(payload).stringify()
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
  self.response.body = body
}

///|
pub fn Context::html(self : Context, status : Int32, body : String) -> Unit {
  self.response.status = status
  self.response.headers.set("Content-Type", "text/html; charset=utf-8")
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
pub fn Context::redirect(
  self : Context,
  status : Int32,
  location : String,
) -> Unit {
  self.response.status = status
  self.response.headers.set("Location", location)
  self.response.body = ""
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
fn decode_url(source : StringView) -> String {
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
    } else if value == 43 {
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
      } else if value == 43 {
        builder.write_char(' ')
      } else {
        builder.write_char(value.unsafe_to_char())
      }
      i = i + 1
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
    } else if byte == b'+' {
      buffer.write_byte(b' ')
    } else {
      buffer.write_byte(byte)
    }
    i = i + 1
  }
  @utf8.decode_lossy(buffer.to_bytes())
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
  if is_ascii_view(view) {
    let length = view.length()
    let builder = StringBuilder(size_hint=length)
    let mut i = 0
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
  } else if extension == "json" {
    "application/json; charset=utf-8"
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
  } else if extension == "mp4" {
    "video/mp4"
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
  if !key.contains("%") && !key.contains("+") {
    key == name.view()
  } else {
    decode_url(key) == name
  }
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
    413 => "Payload Too Large"
    415 => "Unsupported Media Type"
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
fn normalize_prefix(prefix : String) -> String {
  let view = prefix.view()
  let length = view.length()
  let mut end = length
  while end > 1 && view[end - 1:].has_prefix("/") {
    end = end - 1
  }
  if end == 1 && view.has_prefix("/") {
    return ""
  }
  let trimmed = if end == length { view } else { view[:end] }
  if trimmed.has_prefix("/") {
    if end == length {
      return prefix
    }
    return trimmed.to_owned()
  }
  if end == 0 {
    return ""
  }
  "/" + trimmed.to_owned()
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
) -> String? {
  self.router.url_for(name, params?)
}

///|
pub(all) struct StaticMount {
  url_prefix : String
  root : String
  index : String
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
) -> String? {
  self.router.url_for(name, params?)
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
) -> App {
  let mut clean_root = root
  while clean_root.length() > 1 && clean_root.has_suffix("/") {
    clean_root = clean_root[:clean_root.length() - 1].to_owned()
  }
  self.static_mounts.push({
    url_prefix: normalize_prefix(url_prefix),
    root: clean_root,
    index,
  })
  self
}

///|
pub fn App::static_file_for(self : App, path : String) -> String? {
  if self.static_mounts.length() == 0 {
    return None
  }
  let path_view = clean_path_view(path)
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
  match best {
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
      let clean = match clean_relative_path(relative) {
        Some(clean) => clean
        None => return None
      }
      if clean.is_empty() || relative.has_suffix("/") {
        Some(join_fs_path(join_fs_path(mount.root, clean), mount.index))
      } else {
        Some(join_fs_path(mount.root, clean))
      }
    }
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
        err => error_response(ctx, 500, "\{err}")
      }
    }
  }
}

///|
pub fn middleware_logger(log~ : (String) -> Unit = println) -> Middleware {
  fn(next) {
    fn(ctx) raise {
      next(ctx)
      log("[\{ctx.response.status}] \{ctx.request.method} \{ctx.request.path}")
    }
  }
}

///|
pub fn middleware_cors(allow_origin~ : String = "*") -> Middleware {
  fn(next) {
    fn(ctx) raise {
      ctx.response.headers.set("Access-Control-Allow-Origin", allow_origin)
      if ctx.request.method == "OPTIONS" {
        ctx.response.status = 204
        ctx.response.headers.set(
          "Access-Control-Allow-Methods", "GET, POST, PUT, PATCH, DELETE, HEAD, OPTIONS",
        )
        ctx.response.headers.set("Access-Control-Allow-Headers", "*")
      } else {
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
) -> String? {
  self.app.url_for(name, params?)
}

///|
pub fn Feather::static_files(
  self : Feather,
  url_prefix : String,
  root : String,
  index~ : String = "index.html",
) -> Feather {
  ignore(self.app.static_files(url_prefix, root, index~))
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
