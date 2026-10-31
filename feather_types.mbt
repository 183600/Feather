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
  mut timeout : Int32
  mut body_limit : Int32
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

