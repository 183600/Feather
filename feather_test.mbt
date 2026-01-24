// Test cases for Feather Web Framework
// Based on PLAN.md specifications

test "Feather server can be created with basic configuration" {
  let config : Config = {
    host: "127.0.0.1",
    port: 8080,
    timeout: 30000
  }
  let server = create_server(config)
  assert_eq!(server.host, "127.0.0.1")
  assert_eq!(server.port, 8080)
  assert_eq!(server.timeout, 30000)
}

test "Request and Response objects have expected properties" {
  let request : Request = {
    method: "GET",
    path: "/test",
    headers: Map::new(),
    body: ""
  }
  let response : Response = {
    status: 200,
    headers: Map::new(),
    body: "OK"
  }
  
  assert_eq!(request.method, "GET")
  assert_eq!(request.path, "/test")
  assert_eq!(response.status, 200)
}

test "Router can match static routes" {
  let router = create_router()
  let matched = router.matching("GET", "/api/users")
  assert_true!(matched.is_some())
  let route = matched.unwrap()
  assert_eq!(route.path, "/api/users")
}

test "Router can match parameterized routes" {
  let router = create_router()
  let matched = router.matching("GET", "/api/users/123")
  assert_true!(matched.is_some())
}

test "Router can match wildcard routes" {
  let router = create_router()
  let matched = router.matching("GET", "/api/files/deep/nested/path.txt")
  assert_true!(matched.is_some())
}

test "Middleware chaining" {
  let chain = compose_middleware([])
  assert_true!(chain.is_some())
}

test "Context can store and retrieve values" {
  let ctx = create_context()
  ctx.set("user_id", "42")
  assert_eq!(ctx.get("user_id"), "42")
}

test "Response helpers - JSON" {
  let ctx = create_context()
  let data : Map[String, String] = Map::new()
  ctx.json(200, data)
  assert_eq!(ctx.response.status, 200)
}
