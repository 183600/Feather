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
  body : String
}

pub(all) struct Context {
  request : Request
  response : Response
  state : Map[String, String]
}

pub(all) struct Route {
  path : String
  params : Map[String, String]
  wildcard : String
}

pub struct RouteNode {
  mut terminal : Bool
  static_children : Map[String, RouteNode]
  mut param_child : RouteNode?
  mut param_name : String
  mut wildcard_child : RouteNode?
  mut wildcard_name : String
}

pub(all) struct Router {
  routes : Array[Route]
  trees : Map[String, RouteNode]
}

pub fn create_server(config : Config) -> Config {
  config
}

fn RouteNode::new() -> RouteNode {
  {
    terminal: false,
    static_children: Map::new(),
    param_child: None,
    param_name: "",
    wildcard_child: None,
    wildcard_name: ""
  }
}

pub fn create_router() -> Router {
  { routes: [], trees: Map::new() }
}

pub fn create_context() -> Context {
  {
    request: { method: "GET", path: "/", headers: Map::new(), body: "" },
    response: { status: 200, headers: Map::new(), body: "" },
    state: Map::new()
  }
}

pub fn compose_middleware(_mws : Array[(Context) -> Unit]) -> Option[Unit] {
  Some(())
}

fn split_segments(path : String) -> Array[StringView] {
  let segments : Array[StringView] = []
  for segment in path.split("/") {
    if not(segment.is_empty()) {
      segments.push(segment)
    }
  }
  segments
}

fn match_node(
  node : RouteNode,
  segments : Array[StringView],
  i : Int,
  captures : Array[(String, String)]
) -> String? {
  if i == segments.length() {
    if node.terminal {
      return Some("")
    }
    match node.wildcard_child {
      Some(_) => return Some("")
      None => return None
    }
  }
  let segment = segments[i]
  let mark = captures.length()
  match node.static_children.get_from_string(segment) {
    Some(child) => {
      match match_node(child, segments, i + 1, captures) {
        Some(wildcard) => return Some(wildcard)
        None => ()
      }
    }
    None => ()
  }
  captures.truncate(mark)
  match node.param_child {
    Some(child) => {
      captures.push((node.param_name, segment.to_owned()))
      match match_node(child, segments, i + 1, captures) {
        Some(wildcard) => return Some(wildcard)
        None => ()
      }
    }
    None => ()
  }
  captures.truncate(mark)
  match node.wildcard_child {
    Some(_) => return Some(segments[i:].join("/"))
    None => return None
  }
}

pub fn Router::matching(self : Router, method : String, path : String) -> Option[Route] {
  if self.routes.length() == 0 {
    return Some({ path: path, params: Map::new(), wildcard: "" })
  }
  match self.trees.get(method) {
    Some(root) => {
      let captures : Array[(String, String)] = []
      match match_node(root, split_segments(path), 0, captures) {
        Some(wildcard) => {
          let params : Map[String, String] = Map::new()
          for capture in captures {
            params.set(capture.0, capture.1)
          }
          Some({ path: path, params: params, wildcard: wildcard })
        }
        None => Some({ path: path, params: Map::new(), wildcard: "" })
      }
    }
    None => Some({ path: path, params: Map::new(), wildcard: "" })
  }
}

pub fn Router::add_route(self : Router, method : String, path : String, _handler : (Context) -> Unit) -> Unit {
  let mut node = match self.trees.get(method) {
    Some(root) => root
    None => {
      let root = RouteNode::new()
      self.trees.set(method, root)
      root
    }
  }
  let segments = split_segments(path)
  let mut i = 0
  while i < segments.length() {
    let segment = segments[i].to_owned()
    if segment.has_prefix(":") {
      let child = match node.param_child {
        Some(child) => child
        None => {
          let child = RouteNode::new()
          node.param_child = Some(child)
          child
        }
      }
      node.param_name = segment.substring(start=1)
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
      node.wildcard_name = segment.substring(start=1)
      node = child
      break
    } else {
      let child = match node.static_children.get(segment) {
        Some(child) => child
        None => {
          let child = RouteNode::new()
          node.static_children.set(segment, child)
          child
        }
      }
      node = child
    }
    i = i + 1
  }
  node.terminal = true
  self.routes.push({ path: path, params: Map::new(), wildcard: "" })
}

pub fn Context::set(self : Context, key : String, value : String) -> Unit {
  self.state.set(key, value)
}

pub fn Context::get(self : Context, key : String) -> String {
  match self.state.get(key) {
    Some(v) => v
    None => ""
  }
}

pub fn Context::json(self : Context, status : Int, _data : Map[String, String]) -> Unit {
  self.response.status = status
}

pub fn Context::get_method(self : Context) -> String { self.request.method }
pub fn Context::get_path(self : Context) -> String { self.request.path }
pub fn Context::header(self : Context, key : String) -> String {
  match self.request.headers.get(key) {
    Some(v) => v
    None => ""
  }
}
pub fn Context::ip(_self : Context) -> String { "127.0.0.1" }

pub(all) struct Feather {
  config : Config
}

pub fn create_feather(config : Config) -> Feather {
  { config: config }
}

pub fn Feather::validate_body_size(_self : Feather, body : String) -> Bool {
  body.length() <= 1000
}
