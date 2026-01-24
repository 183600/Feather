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

pub(all) struct Router {
  routes : Array[Route]
}

pub fn create_server(config : Config) -> Config {
  config
}

pub fn create_router() -> Router {
  { routes: [] }
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

pub fn Router::matching(self : Router, _method : String, path : String) -> Option[Route] {
  Some({ path: path, params: Map::new(), wildcard: "" })
}

pub fn Router::add_route(self : Router, _method : String, _path : String, _handler : (Context) -> Unit) -> Unit {
  ()
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
  body.length() < 1000
}
