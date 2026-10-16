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
  static_children : Map[String, RouteNode]
  mut param_child : RouteNode?
  mut param_name : String
  mut wildcard_child : RouteNode?
  mut wildcard_name : String
  mut has_dynamic : Bool
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
    static_children: Map([], capacity=2),
    param_child: None,
    param_name: "",
    wildcard_child: None,
    wildcard_name: "",
    has_dynamic: false,
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
fn join_segments(segments : Array[StringView], start : Int32) -> String {
  let builder = StringBuilder()
  for i = start; i < segments.length(); i = i + 1 {
    if i > start {
      builder.write_string("/")
    }
    builder.write_stringview(segments[i])
  }
  builder.to_string()
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
priv struct RouteParams {
  params : Map[String, String]
  wildcard_name : String
  wildcard_value : String
}

///|
fn extract_route_params(
  route_path : StringView,
  segments : Array[StringView],
) -> RouteParams {
  let params : Map[String, String] = Map([], capacity=4)
  let mut wildcard_name = ""
  let mut wildcard_value = ""
  let mut index = 0
  for pattern in split_segments(route_path) {
    if pattern.has_prefix(":") {
      if index < segments.length() {
        params.set(pattern[1:].to_owned(), segments[index].to_owned())
      }
      index = index + 1
    } else if pattern.has_prefix("*") {
      wildcard_name = pattern[1:].to_owned()
      wildcard_value = join_segments(segments, index)
      if wildcard_name != "" {
        params.set(wildcard_name, wildcard_value)
      }
      index = segments.length()
    } else {
      index = index + 1
    }
  }
  { params, wildcard_name, wildcard_value, }
}

///|
fn match_node(
  node : RouteNode,
  segments : Array[StringView],
  index : Int32,
) -> RouteNode? {
  if index == segments.length() {
    if node.handler is Some(_) {
      return Some(node)
    }
    return node.wildcard_child
  }
  let segment = segments[index]
  match node.static_children.get_from_string(segment) {
    Some(child) =>
      match match_node(child, segments, index + 1) {
        Some(result) => return Some(result)
        None => ()
      }
    None => ()
  }
  match node.param_child {
    Some(child) =>
      match match_node(child, segments, index + 1) {
        Some(result) => return Some(result)
        None => ()
      }
    None => ()
  }
  node.wildcard_child
}

///|
fn match_static_node(
  node : RouteNode,
  segments : Array[StringView],
  index : Int32,
) -> RouteNode? {
  if index == segments.length() {
    if node.handler is Some(_) {
      return Some(node)
    }
    return None
  }
  match node.static_children.get_from_string(segments[index]) {
    Some(child) => match_static_node(child, segments, index + 1)
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
  let ancestors : Array[RouteNode] = [node]
  for segment in split_segments(clean_path) {
    if segment.has_prefix(":") {
      let child = match node.param_child {
        Some(child) => child
        None => {
          let child = RouteNode::new()
          node.param_child = Some(child)
          child
        }
      }
      node.param_name = segment[1:].to_owned()
      for ancestor in ancestors {
        ancestor.has_dynamic = true
      }
      node = child
    } else if segment.has_prefix("*") {
      let child = match node.wildcard_child {
        Some(child) => child
        None => {
          let child = RouteNode::new()
          node.wildcard_child = Some(child)
          child
        }
      }
      node.wildcard_name = segment[1:].to_owned()
      for ancestor in ancestors {
        ancestor.has_dynamic = true
      }
      node = child
      break
    } else {
      let key = segment.to_owned()
      let child = match node.static_children.get(key) {
        Some(child) => child
        None => {
          let child = RouteNode::new()
          node.static_children.set(key, child)
          child
        }
      }
      node = child
    }
    ancestors.push(node)
  }
  node.handler = Some(handler)
  node.route_path = clean_path
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
  let segments = split_segments(named.path.view())
  if segments.length() == 0 {
    return Some("/")
  }
  let builder = StringBuilder()
  for i = 0; i < segments.length(); i = i + 1 {
    builder.write_string("/")
    let segment = segments[i]
    if segment.has_prefix(":") {
      match values.get(segment[1:].to_owned()) {
        Some(value) => builder.write_string(url_encode(value))
        None => return None
      }
    } else if segment.has_prefix("*") {
      match values.get(segment[1:].to_owned()) {
        Some(value) => builder.write_string(value)
        None => return None
      }
    } else {
      builder.write_stringview(segment)
    }
  }
  Some(builder.to_string())
}

///|
fn Router::allowed_methods(self : Router, path : StringView) -> Array[String] {
  let allowed : Array[String] = []
  let segments = split_segments(path)
  for meth, root in self.trees {
    let matched = if root.has_dynamic {
      match_node(root, segments, 0) is Some(_)
    } else {
      match_static_node(root, segments, 0) is Some(_)
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
  let segments = split_segments(clean_path)
  if !root.has_dynamic {
    match match_static_node(root, segments, 0) {
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
    match match_node(root, segments, 0) {
      Some(node) => {
        let info = extract_route_params(node.route_path.view(), segments)
        Some(
          found_route(
            node.route_path,
            method_key,
            info.params,
            info.wildcard_value,
            info.wildcard_name,
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
      let target = key.view().to_lower()
      for name, value in self.request.headers {
        if name.view().to_lower() == target {
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
fn hex_digit(byte : Byte) -> Int32 {
  let value = byte.to_int()
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
fn decode_url(source : StringView) -> String {
  if !source.contains("%") && !source.contains("+") {
    return source.to_owned()
  }
  let bytes = @utf8.encode(source)
  let buffer = @buffer.Buffer::Buffer(size_hint=bytes.length())
  let mut i = 0
  while i < bytes.length() {
    let byte = bytes[i]
    if byte == b'%' && i + 2 < bytes.length() {
      let high = hex_digit(bytes[i + 1])
      let low = hex_digit(bytes[i + 2])
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
fn url_encode_byte(byte : Byte, builder : StringBuilder) -> Unit {
  let value = byte.to_int()
  if is_url_unreserved(value) {
    builder.write_char(value.unsafe_to_char())
  } else {
    let hex = "0123456789ABCDEF"
    builder.write_char('%')
    builder.write_char(hex[value / 16].unsafe_to_char())
    builder.write_char(hex[value % 16].unsafe_to_char())
  }
}

///|
pub fn url_encode(source : String) -> String {
  let bytes = @utf8.encode(source)
  let builder = StringBuilder(size_hint=bytes.length())
  for byte in bytes {
    url_encode_byte(byte, builder)
  }
  builder.to_string()
}

///|
pub fn mime_type_for(path : String) -> String {
  let lower = path.view().to_lower()
  let extension = match lower.rev_find(".") {
    Some(index) => lower[index + 1:].to_owned()
    None => ""
  }
  match extension {
    "html" | "htm" => "text/html; charset=utf-8"
    "css" => "text/css; charset=utf-8"
    "js" | "mjs" => "text/javascript; charset=utf-8"
    "json" => "application/json; charset=utf-8"
    "txt" | "text" | "log" => "text/plain; charset=utf-8"
    "md" | "markdown" => "text/markdown; charset=utf-8"
    "csv" => "text/csv; charset=utf-8"
    "xml" => "application/xml"
    "svg" => "image/svg+xml"
    "png" => "image/png"
    "jpg" | "jpeg" => "image/jpeg"
    "gif" => "image/gif"
    "webp" => "image/webp"
    "bmp" => "image/bmp"
    "ico" => "image/x-icon"
    "wasm" => "application/wasm"
    "pdf" => "application/pdf"
    "zip" => "application/zip"
    "gz" => "application/gzip"
    "mp3" => "audio/mpeg"
    "mp4" => "video/mp4"
    "woff" => "font/woff"
    "woff2" => "font/woff2"
    "ttf" => "font/ttf"
    "otf" => "font/otf"
    _ => "application/octet-stream"
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
fn query_param(source : StringView, name : String) -> String {
  let mut found : String? = None
  for pair in source.split("&") {
    if pair.is_empty() {
      continue
    }
    match pair.find("=") {
      Some(index) =>
        if decode_url(pair[:index]) == name {
          found = Some(decode_url(pair[index + 1:]))
        }
      None => if decode_url(pair) == name { found = Some("") }
    }
  }
  match found {
    Some(value) => value
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
  if !content_type
    .view()
    .to_lower()
    .has_prefix("application/x-www-form-urlencoded") {
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
  let mut normalized = prefix
  while normalized.length() > 1 && normalized.has_suffix("/") {
    normalized = normalized[:normalized.length() - 1].to_owned()
  }
  if normalized == "/" {
    return ""
  }
  if !normalized.has_prefix("/") {
    return "/" + normalized
  }
  normalized
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
  root + "/" + relative
}

///|
fn clean_relative_path(relative : String) -> String? {
  if relative.contains("\u{0}") || relative.contains("\\") {
    return None
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
  let mut best : StaticMount? = None
  let mut best_length = -1
  for mount in self.static_mounts {
    let prefix = mount.url_prefix
    let matched = if prefix == "" {
      true
    } else {
      path == prefix || path.has_prefix(prefix + "/")
    }
    if matched && prefix.length() > best_length {
      best = Some(mount)
      best_length = prefix.length()
    }
  }
  match best {
    None => None
    Some(mount) => {
      let relative = if mount.url_prefix == "" {
        path
      } else if path == mount.url_prefix {
        ""
      } else {
        path[mount.url_prefix.length() + 1:].to_owned()
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
