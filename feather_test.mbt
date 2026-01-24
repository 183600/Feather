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

// Test 21: Query parameter parsing
test("Context can parse query parameters") {
  let ctx = create_context()
  ctx.request.path = "/api/search?q=moonbit&page=2&limit=10"
  
  let query = ctx.parse_query()
  assert(query["q"] == "moonbit")
  assert(query["page"] == "2")
  assert(query["limit"] == "10")
}

// Test 22: URL-encoded body parsing
test("Context can parse URL-encoded form data") {
  let ctx = create_context()
  ctx.request.headers["Content-Type"] = "application/x-www-form-urlencoded"
  ctx.request.body = "username=test&password=secret"
  
  let form = ctx.parse_form()
  assert(form["username"] == "test")
  assert(form["password"] == "secret")
}

// Test 23: JSON body parsing
test("Context can parse JSON request body") {
  let ctx = create_context()
  ctx.request.headers["Content-Type"] = "application/json"
  ctx.request.body = "{\"name\":\"Feather\",\"version\":\"0.1.0\"}"
  
  let json = ctx.parse_json()
  assert(json["name"] == "Feather")
  assert(json["version"] == "0.1.0")
}

// Test 24: Route priority - static before parameter
test("Static routes have higher priority than parameterized routes") {
  let router = create_router()
  router.add_route("GET", "/api/status", fn(ctx) { "static" })
  router.add_route("GET", "/api/:id", fn(ctx) { "parameter" })
  
  let matched1 = router.match("GET", "/api/status")
  let matched2 = router.match("GET", "/api/123")
  
  assert(matched1.unwrap().handler(create_context()) == "static")
  assert(matched2.unwrap().handler(create_context()) == "parameter")
}

// Test 25: HTTP method matching
test("Router correctly matches different HTTP methods") {
  let router = create_router()
  router.add_route("GET", "/api/users", fn(ctx) { "GET" })
  router.add_route("POST", "/api/users", fn(ctx) { "POST" })
  router.add_route("PUT", "/api/users", fn(ctx) { "PUT" })
  router.add_route("DELETE", "/api/users", fn(ctx) { "DELETE" })
  
  assert(router.match("GET", "/api/users").is_some())
  assert(router.match("POST", "/api/users").is_some())
  assert(router.match("PUT", "/api/users").is_some())
  assert(router.match("DELETE", "/api/users").is_some())
  assert(router.match("PATCH", "/api/users").is_none())
}

// Test 26: Authentication middleware
test("Authentication middleware validates tokens") {
  let auth_middleware = create_auth_middleware({
    secret: "test-secret",
    header_name: "Authorization"
  })
  
  let ctx = create_context()
  ctx.request.headers["Authorization"] = "Bearer valid-token"
  
  let next = fn(c) { c }
  let result = auth_middleware(next)(ctx)
  
  assert(result.user != null)
}

// Test 27: Rate limiting middleware
test("Rate limiting middleware prevents excessive requests") {
  let rate_limiter = create_rate_limiter({
    max_requests: 5,
    window_seconds: 60
  })
  
  let ctx = create_context()
  ctx.request.remote_addr = "127.0.0.1"
  
  let allowed_count = 0
  for i in 0..10 {
    if rate_limiter.allow(ctx) {
      allowed_count = allowed_count + 1
    }
  }
  
  assert(allowed_count == 5)
}

// Test 28: Response status codes
test("Context can set various HTTP status codes") {
  let ctx = create_context()
  
  ctx.status(200).text("OK")
  assert(ctx.response.status == 200)
  
  ctx.status(404).text("Not Found")
  assert(ctx.response.status == 404)
  
  ctx.status(500).text("Internal Server Error")
  assert(ctx.response.status == 500)
}

// Test 29: Cookie handling
test("Context can set and read cookies") {
  let ctx = create_context()
  
  ctx.set_cookie("session", "abc123", {
    max_age: 3600,
    http_only: true,
    secure: false
  })
  
  assert(ctx.response.headers["Set-Cookie"] != null)
  
  ctx.request.headers["Cookie"] = "session=abc123"
  let cookie = ctx.get_cookie("session")
  assert(cookie == "abc123")
}

// Test 30: Custom error handler
test("Server can use custom error handlers") {
  let server = create_server({host: "127.0.0.1", port: 8080})
  
  let error_handler = fn(ctx, error) {
    ctx.response.status = 500
    ctx.response.body = "Custom error: ${error}"
  }
  
  server.use_error_handler(error_handler)
  
  assert(server.error_handler != null)
}

// Test 31: Middleware can skip chain
test("Middleware can stop the chain early") {
  let middleware = fn(next) {
    fn(ctx) {
      ctx.response.status = 403
      ctx.response.body = "Forbidden"
      ctx // Stop the chain
    }
  }
  
  let next = fn(c) {
    c.response.status = 200
    c.response.body = "OK"
    c
  }
  
  let result = middleware(next)(create_context())
  assert(result.response.status == 403)
  assert(result.response.body == "Forbidden")
}

// Test 32: Context has helper methods for common responses
test("Context provides convenience methods for common responses") {
  let ctx = create_context()
  
  ctx.ok("Success")
  assert(ctx.response.status == 200)
  
  ctx.created("Resource created")
  assert(ctx.response.status == 201)
  
  ctx.bad_request("Invalid input")
  assert(ctx.response.status == 400)
  
  ctx.not_found("Resource not found")
  assert(ctx.response.status == 404)
  
  ctx.internal_server_error("Something went wrong")
  assert(ctx.response.status == 500)
}

// Test 33: Server graceful shutdown
test("Server can handle graceful shutdown") {
  let server = create_server({host: "127.0.0.1", port: 8080})
  
  server.start()
  let is_running = server.is_running()
  assert(is_running == true)
  
  server.shutdown()
  let stopped = server.is_running()
  assert(stopped == false)
}

// Test 34: Router with multiple parameters
test("Router can match routes with multiple parameters") {
  let router = create_router()
  router.add_route("GET", "/api/:version/users/:id/posts/:post_id", handler1)
  
  let matched = router.match("GET", "/api/v1/users/42/posts/100")
  assert(matched.is_some())
  
  let params = matched.unwrap().params
  assert(params["version"] == "v1")
  assert(params["id"] == "42")
  assert(params["post_id"] == "100")
}

// Test 35: Middleware execution order
test("Middleware executes in the correct order") {
  let execution_order = []
  
  let middleware1 = fn(next) {
    fn(ctx) {
      execution_order.push("middleware1")
      next(ctx)
    }
  }
  
  let middleware2 = fn(next) {
    fn(ctx) {
      execution_order.push("middleware2")
      next(ctx)
    }
  }
  
  let middleware3 = fn(next) {
    fn(ctx) {
      execution_order.push("middleware3")
      ctx
    }
  }
  
  let chain = compose_middleware([middleware1, middleware2, middleware3])
  let handler = fn(ctx) {
    execution_order.push("handler")
    ctx
  }
  
  chain(handler)(create_context())
  
  assert(execution_order[0] == "middleware1")
  assert(execution_order[1] == "middleware2")
  assert(execution_order[2] == "middleware3")
  assert(execution_order[3] == "handler")
}

// Test 36: Server configuration validation
test("Server validates configuration parameters") {
  let valid_config = {
    host: "0.0.0.0",
    port: 8080,
    timeout: 30000,
    max_connections: 1000
  }
  let server = create_server(valid_config)
  
  assert(server.config.host == "0.0.0.0")
  assert(server.config.port == 8080)
  assert(server.config.timeout == 30000)
  assert(server.config.max_connections == 1000)
}

// Test 37: Response streaming
test("Context can stream response data") {
  let ctx = create_context()
  
  let chunks = ["chunk1", "chunk2", "chunk3"]
  let stream = ctx.stream_response(200, chunks)
  
  assert(ctx.response.status == 200)
  assert(stream.is_some())
}

// Test 38: Wildcard route priority
test("Wildcard routes have lower priority than static and parameter routes") {
  let router = create_router()
  router.add_route("GET", "/api/docs", fn(ctx) { "static" })
  router.add_route("GET", "/api/:id", fn(ctx) { "parameter" })
  router.add_route("GET", "/api/*", fn(ctx) { "wildcard" })
  
  let matched1 = router.match("GET", "/api/docs")
  let matched2 = router.match("GET", "/api/123")
  let matched3 = router.match("GET", "/api/any/deep/path")
  
  assert(matched1.unwrap().handler(create_context()) == "static")
  assert(matched2.unwrap().handler(create_context()) == "parameter")
  assert(matched3.unwrap().handler(create_context()) == "wildcard")
}

// Test 39: Request body size limit
test("Server enforces request body size limits") {
  let server = create_server({
    host: "127.0.0.1",
    port: 8080,
    max_body_size: 1024 // 1KB limit
  })
  
  let small_body = "a" * 512
  let large_body = "a" * 2048
  
  assert(server.validate_body_size(small_body) == true)
  assert(server.validate_body_size(large_body) == false)
}

// Test 40: Context provides request information
test("Context exposes detailed request information") {
  let ctx = create_context()
  ctx.request.method = "POST"
  ctx.request.path = "/api/users"
  ctx.request.headers["Content-Type"] = "application/json"
  ctx.request.headers["User-Agent"] = "TestClient/1.0"
  ctx.request.remote_addr = "192.168.1.1"
  
  assert(ctx.method() == "POST")
  assert(ctx.path() == "/api/users")
  assert(ctx.header("Content-Type") == "application/json")
  assert(ctx.header("User-Agent") == "TestClient/1.0")
  assert(ctx.ip() == "192.168.1.1")
}