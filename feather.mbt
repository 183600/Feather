pub const DEFAULT_MAX_BODY_SIZE : Int = 1000

pub const PARAM_PREFIX : String = "param:"

pub(all) struct Config {
  host : String
  port : Int
  timeout : Int
}

pub(all) struct Request {
  method : String
  path : String
  headers : Map[String, String]
  body : String
}

pub(all) struct Response {
  mut status : Int
  headers : Map[String, String]
  mut body : String
}

pub(all) struct Context {
  request : Request
  response : Response
  state : Map[String, String]
}

pub type Handler = (Context) -> Unit raise

pub type Middleware = (Handler) -> Handler

pub(all) struct Route {
  path : String
  method : String
  params : Map[String, String]
  wildcard : String
  wildcard_name : String
  handler : Handler?
}

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

pub(all) struct Router {
  routes : Array[Route]
  trees : Map[String, RouteNode]
}

pub(all) enum RouteOutcome {
  RouteFound(Route)
  RouteMethodNotAllowed(Array[String])
  RouteNotFound
}

pub fn create_server(config : Config) -> Config {
  config
}

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

pub fn create_router() -> Router {
  { routes: [], trees: Map([]) }
}

pub fn Context::new(request : Request) -> Context {
  {
    request,
    response: { status: 200, headers: Map([], capacity=4), body: "" },
    state: Map([], capacity=4),
  }
}

pub fn create_context() -> Context {
  Context::new({ method: "GET", path: "/", headers: Map([]), body: "" })
}

pub fn compose_middleware(handlers : Array[(Context) -> Unit]) -> Option[Handler] {
  Some(fn(ctx) {
    for handler in handlers {
      handler(ctx)
    }
  })
}

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

fn clean_path_view(path : String) -> StringView {
  match path.find("?") {
    Some(index) => path[:index]
    None => path.view()
  }
}

fn join_segments(segments : Array[StringView], start : Int) -> String {
  let builder = StringBuilder()
  for i = start; i < segments.length(); i = i + 1 {
    if i > start {
      builder.write_string("/")
    }
    builder.write_stringview(segments[i])
  }
  builder.to_string()
}

fn split_segments(path : StringView) -> Array[StringView] {
  let segments : Array[StringView] = Array(capacity=4)
  for segment in path.split("/") {
    if !(segment.is_empty()) {
      segments.push(segment)
    }
  }
  segments
}

priv struct MatchResult {
  route_path : String
  handler : Handler?
  wildcard_name : String
  wildcard_value : String
}

fn leaf_result(
  node : RouteNode,
  wildcard_name : String,
  wildcard_value : String,
) -> MatchResult {
  {
    route_path: node.route_path,
    handler: node.handler,
    wildcard_name,
    wildcard_value,
  }
}

fn match_node(
  node : RouteNode,
  segments : Array[StringView],
  index : Int,
  captures : Array[(String, String)],
) -> MatchResult? {
  if index == segments.length() {
    if node.handler is Some(_) {
      return Some(leaf_result(node, "", ""))
    }
    match node.wildcard_child {
      Some(child) =>
        return Some(leaf_result(child, node.wildcard_name, ""))
      None => return None
    }
  }
  let segment = segments[index]
  let mark = captures.length()
  match node.static_children.get_from_string(segment) {
    Some(child) =>
      match match_node(child, segments, index + 1, captures) {
        Some(result) => return Some(result)
        None => ()
      }
    None => ()
  }
  captures.truncate(mark)
  match node.param_child {
    Some(child) => {
      captures.push((node.param_name, segment.to_owned()))
      match match_node(child, segments, index + 1, captures) {
        Some(result) => return Some(result)
        None => ()
      }
    }
    None => ()
  }
  captures.truncate(mark)
  match node.wildcard_child {
    Some(child) =>
      return Some(leaf_result(child, node.wildcard_name, join_segments(segments, index)))
    None => return None
  }
}

fn match_static_node(
  node : RouteNode,
  segments : Array[StringView],
  index : Int,
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

pub fn Router::add_route(
  self : Router,
  meth : String,
  path : String,
  handler : Handler,
) -> Unit {
  let clean_path = match path.find("?") {
    Some(index) => path[:index].to_owned()
    None => path
  }
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

fn Router::allowed_methods(self : Router, path : StringView) -> Array[String] {
  let allowed : Array[String] = []
  let segments = split_segments(path)
  for meth, root in self.trees {
    let matched = if root.has_dynamic {
      let captures : Array[(String, String)] = []
      match_node(root, segments, 0, captures) is Some(_)
    } else {
      match_static_node(root, segments, 0) is Some(_)
    }
    if matched {
      allowed.push(meth)
    }
  }
  allowed
}

pub fn Router::route(
  self : Router,
  meth : String,
  path : String,
) -> RouteOutcome {
  let clean_path = clean_path_view(path)
  let method_key = meth
  let root = match self.trees.get(method_key) {
    Some(root) => Some(root)
    None =>
      if method_key == "HEAD" {
        self.trees.get("GET")
      } else {
        None
      }
  }
  match root {
    Some(root) => {
      let segments = split_segments(clean_path)
      if !(root.has_dynamic) {
        match match_static_node(root, segments, 0) {
          Some(node) =>
            found_route(
              node.route_path,
              method_key,
              Map([], capacity=0),
              "",
              "",
              node.handler,
            )
          None => self.dispatch_miss(clean_path)
        }
      } else {
        let captures : Array[(String, String)] = []
        match match_node(root, segments, 0, captures) {
          Some(result) => {
            let extra = if result.wildcard_name != "" { 1 } else { 0 }
            let params : Map[String, String] = Map(
              [],
              capacity=captures.length() + extra,
            )
            for capture in captures {
              params.set(capture.0, capture.1)
            }
            if result.wildcard_name != "" {
              params.set(result.wildcard_name, result.wildcard_value)
            }
            found_route(
              result.route_path,
              method_key,
              params,
              result.wildcard_value,
              result.wildcard_name,
              result.handler,
            )
          }
          None => self.dispatch_miss(clean_path)
        }
      }
    }
    None => self.dispatch_miss(clean_path)
  }
}

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

fn Router::dispatch_miss(self : Router, path : StringView) -> RouteOutcome {
  let allowed = self.allowed_methods(path)
  if allowed.length() > 0 {
    RouteMethodNotAllowed(allowed)
  } else {
    RouteNotFound
  }
}

pub fn Router::matching(
  self : Router,
  meth : String,
  path : String,
) -> Option[Route] {
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

pub fn Router::dispatch(self : Router, ctx : Context) -> Unit raise {
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
    RouteNotFound => not_found(ctx)
  }
}

pub fn not_found(ctx : Context) -> Unit {
  ctx.response.status = 404
  ctx.response.headers.set("Content-Type", "text/plain; charset=utf-8")
  ctx.response.body = "404 Not Found"
}

pub fn method_not_allowed(ctx : Context, allowed : Array[String]) -> Unit {
  ctx.response.status = 405
  ctx.response.headers.set("Allow", allowed.join(", "))
  ctx.response.headers.set("Content-Type", "text/plain; charset=utf-8")
  ctx.response.body = "405 Method Not Allowed"
}

pub fn internal_error(ctx : Context, detail : String) -> Unit {
  ctx.state.set("error", detail)
  ctx.response.status = 500
  ctx.response.headers.set("Content-Type", "text/plain; charset=utf-8")
  ctx.response.body = "Internal Server Error"
}

pub fn Context::set(self : Context, key : String, value : String) -> Unit {
  self.state.set(key, value)
}

pub fn Context::get(self : Context, key : String) -> String {
  match self.state.get(key) {
    Some(value) => value
    None => ""
  }
}

pub fn Context::param(self : Context, name : String) -> String {
  match self.state.get(PARAM_PREFIX + name) {
    Some(value) => value
    None => ""
  }
}

pub fn Context::status(self : Context, code : Int) -> Unit {
  self.response.status = code
}

pub fn Context::set_header(self : Context, key : String, value : String) -> Unit {
  self.response.headers.set(key, value)
}

pub fn Context::text(self : Context, status : Int, body : String) -> Unit {
  self.response.status = status
  self.response.headers.set("Content-Type", "text/plain; charset=utf-8")
  self.response.body = body
}

pub fn Context::html(self : Context, status : Int, body : String) -> Unit {
  self.response.status = status
  self.response.headers.set("Content-Type", "text/html; charset=utf-8")
  self.response.body = body
}

pub fn json_object(data : Map[String, String]) -> Json {
  let object : Map[String, Json] = Map([], capacity=data.length())
  for key, value in data {
    object.set(key, Json::string(value))
  }
  Json::object(object)
}

pub fn Context::json_value(self : Context, status : Int, data : Json) -> Unit {
  self.response.status = status
  self.response.headers.set("Content-Type", "application/json; charset=utf-8")
  self.response.body = data.stringify()
}

pub fn Context::json(self : Context, status : Int, data : Map[String, String]) -> Unit {
  self.json_value(status, json_object(data))
}

pub fn Context::redirect(self : Context, status : Int, location : String) -> Unit {
  self.response.status = status
  self.response.headers.set("Location", location)
  self.response.body = ""
}

pub fn Context::get_method(self : Context) -> String {
  self.request.method
}

pub fn Context::get_path(self : Context) -> String {
  self.request.path
}

pub fn Context::header(self : Context, key : String) -> String {
  match self.request.headers.get(key) {
    Some(value) => value
    None => ""
  }
}

pub fn Context::ip(self : Context) -> String {
  match self.state.get("remote_addr") {
    Some(value) => value
    None => "127.0.0.1"
  }
}

fn hex_digit(byte : Byte) -> Int {
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

fn decode_url(source : StringView) -> String {
  if !(source.contains("%")) && !(source.contains("+")) {
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

pub fn url_decode(source : String) -> String {
  decode_url(source)
}

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

pub fn parse_urlencoded(source : String) -> Map[String, String] {
  parse_urlencoded_view(source)
}

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
      None =>
        if decode_url(pair) == name {
          found = Some("")
        }
    }
  }
  match found {
    Some(value) => value
    None => ""
  }
}

pub fn Context::query(self : Context, name : String) -> String {
  let path = self.request.path
  match path.find("?") {
    Some(index) => query_param(path[index + 1:], name)
    None => ""
  }
}

pub fn Context::form(self : Context, name : String) -> String {
  let content_type = self.header("Content-Type")
  if !(content_type.has_prefix("application/x-www-form-urlencoded")) {
    return ""
  }
  query_param(self.request.body.view(), name)
}

pub fn status_text(code : Int) -> String {
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

pub struct App {
  router : Router
  middlewares : Array[Middleware]
  mut max_body_size : Int
  mut timeout : Int
  mut chain : Handler?
}

pub fn App::new() -> App {
  {
    router: create_router(),
    middlewares: [],
    max_body_size: DEFAULT_MAX_BODY_SIZE,
    timeout: 0,
    chain: None,
  }
}

pub fn App::use(self : App, middleware : Middleware) -> App {
  self.middlewares.push(middleware)
  self.chain = None
  self
}

pub fn App::route(self : App, meth : String, path : String, handler : Handler) -> App {
  self.router.add_route(meth, path, handler)
  self
}

pub fn App::get(self : App, path : String, handler : Handler) -> App {
  self.route("GET", path, handler)
}

pub fn App::post(self : App, path : String, handler : Handler) -> App {
  self.route("POST", path, handler)
}

pub fn App::put(self : App, path : String, handler : Handler) -> App {
  self.route("PUT", path, handler)
}

pub fn App::patch(self : App, path : String, handler : Handler) -> App {
  self.route("PATCH", path, handler)
}

pub fn App::delete(self : App, path : String, handler : Handler) -> App {
  self.route("DELETE", path, handler)
}

pub fn App::head(self : App, path : String, handler : Handler) -> App {
  self.route("HEAD", path, handler)
}

pub fn App::options(self : App, path : String, handler : Handler) -> App {
  self.route("OPTIONS", path, handler)
}

pub fn App::max_body_size(self : App, size : Int) -> App {
  self.max_body_size = size
  self
}

pub fn App::request_timeout(self : App, millis : Int) -> App {
  self.timeout = millis
  self
}

pub fn App::handle(self : App, ctx : Context) -> Unit raise {
  match self.chain {
    Some(chain) => chain(ctx)
    None => {
      let router = self.router
      let terminal : Handler = fn(ctx) raise { router.dispatch(ctx) }
      let chain = apply_middleware(self.middlewares, terminal)
      self.chain = Some(chain)
      chain(ctx)
    }
  }
}

pub fn App::respond(self : App, request : Request) -> Response {
  let ctx = Context::new(request)
  self.handle(ctx) catch {
    err => internal_error(ctx, "\{err}")
  }
  ctx.response
}

pub fn middleware_recover() -> Middleware {
  fn(next) {
    fn(ctx) {
      next(ctx) catch {
        err => internal_error(ctx, "\{err}")
      }
    }
  }
}

pub fn middleware_logger(log~ : (String) -> Unit = println) -> Middleware {
  fn(next) {
    fn(ctx) raise {
      next(ctx)
      log("[\{ctx.response.status}] \{ctx.request.method} \{ctx.request.path}")
    }
  }
}

pub fn middleware_cors(allow_origin~ : String = "*") -> Middleware {
  fn(next) {
    fn(ctx) raise {
      ctx.response.headers.set("Access-Control-Allow-Origin", allow_origin)
      if ctx.request.method == "OPTIONS" {
        ctx.response.status = 204
        ctx.response.headers.set(
          "Access-Control-Allow-Methods",
          "GET, POST, PUT, PATCH, DELETE, HEAD, OPTIONS",
        )
        ctx.response.headers.set("Access-Control-Allow-Headers", "*")
      } else {
        next(ctx)
      }
    }
  }
}

pub(all) struct Feather {
  config : Config
  app : App
}

pub fn create_feather(config : Config) -> Feather {
  {
    config,
    app: {
      router: create_router(),
      middlewares: [],
      max_body_size: DEFAULT_MAX_BODY_SIZE,
      timeout: config.timeout,
      chain: None,
    },
  }
}

pub fn Feather::use(self : Feather, middleware : Middleware) -> Feather {
  ignore(self.app.use(middleware))
  self
}

pub fn Feather::route(
  self : Feather,
  meth : String,
  path : String,
  handler : Handler,
) -> Feather {
  ignore(self.app.route(meth, path, handler))
  self
}

pub fn Feather::get(self : Feather, path : String, handler : Handler) -> Feather {
  self.route("GET", path, handler)
}

pub fn Feather::post(self : Feather, path : String, handler : Handler) -> Feather {
  self.route("POST", path, handler)
}

pub fn Feather::handle(self : Feather, request : Request) -> Response {
  self.app.respond(request)
}

pub fn Feather::validate_body_size(_self : Feather, body : String) -> Bool {
  body.length() <= DEFAULT_MAX_BODY_SIZE
}
