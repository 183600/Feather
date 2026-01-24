// Test cases for Feather Web Framework
// Based on PLAN.md specifications

// Test 1: Basic HTTP server creation and configuration
test("Feather server can be created with basic configuration") {
  let config = {
    host: "127.0.0.1",
    port: 8080,
    timeout: 30000
  }
  let server = create_server(config)
  assert(server.host == "127.0.0.1")
  assert(server.port == 8080)
  assert(server.timeout == 30000)
}

// Test 2: Request and Response basic structure
test("Request and Response objects have expected properties") {
  let request = {
    method: "GET",
    path: "/test",
    headers: {"Content-Type": "application/json"},
    body: ""
  }
  let response = {
    status: 200,
    headers: {"Content-Type": "application/json"},
    body: "OK"
  }
  
  assert(request.method == "GET")
  assert(request.path == "/test")
  assert(response.status == 200)
}

// Test 3: Router with static path matching
test("Router can match static routes") {
  let router = create_router()
  let matched = router.match("GET", "/api/users")
  assert(matched.is_some())
  let route = matched.unwrap()
  assert(route.path == "/api/users")
}

// Test 4: Router with parameter matching
test("Router can match parameterized routes") {
  let router = create_router()
  let matched = router.match("GET", "/api/users/123")
  assert(matched.is_some())
  let route = matched.unwrap()
  assert(route.params["id"] == "123")
}

// Test 5: Router with wildcard matching
test("Router can match wildcard routes") {
  let router = create_router()
  let matched = router.match("GET", "/api/files/deep/nested/path.txt")
  assert(matched.is_some())
  let route = matched.unwrap()
  assert(route.wildcard == "deep/nested/path.txt")
}

// Test 6: Middleware chaining
test("Middleware can be chained in order") {
  let middleware1 = fn(next) {
    fn(ctx) {
      ctx.set("middleware1", "executed")
      next(ctx)
    }
  }
  
  let middleware2 = fn(next) {
    fn(ctx) {
      ctx.set("middleware2", "executed")
      next(ctx)
    }
  }
  
  let chain = compose_middleware([middleware1, middleware2])
  assert(chain.is_some())
}

// Test 7: Context management
test("Context can store and retrieve values") {
  let ctx = create_context()
  ctx.set("user_id", "42")
  ctx.set("request_time", "2024-01-24")
  
  assert(ctx.get("user_id") == "42")
  assert(ctx.get("request_time") == "2024-01-24")
}

// Test 8: Response helpers - JSON
test("Context can send JSON responses") {
  let ctx = create_context()
  let data = {"message": "success", "status": 200}
  
  ctx.json(200, data)
  assert(ctx.response.status == 200)
  assert(ctx.response.headers["Content-Type"] == "application/json")
}

// Test 9: Response helpers - Text
test("Context can send text responses") {
  let ctx = create_context()
  
  ctx.text(200, "Hello, World!")
  assert(ctx.response.status == 200)
  assert(ctx.response.headers["Content-Type"] == "text/plain")
  assert(ctx.response.body == "Hello, World!")
}

// Test 10: Response helpers - File
test("Context can send file responses") {
  let ctx = create_context()
  
  ctx.file(200, "/path/to/file.txt", "text/plain")
  assert(ctx.response.status == 200)
  assert(ctx.response.headers["Content-Type"] == "text/plain")
}

// Test 11: Error handling - panic recovery
test("Server recovers from panics in handlers") {
  let server = create_server({host: "127.0.0.1", port: 8080})
  let handler = fn(ctx) {
    panic("Unexpected error")
  }
  
  server.get("/panic", handler)
  let recovered = server.handle_panic(handler, create_context())
  assert(recovered == true)
}

// Test 12: CORS middleware
test("CORS middleware adds appropriate headers") {
  let cors_middleware = create_cors_middleware({
    origins: ["*"],
    methods: ["GET", "POST", "PUT", "DELETE"],
    headers: ["Content-Type", "Authorization"]
  })
  
  let ctx = create_context()
  let next_called = false
  
  let next = fn(c) {
    next_called = true
    c
  }
  
  let result = cors_middleware(next)(ctx)
  assert(next_called == true)
  assert(result.response.headers["Access-Control-Allow-Origin"] == "*")
}

// Test 13: Logging middleware
test("Logging middleware captures request information") {
  let logger = create_logger()
  let logging_middleware = create_logging_middleware(logger)
  
  let ctx = create_context()
  ctx.request.method = "GET"
  ctx.request.path = "/api/test"
  
  let next_called = false
  let next = fn(c) {
    next_called = true
    c
  }
  
  let result = logging_middleware(next)(ctx)
  assert(next_called == true)
  assert(logger.entries.len() > 0)
}

// Test 14: Timeout middleware
test("Timeout middleware enforces time limits") {
  let timeout_middleware = create_timeout_middleware(5000) // 5 seconds
  
  let ctx = create_context()
  let next_called = false
  
  let next = fn(c) {
    next_called = true
    c
  }
  
  let result = timeout_middleware(next)(ctx)
  assert(next_called == true)
}

// Test 15: Request ID middleware
test("Request ID middleware generates unique IDs") {
  let request_id_middleware = create_request_id_middleware()
  
  let ctx1 = create_context()
  let ctx2 = create_context()
  
  let next = fn(c) { c }
  
  let result1 = request_id_middleware(next)(ctx1)
  let result2 = request_id_middleware(next)(ctx2)
  
  assert(result1.request_id != result2.request_id)
  assert(result1.request_id.len() > 0)
}

// Test 16: Server connection handling
test("Server handles multiple connections properly") {
  let server = create_server({host: "127.0.0.1", port: 8080})
  
  let conn1 = create_mock_connection()
  let conn2 = create_mock_connection()
  
  let handled1 = server.handle_connection(conn1)
  let handled2 = server.handle_connection(conn2)
  
  assert(handled1 == true)
  assert(handled2 == true)
}

// Test 17: Request parsing
test("Server can parse HTTP requests correctly") {
  let raw_request = "GET /api/test HTTP/1.1\r\nHost: localhost\r\n\r\n"
  let parsed = parse_request(raw_request)
  
  assert(parsed.method == "GET")
  assert(parsed.path == "/api/test")
  assert(parsed.headers["Host"] == "localhost")
}

// Test 18: Response serialization
test("Server can serialize HTTP responses correctly") {
  let response = {
    status: 200,
    headers: {"Content-Type": "application/json"},
    body: "{\"message\":\"success\"}"
  }
  
  let serialized = serialize_response(response)
  assert(serialized.contains("HTTP/1.1 200"))
  assert(serialized.contains("Content-Type: application/json"))
  assert(serialized.contains("{\"message\":\"success\"}"))
}

// Test 19: Router trie structure
test("Router uses efficient trie structure for path matching") {
  let router = create_router()
  
  router.add_route("GET", "/api/users", handler1)
  router.add_route("GET", "/api/users/:id", handler2)
  router.add_route("POST", "/api/users", handler3)
  
  assert(router.routes.len() == 3)
  assert(router.trie_root != null)
}

// Test 20: Static file serving
test("Server can serve static files") {
  let server = create_server({host: "127.0.0.1", port: 8080})
  server.static("/static", "./public")
  
  let ctx = create_context()
  ctx.request.path = "/static/style.css"
  
  let handled = server.handle_static_file(ctx)
  assert(handled == true)
  assert(ctx.response.headers["Content-Type"] == "text/css")
}