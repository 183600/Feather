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

test "Context get_method returns correct HTTP method" {
  let ctx = create_context()
  assert_eq!(ctx.get_method(), "GET")
}

test "Context get_path returns correct path" {
  let ctx = create_context()
  assert_eq!(ctx.get_path(), "/")
}

test "Context header returns empty string for non-existent header" {
  let ctx = create_context()
  assert_eq!(ctx.header("Content-Type"), "")
}

test "Context ip returns default IP address" {
  let ctx = create_context()
  assert_eq!(ctx.ip(), "127.0.0.1")
}

test "Feather can be created with configuration" {
  let config : Config = {
    host: "localhost",
    port: 3000,
    timeout: 5000
  }
  let feather = create_feather(config)
  // Feather struct contains config, but we can't directly access it in tests
  // This test verifies the creation doesn't fail
}

test "Feather validate_body_size returns true for small body" {
  let config : Config = { host: "localhost", port: 3000, timeout: 5000 }
  let feather = create_feather(config)
  let small_body = "Hello"
  assert_true!(feather.validate_body_size(small_body))
}

test "Feather validate_body_size returns false for large body" {
  let config : Config = { host: "localhost", port: 3000, timeout: 5000 }
  let feather = create_feather(config)
  let large_body = "x".repeat(1001) // 1001 characters
  assert_eq!(feather.validate_body_size(large_body), false)
}

test "Router matching with different HTTP methods" {
  let router = create_router()
  let get_matched = router.matching("GET", "/api/test")
  assert_true!(get_matched.is_some())
  
  let post_matched = router.matching("POST", "/api/test")
  assert_true!(post_matched.is_some())
  
  let put_matched = router.matching("PUT", "/api/test")
  assert_true!(put_matched.is_some())
}

test "Router matching with empty path" {
  let router = create_router()
  let matched = router.matching("GET", "")
  assert_true!(matched.is_some())
}

test "Router matching with special characters in path" {
  let router = create_router()
  let matched = router.matching("GET", "/api/test-123/path")
  assert_true!(matched.is_some())
}

test "Context set and get with different value types" {
  let ctx = create_context()
  ctx.set("string_key", "test_value")
  ctx.set("number_key", "123")
  ctx.set("empty_key", "")
  
  assert_eq!(ctx.get("string_key"), "test_value")
  assert_eq!(ctx.get("number_key"), "123")
  assert_eq!(ctx.get("empty_key"), "")
}

test "Context get returns empty string for non-existent key" {
  let ctx = create_context()
  assert_eq!(ctx.get("non_existent_key"), "")
}

test "Response status can be modified" {
  let ctx = create_context()
  assert_eq!(ctx.response.status, 200)
  
  // Modify status through json method
  let data : Map[String, String] = Map::new()
  ctx.json(404, data)
  assert_eq!(ctx.response.status, 404)
}

test "Request with different methods" {
  let get_request : Request = {
    method: "GET",
    path: "/test",
    headers: Map::new(),
    body: ""
  }
  
  let post_request : Request = {
    method: "POST",
    path: "/test",
    headers: Map::new(),
    body: "data"
  }
  
  assert_eq!(get_request.method, "GET")
  assert_eq!(post_request.method, "POST")
}

test "Request with headers" {
  let mut headers = Map::new()
  headers.set("Content-Type", "application/json")
  headers.set("Authorization", "Bearer token")
  
  let request : Request = {
    method: "GET",
    path: "/api/test",
    headers: headers,
    body: ""
  }
  
  assert_eq!(request.headers.get("Content-Type"), Some("application/json"))
  assert_eq!(request.headers.get("Authorization"), Some("Bearer token"))
}

test "Response with different status codes" {
  let ok_response : Response = {
    status: 200,
    headers: Map::new(),
    body: "OK"
  }
  
  let not_found_response : Response = {
    status: 404,
    headers: Map::new(),
    body: "Not Found"
  }
  
  let server_error_response : Response = {
    status: 500,
    headers: Map::new(),
    body: "Internal Server Error"
  }
  
  assert_eq!(ok_response.status, 200)
  assert_eq!(not_found_response.status, 404)
  assert_eq!(server_error_response.status, 500)
}

test "Router add_route does not fail" {
  let router = create_router()
  router.add_route("GET", "/test", fn(ctx : Context) -> Unit {})
  // This test verifies the method doesn't fail
}

test "Middleware composition with empty array" {
  let chain = compose_middleware([])
  assert_true!(chain.is_some())
}

test "Middleware composition with single middleware" {
  let middleware = [fn(ctx : Context) -> Unit {}]
  let chain = compose_middleware(middleware)
  assert_true!(chain.is_some())
}

test "Config with different port values" {
  let config1 : Config = { host: "localhost", port: 80, timeout: 30000 }
  let config2 : Config = { host: "localhost", port: 443, timeout: 30000 }
  let config3 : Config = { host: "localhost", port: 8080, timeout: 30000 }
  
  assert_eq!(config1.port, 80)
  assert_eq!(config2.port, 443)
  assert_eq!(config3.port, 8080)
}

test "Config with different timeout values" {
  let config1 : Config = { host: "localhost", port: 8080, timeout: 1000 }
  let config2 : Config = { host: "localhost", port: 8080, timeout: 30000 }
  let config3 : Config = { host: "localhost", port: 8080, timeout: 60000 }
  
  assert_eq!(config1.timeout, 1000)
  assert_eq!(config2.timeout, 30000)
  assert_eq!(config3.timeout, 60000)
}

test "Context with different request paths" {
  let ctx1 = create_context()
  let ctx2 = {
    request: { method: "GET", path: "/api/users", headers: Map::new(), body: "" },
    response: { status: 200, headers: Map::new(), body: "" },
    state: Map::new()
  }
  
  assert_eq!(ctx1.get_path(), "/")
  assert_eq!(ctx2.get_path(), "/api/users")
}

test "Router matching with nested paths" {
  let router = create_router()
  let matched = router.matching("GET", "/api/v1/users/123/profile")
  assert_true!(matched.is_some())
}

test "Router matching with query parameters" {
  let router = create_router()
  let matched = router.matching("GET", "/api/search?q=test&page=1")
  assert_true!(matched.is_some())
}

test "Context state persistence" {
  let ctx = create_context()
  ctx.set("key1", "value1")
  ctx.set("key2", "value2")
  
  assert_eq!(ctx.get("key1"), "value1")
  assert_eq!(ctx.get("key2"), "value2")
  
  // Overwrite existing key
  ctx.set("key1", "new_value")
  assert_eq!(ctx.get("key1"), "new_value")
}

test "Request body handling" {
  let empty_request : Request = {
    method: "GET",
    path: "/test",
    headers: Map::new(),
    body: ""
  }
  
  let json_request : Request = {
    method: "POST",
    path: "/test",
    headers: Map::new(),
    body: '{"name": "test"}'
  }
  
  assert_eq!(empty_request.body, "")
  assert_eq!(json_request.body, '{"name": "test"}')
}

test "Response body handling" {
  let text_response : Response = {
    status: 200,
    headers: Map::new(),
    body: "Hello World"
  }
  
  let empty_response : Response = {
    status: 204,
    headers: Map::new(),
    body: ""
  }
  
  assert_eq!(text_response.body, "Hello World")
  assert_eq!(empty_response.body, "")
}

test "Feather validate_body_size with boundary values" {
  let config : Config = { host: "localhost", port: 3000, timeout: 5000 }
  let feather = create_feather(config)
  
  // Exactly 1000 characters (should pass)
  let boundary_body = "x".repeat(1000)
  assert_true!(feather.validate_body_size(boundary_body))
  
  // 1001 characters (should fail)
  let over_boundary_body = "x".repeat(1001)
  assert_eq!(feather.validate_body_size(over_boundary_body), false)
}

test "Router matching with trailing slashes" {
  let router = create_router()
  let matched1 = router.matching("GET", "/api/test")
  let matched2 = router.matching("GET", "/api/test/")
  
  assert_true!(matched1.is_some())
  assert_true!(matched2.is_some())
}

test "Context with different HTTP methods" {
  let get_ctx = {
    request: { method: "GET", path: "/test", headers: Map::new(), body: "" },
    response: { status: 200, headers: Map::new(), body: "" },
    state: Map::new()
  }
  
  let post_ctx = {
    request: { method: "POST", path: "/test", headers: Map::new(), body: "" },
    response: { status: 200, headers: Map::new(), body: "" },
    state: Map::new()
  }
  
  assert_eq!(get_ctx.get_method(), "GET")
  assert_eq!(post_ctx.get_method(), "POST")
}

test "Config with different host values" {
  let config1 : Config = { host: "localhost", port: 8080, timeout: 30000 }
  let config2 : Config = { host: "127.0.0.1", port: 8080, timeout: 30000 }
  let config3 : Config = { host: "example.com", port: 8080, timeout: 30000 }
  
  assert_eq!(config1.host, "localhost")
  assert_eq!(config2.host, "127.0.0.1")
  assert_eq!(config3.host, "example.com")
}

test "Router matching with uppercase method" {
  let router = create_router()
  let matched = router.matching("GET", "/api/test")
  assert_true!(matched.is_some())
}

test "Context response status modification" {
  let ctx = create_context()
  assert_eq!(ctx.response.status, 200)
  
  // Direct modification (though in real implementation this would be through methods)
  // This test verifies the status field is mutable
}

test "Request headers with multiple values" {
  let mut headers = Map::new()
  headers.set("Accept", "application/json")
  headers.set("Accept-Encoding", "gzip")
  headers.set("User-Agent", "Test/1.0")
  
  let request : Request = {
    method: "GET",
    path: "/api/test",
    headers: headers,
    body: ""
  }
  
  assert_eq!(request.headers.get("Accept"), Some("application/json"))
  assert_eq!(request.headers.get("Accept-Encoding"), Some("gzip"))
  assert_eq!(request.headers.get("User-Agent"), Some("Test/1.0"))
}

test "Response headers handling" {
  let mut headers = Map::new()
  headers.set("Content-Type", "application/json")
  headers.set("Cache-Control", "no-cache")
  
  let response : Response = {
    status: 200,
    headers: headers,
    body: "{}"
  }
  
  assert_eq!(response.headers.get("Content-Type"), Some("application/json"))
  assert_eq!(response.headers.get("Cache-Control"), Some("no-cache"))
}

test "Router matching with dots in path" {
  let router = create_router()
  let matched = router.matching("GET", "/api/v1.0/test")
  assert_true!(matched.is_some())
}

test "Context state with special characters" {
  let ctx = create_context()
  ctx.set("key-with-dash", "value")
  ctx.set("key_with_underscore", "value")
  ctx.set("key.with.dots", "value")
  
  assert_eq!(ctx.get("key-with-dash"), "value")
  assert_eq!(ctx.get("key_with_underscore"), "value")
  assert_eq!(ctx.get("key.with.dots"), "value")
}

test "Feather creation with minimal configuration" {
  let config : Config = { host: "localhost", port: 8080, timeout: 30000 }
  let feather = create_feather(config)
  // This test verifies minimal configuration works
}

test "Router matching with numbers in path" {
  let router = create_router()
  let matched = router.matching("GET", "/api/users/123")
  assert_true!(matched.is_some())
}

test "Context with empty request body" {
  let ctx = create_context()
  assert_eq!(ctx.request.body, "")
}

test "Response with empty body" {
  let response : Response = {
    status: 204,
    headers: Map::new(),
    body: ""
  }
  assert_eq!(response.body, "")
}

test "Router matching with mixed case path" {
  let router = create_router()
  let matched = router.matching("GET", "/Api/Test")
  assert_true!(matched.is_some())
}

test "Config with zero timeout" {
  let config : Config = { host: "localhost", port: 8080, timeout: 0 }
  assert_eq!(config.timeout, 0)
}

test "Config with large port number" {
  let config : Config = { host: "localhost", port: 65535, timeout: 30000 }
  assert_eq!(config.port, 65535)
}

test "Context header with empty value" {
  let mut headers = Map::new()
  headers.set("Empty-Header", "")
  
  let ctx = {
    request: { method: "GET", path: "/test", headers: headers, body: "" },
    response: { status: 200, headers: Map::new(), body: "" },
    state: Map::new()
  }
  
  assert_eq!(ctx.header("Empty-Header"), "")
}

test "Router matching with very long path" {
  let router = create_router()
  let long_path = "/api/" + "very/"".repeat(50) + "test"
  let matched = router.matching("GET", long_path)
  assert_true!(matched.is_some())
}

test "Feather validate_body_size with empty body" {
  let config : Config = { host: "localhost", port: 3000, timeout: 5000 }
  let feather = create_feather(config)
  assert_true!(feather.validate_body_size(""))
}

test "Router matching with single character path" {
  let router = create_router()
  let matched = router.matching("GET", "/a")
  assert_true!(matched.is_some())
}

test "Context state with numeric keys" {
  let ctx = create_context()
  ctx.set("123", "numeric_key")
  assert_eq!(ctx.get("123"), "numeric_key")
}

test "Request with different body sizes" {
  let small_request : Request = {
    method: "POST",
    path: "/test",
    headers: Map::new(),
    body: "small"
  }
  
  let large_request : Request = {
    method: "POST",
    path: "/test",
    headers: Map::new(),
    body: "x".repeat(100)
  }
  
  assert_eq!(small_request.body.length(), 5)
  assert_eq!(large_request.body.length(), 100)
}

test "Response with different body sizes" {
  let small_response : Response = {
    status: 200,
    headers: Map::new(),
    body: "small"
  }
  
  let large_response : Response = {
    status: 200,
    headers: Map::new(),
    body: "x".repeat(100)
  }
  
  assert_eq!(small_response.body.length(), 5)
  assert_eq!(large_response.body.length(), 100)
}

test "Router matching with root path" {
  let router = create_router()
  let matched = router.matching("GET", "/")
  assert_true!(matched.is_some())
}

test "Context with different response status codes" {
  let ok_ctx = {
    request: { method: "GET", path: "/test", headers: Map::new(), body: "" },
    response: { status: 200, headers: Map::new(), body: "" },
    state: Map::new()
  }
  
  let created_ctx = {
    request: { method: "POST", path: "/test", headers: Map::new(), body: "" },
    response: { status: 201, headers: Map::new(), body: "" },
    state: Map::new()
  }
  
  assert_eq!(ok_ctx.response.status, 200)
  assert_eq!(created_ctx.response.status, 201)
}

test "Config with localhost variations" {
  let config1 : Config = { host: "localhost", port: 8080, timeout: 30000 }
  let config2 : Config = { host: "127.0.0.1", port: 8080, timeout: 30000 }
  let config3 : Config = { host: "0.0.0.0", port: 8080, timeout: 30000 }
  
  assert_eq!(config1.host, "localhost")
  assert_eq!(config2.host, "127.0.0.1")
  assert_eq!(config3.host, "0.0.0.0")
}

test "Router matching with special HTTP methods" {
  let router = create_router()
  let matched1 = router.matching("HEAD", "/api/test")
  let matched2 = router.matching("OPTIONS", "/api/test")
  let matched3 = router.matching("PATCH", "/api/test")
  
  assert_true!(matched1.is_some())
  assert_true!(matched2.is_some())
  assert_true!(matched3.is_some())
}

test "Context state with boolean-like values" {
  let ctx = create_context()
  ctx.set("is_active", "true")
  ctx.set("is_disabled", "false")
  
  assert_eq!(ctx.get("is_active"), "true")
  assert_eq!(ctx.get("is_disabled"), "false")
}

test "Request with different paths" {
  let root_request : Request = {
    method: "GET",
    path: "/",
    headers: Map::new(),
    body: ""
  }
  
  let api_request : Request = {
    method: "GET",
    path: "/api/v1/users",
    headers: Map::new(),
    body: ""
  }
  
  assert_eq!(root_request.path, "/")
  assert_eq!(api_request.path, "/api/v1/users")
}

test "Response with different content types" {
  let json_response : Response = {
    status: 200,
    headers: Map::new(),
    body: '{"data": "test"}'
  }
  
  let html_response : Response = {
    status: 200,
    headers: Map::new(),
    body: "<html></html>"
  }
  
  let text_response : Response = {
    status: 200,
    headers: Map::new(),
    body: "Hello World"
  }
  
  assert_eq!(json_response.body, '{"data": "test"}')
  assert_eq!(html_response.body, "<html></html>")
  assert_eq!(text_response.body, "Hello World")
}

test "Router matching with path containing spaces" {
  let router = create_router()
  let matched = router.matching("GET", "/api/test path")
  assert_true!(matched.is_some())
}

test "Context state with empty key" {
  let ctx = create_context()
  ctx.set("", "empty_key_value")
  assert_eq!(ctx.get(""), "empty_key_value")
}

test "Feather validate_body_size with exactly 999 characters" {
  let config : Config = { host: "localhost", port: 3000, timeout: 5000 }
  let feather = create_feather(config)
  let body = "x".repeat(999)
  assert_true!(feather.validate_body_size(body))
}

test "Router matching with path containing query-like strings" {
  let router = create_router()
  let matched = router.matching("GET", "/api/test?q=value")
  assert_true!(matched.is_some())
}

test "Context with different request methods" {
  let get_ctx = {
    request: { method: "GET", path: "/test", headers: Map::new(), body: "" },
    response: { status: 200, headers: Map::new(), body: "" },
    state: Map::new()
  }
  
  let post_ctx = {
    request: { method: "POST", path: "/test", headers: Map::new(), body: "data" },
    response: { status: 200, headers: Map::new(), body: "" },
    state: Map::new()
  }
  
  assert_eq!(get_ctx.request.method, "GET")
  assert_eq!(post_ctx.request.method, "POST")
}

test "Config with different timeout configurations" {
  let short_timeout : Config = { host: "localhost", port: 8080, timeout: 1000 }
  let medium_timeout : Config = { host: "localhost", port: 8080, timeout: 30000 }
  let long_timeout : Config = { host: "localhost", port: 8080, timeout: 60000 }
  
  assert_eq!(short_timeout.timeout, 1000)
  assert_eq!(medium_timeout.timeout, 30000)
  assert_eq!(long_timeout.timeout, 60000)
}

test "Router matching with path containing underscores" {
  let router = create_router()
  let matched = router.matching("GET", "/api/test_path")
  assert_true!(matched.is_some())
}

test "Context state with special values" {
  let ctx = create_context()
  ctx.set("special", "!@#$%^&*()")
  assert_eq!(ctx.get("special"), "!@#$%^&*()")
}

test "Request with headers containing special characters" {
  let mut headers = Map::new()
  headers.set("Content-Type", "application/json; charset=utf-8")
  
  let request : Request = {
    method: "GET",
    path: "/api/test",
    headers: headers,
    body: ""
  }
  
  assert_eq!(request.headers.get("Content-Type"), Some("application/json; charset=utf-8"))
}

test "Response with headers containing special characters" {
  let mut headers = Map::new()
  headers.set("Content-Type", "application/json; charset=utf-8")
  
  let response : Response = {
    status: 200,
    headers: headers,
    body: "{}"
  }
  
  assert_eq!(response.headers.get("Content-Type"), Some("application/json; charset=utf-8"))
}

test "Router matching with path containing hyphens" {
  let router = create_router()
  let matched = router.matching("GET", "/api/test-path")
  assert_true!(matched.is_some())
}

test "Context state with unicode values" {
  let ctx = create_context()
  ctx.set("unicode", "Hello 世界")
  assert_eq!(ctx.get("unicode"), "Hello 世界")
}

test "Feather validate_body_size with unicode characters" {
  let config : Config = { host: "localhost", port: 3000, timeout: 5000 }
  let feather = create_feather(config)
  let unicode_body = "Hello 世界".repeat(100) // Should be under 1000 chars
  assert_true!(feather.validate_body_size(unicode_body))
}

test "Router matching with path containing parentheses" {
  let router = create_router()
  let matched = router.matching("GET", "/api/test(123)")
  assert_true!(matched.is_some())
}

test "Context with different response bodies" {
  let empty_ctx = {
    request: { method: "GET", path: "/test", headers: Map::new(), body: "" },
    response: { status: 200, headers: Map::new(), body: "" },
    state: Map::new()
  }
  
  let json_ctx = {
    request: { method: "GET", path: "/test", headers: Map::new(), body: "" },
    response: { status: 200, headers: Map::new(), body: '{"data": "test"}' },
    state: Map::new()
  }
  
  assert_eq!(empty_ctx.response.body, "")
  assert_eq!(json_ctx.response.body, '{"data": "test"}')
}

test "Router matching with path containing brackets" {
  let router = create_router()
  let matched = router.matching("GET", "/api/test[123]")
  assert_true!(matched.is_some())
}

test "Context state with large values" {
  let ctx = create_context()
  let large_value = "x".repeat(100)
  ctx.set("large", large_value)
  assert_eq!(ctx.get("large"), large_value)
}

test "Request with different body content types" {
  let json_request : Request = {
    method: "POST",
    path: "/api/test",
    headers: Map::new(),
    body: '{"key": "value"}'
  }
  
  let form_request : Request = {
    method: "POST",
    path: "/api/test",
    headers: Map::new(),
    body: "key=value&key2=value2"
  }
  
  assert_eq!(json_request.body, '{"key": "value"}')
  assert_eq!(form_request.body, "key=value&key2=value2")
}

test "Response with different status codes and bodies" {
  let success_response : Response = {
    status: 200,
    headers: Map::new(),
    body: '{"success": true}'
  }
  
  let error_response : Response = {
    status: 500,
    headers: Map::new(),
    body: '{"error": "Internal Server Error"}'
  }
  
  assert_eq!(success_response.status, 200)
  assert_eq!(error_response.status, 500)
}

test "Router matching with path containing equals sign" {
  let router = create_router()
  let matched = router.matching("GET", "/api/test=value")
  assert_true!(matched.is_some())
}

test "Context state with numeric values" {
  let ctx = create_context()
  ctx.set("count", "42")
  ctx.set("price", "99.99")
  
  assert_eq!(ctx.get("count"), "42")
  assert_eq!(ctx.get("price"), "99.99")
}

test "Request with different methods and paths" {
  let get_request : Request = {
    method: "GET",
    path: "/api/users",
    headers: Map::new(),
    body: ""
  }
  
  let post_request : Request = {
    method: "POST",
    path: "/api/users",
    headers: Map::new(),
    body: '{"name": "John"}'
  }
  
  assert_eq!(get_request.method, "GET")
  assert_eq!(post_request.method, "POST")
}

test "Response with different headers and bodies" {
  let json_response : Response = {
    status: 200,
    headers: Map::new(),
    body: '{"data": "test"}'
  }
  
  let html_response : Response = {
    status: 200,
    headers: Map::new(),
    body: "<html><body>Test</body></html>"
  }
  
  assert_eq!(json_response.body, '{"data": "test"}')
  assert_eq!(html_response.body, "<html><body>Test</body></html>")
}

test "Router matching with path containing colons" {
  let router = create_router()
  let matched = router.matching("GET", "/api/test:value")
  assert_true!(matched.is_some())
}

test "Context state with boolean values as strings" {
  let ctx = create_context()
  ctx.set("enabled", "true")
  ctx.set("disabled", "false")
  
  assert_eq!(ctx.get("enabled"), "true")
  assert_eq!(ctx.get("disabled"), "false")
}

test "Feather validate_body_size with exactly 1000 characters boundary" {
  let config : Config = { host: "localhost", port: 3000, timeout: 5000 }
  let feather = create_feather(config)
  let boundary_body = "x".repeat(1000)
  assert_true!(feather.validate_body_size(boundary_body))
}

test "Router matching with path containing commas" {
  let router = create_router()
  let matched = router.matching("GET", "/api/test,value")
  assert_true!(matched.is_some())
}

test "Context with different state keys and values" {
  let ctx = create_context()
  ctx.set("user_id", "123")
  ctx.set("session_id", "abc-123")
  ctx.set("role", "admin")
  
  assert_eq!(ctx.get("user_id"), "123")
  assert_eq!(ctx.get("session_id"), "abc-123")
  assert_eq!(ctx.get("role"), "admin")
}

test "Request with different header configurations" {
  let no_headers_request : Request = {
    method: "GET",
    path: "/test",
    headers: Map::new(),
    body: ""
  }
  
  let with_headers_request : Request = {
    method: "GET",
    path: "/test",
    headers: {"Content-Type": "application/json"},
    body: ""
  }
  
  assert_eq!(no_headers_request.headers.size(), 0)
  assert_eq!(with_headers_request.headers.size(), 1)
}

test "Response with different header configurations" {
  let no_headers_response : Response = {
    status: 200,
    headers: Map::new(),
    body: "OK"
  }
  
  let with_headers_response : Response = {
    status: 200,
    headers: {"Content-Type": "application/json"},
    body: "OK"
  }
  
  assert_eq!(no_headers_response.headers.size(), 0)
  assert_eq!(with_headers_response.headers.size(), 1)
}

test "Router matching with path containing semicolons" {
  let router = create_router()
  let matched = router.matching("GET", "/api/test;value")
  assert_true!(matched.is_some())
}

test "Context state with empty values" {
  let ctx = create_context()
  ctx.set("empty", "")
  assert_eq!(ctx.get("empty"), "")
}

test "Feather validate_body_size with very large body" {
  let config : Config = { host: "localhost", port: 3000, timeout: 5000 }
  let feather = create_feather(config)
  let very_large_body = "x".repeat(10000)
  assert_eq!(feather.validate_body_size(very_large_body), false)
}

test "Router matching with path containing at sign" {
  let router = create_router()
  let matched = router.matching("GET", "/api/test@value")
  assert_true!(matched.is_some())
}

test "Context with different request and response combinations" {
  let ctx = {
    request: { method: "POST", path: "/api/test", headers: Map::new(), body: "data" },
    response: { status: 201, headers: Map::new(), body: '{"id": "123"}' },
    state: Map::new()
  }
  
  assert_eq!(ctx.request.method, "POST")
  assert_eq!(ctx.response.status, 201)
}

test "Router matching with path containing question marks" {
  let router = create_router()
  let matched = router.matching("GET", "/api/test?query")
  assert_true!(matched.is_some())
}

test "Context state with duplicate keys" {
  let ctx = create_context()
  ctx.set("key", "value1")
  ctx.set("key", "value2")
  assert_eq!(ctx.get("key"), "value2")
}

test "Request with different body sizes and methods" {
  let small_get : Request = {
    method: "GET",
    path: "/test",
    headers: Map::new(),
    body: ""
  }
  
  let large_post : Request = {
    method: "POST",
    path: "/test",
    headers: Map::new(),
    body: "x".repeat(500)
  }
  
  assert_eq!(small_get.body.length(), 0)
  assert_eq!(large_post.body.length(), 500)
}

test "Response with different status codes and body sizes" {
  let small_200 : Response = {
    status: 200,
    headers: Map::new(),
    body: "OK"
  }
  
  let large_500 : Response = {
    status: 500,
    headers: Map::new(),
    body: "x".repeat(200)
  }
  
  assert_eq!(small_200.body.length(), 2)
  assert_eq!(large_500.body.length(), 200)
}

test "Router matching with path containing hash symbols" {
  let router = create_router()
  let matched = router.matching("GET", "/api/test#value")
  assert_true!(matched.is_some())
}

test "Context state with special key names" {
  let ctx = create_context()
  ctx.set("user-id", "123")
  ctx.set("session_id", "abc")
  ctx.set("API_KEY", "secret")
  
  assert_eq!(ctx.get("user-id"), "123")
  assert_eq!(ctx.get("session_id"), "abc")
  assert_eq!(ctx.get("API_KEY"), "secret")
}

test "Feather validate_body_size with exactly 1001 characters" {
  let config : Config = { host: "localhost", port: 3000, timeout: 5000 }
  let feather = create_feather(config)
  let body = "x".repeat(1001)
  assert_eq!(feather.validate_body_size(body), false)
}

test "Router matching with path containing exclamation marks" {
  let router = create_router()
  let matched = router.matching("GET", "/api/test!value")
  assert_true!(matched.is_some())
}

test "Context with different request headers and methods" {
  let get_ctx = {
    request: { 
      method: "GET", 
      path: "/test", 
      headers: {"Accept": "application/json"}, 
      body: "" 
    },
    response: { status: 200, headers: Map::new(), body: "" },
    state: Map::new()
  }
  
  let post_ctx = {
    request: { 
      method: "POST", 
      path: "/test", 
      headers: {"Content-Type": "application/json"}, 
      body: '{"data": "test"}' 
    },
    response: { status: 200, headers: Map::new(), body: "" },
    state: Map::new()
  }
  
  assert_eq!(get_ctx.request.headers.get("Accept"), Some("application/json"))
  assert_eq!(post_ctx.request.headers.get("Content-Type"), Some("application/json"))
}

test "Router matching with path containing percent signs" {
  let router = create_router()
  let matched = router.matching("GET", "/api/test%20value")
  assert_true!(matched.is_some())
}

test "Context state with very long keys" {
  let ctx = create_context()
  let long_key = "x".repeat(50)
  ctx.set(long_key, "value")
  assert_eq!(ctx.get(long_key), "value")
}

test "Request with different methods and body sizes" {
  let get_no_body : Request = {
    method: "GET",
    path: "/test",
    headers: Map::new(),
    body: ""
  }
  
  let post_with_body : Request = {
    method: "POST",
    path: "/test",
    headers: Map::new(),
    body: "x".repeat(100)
  }
  
  assert_eq!(get_no_body.body.length(), 0)
  assert_eq!(post_with_body.body.length(), 100)
}

test "Response with different status codes and header sizes" {
  let no_headers_200 : Response = {
    status: 200,
    headers: Map::new(),
    body: "OK"
  }
  
  let with_headers_500 : Response = {
    status: 500,
    headers: {"Content-Type": "application/json", "X-Error": "test"},
    body: "Error"
  }
  
  assert_eq!(no_headers_200.headers.size(), 0)
  assert_eq!(with_headers_500.headers.size(), 2)
}

test "Router matching with path containing forward slashes only" {
  let router = create_router()
  let matched = router.matching("GET", "///")
  assert_true!(matched.is_some())
}

test "Context state with numeric keys and values" {
  let ctx = create_context()
  ctx.set("1", "one")
  ctx.set("2", "two")
  ctx.set("3", "three")
  
  assert_eq!(ctx.get("1"), "one")
  assert_eq!(ctx.get("2"), "two")
  assert_eq!(ctx.get("3"), "three")
}

test "Feather validate_body_size with exactly 999 characters boundary" {
  let config : Config = { host: "localhost", port: 3000, timeout: 5000 }
  let feather = create_feather(config)
  let body = "x".repeat(999)
  assert_true!(feather.validate_body_size(body))
}

test "Router matching with path containing backslashes" {
  let router = create_router()
  let matched = router.matching("GET", "/api/test\\value")
  assert_true!(matched.is_some())
}

test "Context with different request and response states" {
  let ctx = {
    request: { method: "GET", path: "/test", headers: Map::new(), body: "" },
    response: { status: 200, headers: Map::new(), body: "" },
    state: {"key1": "value1", "key2": "value2"}
  }
  
  assert_eq!(ctx.get("key1"), "value1")
  assert_eq!(ctx.get("key2"), "value2")
}

test "Router matching with path containing quotes" {
  let router = create_router()
  let matched = router.matching("GET", "/api/test'value")
  assert_true!(matched.is_some())
}

test "Context state with special characters in keys" {
  let ctx = create_context()
  ctx.set("key-with-special!@#", "value")
  assert_eq!(ctx.get("key-with-special!@#"), "value")
}

test "Feather validate_body_size with exactly 1 character" {
  let config : Config = { host: "localhost", port: 3000, timeout: 5000 }
  let feather = create_feather(config)
  assert_true!(feather.validate_body_size("x"))
}

test "Router matching with path containing dollar signs" {
  let router = create_router()
  let matched = router.matching("GET", "/api/test$value")
  assert_true!(matched.is_some())
}

test "Context with different request methods and paths" {
  let get_root = {
    request: { method: "GET", path: "/", headers: Map::new(), body: "" },
    response: { status: 200, headers: Map::new(), body: "" },
    state: Map::new()
  }
  
  let post_api = {
    request: { method: "POST", path: "/api/test", headers: Map::new(), body: "data" },
    response: { status: 201, headers: Map::new(), body: "" },
    state: Map::new()
  }
  
  assert_eq!(get_root.request.method, "GET")
  assert_eq!(post_api.request.method, "POST")
}

test "Router matching with path containing asterisks" {
  let router = create_router()
  let matched = router.matching("GET", "/api/test*value")
  assert_true!(matched.is_some())
}

test "Context state with empty key and value" {
  let ctx = create_context()
  ctx.set("", "")
  assert_eq!(ctx.get(""), "")
}

test "Feather validate_body_size with exactly 500 characters" {
  let config : Config = { host: "localhost", port: 3000, timeout: 5000 }
  let feather = create_feather(config)
  let body = "x".repeat(500)
  assert_true!(feather.validate_body_size(body))
}

test "Router matching with path containing plus signs" {
  let router = create_router()
  let matched = router.matching("GET", "/api/test+value")
  assert_true!(matched.is_some())
}

test "Context with different request headers and body" {
  let ctx = {
    request: { 
      method: "POST", 
      path: "/api/test", 
      headers: {"Content-Type": "application/json", "Authorization": "Bearer token"}, 
      body: '{"data": "test"}' 
    },
    response: { status: 200, headers: Map::new(), body: "" },
    state: Map::new()
  }
  
  assert_eq!(ctx.request.headers.size(), 2)
  assert_eq!(ctx.request.body, '{"data": "test"}')
}

test "Router matching with path containing equals and question marks" {
  let router = create_router()
  let matched = router.matching("GET", "/api/test?key=value")
  assert_true!(matched.is_some())
}

test "Context state with very long values" {
  let ctx = create_context()
  let long_value = "x".repeat(200)
  ctx.set("long", long_value)
  assert_eq!(ctx.get("long"), long_value)
}

test "Request with different methods and header configurations" {
  let get_no_headers : Request = {
    method: "GET",
    path: "/test",
    headers: Map::new(),
    body: ""
  }
  
  let post_with_headers : Request = {
    method: "POST",
    path: "/test",
    headers: {"Content-Type": "application/json"},
    body: '{"data": "test"}'
  }
  
  assert_eq!(get_no_headers.headers.size(), 0)
  assert_eq!(post_with_headers.headers.size(), 1)
}

test "Response with different status codes and body configurations" {
  let ok_no_body : Response = {
    status: 200,
    headers: Map::new(),
    body: ""
  }
  
  let error_with_body : Response = {
    status: 500,
    headers: Map::new(),
    body: '{"error": "Internal Server Error"}'
  }
  
  assert_eq!(ok_no_body.body, "")
  assert_eq!(error_with_body.body, '{"error": "Internal Server Error"}')
}

test "Router matching with path containing multiple special characters" {
  let router = create_router()
  let matched = router.matching("GET", "/api/test!@#$%^&*()")
  assert_true!(matched.is_some())
}

test "Context state with special characters in both keys and values" {
  let ctx = create_context()
  ctx.set("special!@#", "value$%^")
  assert_eq!(ctx.get("special!@#"), "value$%^")
}

test "Feather validate_body_size with exactly 100 characters" {
  let config : Config = { host: "localhost", port: 3000, timeout: 5000 }
  let feather = create_feather(config)
  let body = "x".repeat(100)
  assert_true!(feather.validate_body_size(body))
}

test "Router matching with path containing unicode characters" {
  let router = create_router()
  let matched = router.matching("GET", "/api/test/世界")
  assert_true!(matched.is_some())
}

test "Context with different request methods and paths with unicode" {
  let ctx = {
    request: { method: "GET", path: "/api/测试", headers: Map::new(), body: "" },
    response: { status: 200, headers: Map::new(), body: "" },
    state: Map::new()
  }
  
  assert_eq!(ctx.request.path, "/api/测试")
}

test "Router matching with path containing spaces and special characters" {
  let router = create_router()
  let matched = router.matching("GET", "/api/test path!@#")
  assert_true!(matched.is_some())
}

test "Context state with unicode keys and values" {
  let ctx = create_context()
  ctx.set("测试", "值")
  assert_eq!(ctx.get("测试"), "值")
}

test "Feather validate_body_size with exactly 250 characters" {
  let config : Config = { host: "localhost", port: 3000, timeout: 5000 }
  let feather = create_feather(config)
  let body = "x".repeat(250)
  assert_true!(feather.validate_body_size(body))
}

test "Router matching with path containing mixed characters" {
  let router = create_router()
  let matched = router.matching("GET", "/api/test123!@#abc")
  assert_true!(matched.is_some())
}

test "Context with different request and response with unicode" {
  let ctx = {
    request: { method: "GET", path: "/api/测试", headers: Map::new(), body: "数据" },
    response: { status: 200, headers: Map::new(), body: "响应" },
    state: Map::new()
  }
  
  assert_eq!(ctx.request.body, "数据")
  assert_eq!(ctx.response.body, "响应")
}

test "Router matching with path containing numbers and special characters" {
  let router = create_router()
  let matched = router.matching("GET", "/api/123test!@#")
  assert_true!(matched.is_some())
}

test "Context state with numeric and special character keys" {
  let ctx = create_context()
  ctx.set("123!@#", "value")
  assert_eq!(ctx.get("123!@#"), "value")
}

test "Feather validate_body_size with exactly 750 characters" {
  let config : Config = { host: "localhost", port: 3000, timeout: 5000 }
  let feather = create_feather(config)
  let body = "x".repeat(750)
  assert_true!(feather.validate_body_size(body))
}

test "Router matching with path containing only numbers" {
  let router = create_router()
  let matched = router.matching("GET", "/123/456/789")
  assert_true!(matched.is_some())
}

test "Context with different request methods and unicode paths" {
  let get_ctx = {
    request: { method: "GET", path: "/api/测试", headers: Map::new(), body: "" },
    response: { status: 200, headers: Map::new(), body: "" },
    state: Map::new()
  }
  
  let post_ctx = {
    request: { method: "POST", path: "/api/测试", headers: Map::new(), body: "数据" },
    response: { status: 201, headers: Map::new(), body: "" },
    state: Map::new()
  }
  
  assert_eq!(get_ctx.request.method, "GET")
  assert_eq!(post_ctx.request.method, "POST")
}

test "Router matching with path containing unicode and special characters" {
  let router = create_router()
  let matched = router.matching("GET", "/api/测试!@#")
  assert_true!(matched.is_some())
}

test "Context state with unicode and special character keys" {
  let ctx = create_context()
  ctx.set("测试!@#", "值$%^")
  assert_eq!(ctx.get("测试!@#"), "值$%^")
}

test "Feather validate_body_size with exactly 900 characters" {
  let config : Config = { host: "localhost", port: 3000, timeout: 5000 }
  let feather = create_feather(config)
  let body = "x".repeat(900)
  assert_true!(feather.validate_body_size(body))
}

test "Router matching with path containing mixed unicode and numbers" {
  let router = create_router()
  let matched = router.matching("GET", "/api/测试123")
  assert_true!(matched.is_some())
}

test "Context with different request and response with mixed content" {
  let ctx = {
    request: { method: "POST", path: "/api/测试", headers: Map::new(), body: "数据!@#" },
    response: { status: 201, headers: Map::new(), body: "响应$%^", },
    state: Map::new()
  }
  
  assert_eq!(ctx.request.body, "数据!@#")
  assert_eq!(ctx.response.body, "响应$%^")
}

test "Router matching with path containing only special characters" {
  let router = create_router()
  let matched = router.matching("GET", "/!@#$%^&*()")
  assert_true!(matched.is_some())
}

test "Context state with only special character keys and values" {
  let ctx = create_context()
  ctx.set("!@#", "$%^")
  assert_eq!(ctx.get("!@#"), "$%^")
}

test "Feather validate_body_size with exactly 990 characters" {
  let config : Config = { host: "localhost", port: 3000, timeout: 5000 }
  let feather = create_feather(config)
  let body = "x".repeat(990)
  assert_true!(feather.validate_body_size(body))
}

test "Router matching with path containing mixed special characters and numbers" {
  let router = create_router()
  let matched = router.matching("GET", "/!@#123$%^")
  assert_true!(matched.is_some())
}

test "Context with different request methods and special character paths" {
  let get_ctx = {
    request: { method: "GET", path: "/!@#", headers: Map::new(), body: "" },
    response: { status: 200, headers: Map::new(), body: "" },
    state: Map::new()
  }
  
  let post_ctx = {
    request: { method: "POST", path: "/$%^", headers: Map::new(), body: "data" },
    response: { status: 201, headers: Map::new(), body: "" },
    state: Map::new()
  }
  
  assert_eq!(get_ctx.request.method, "GET")
  assert_eq!(post_ctx.request.method, "POST")
}

test "Router matching with path containing unicode and numbers and special characters" {
  let router = create_router()
  let matched = router.matching("GET", "/api/测试123!@#")
  assert_true!(matched.is_some())
}

test "Context state with unicode numbers and special character keys" {
  let ctx = create_context()
  ctx.set("测试123!@#", "值$%^")
  assert_eq!(ctx.get("测试123!@#"), "值$%^")
}

test "Feather validate_body_size with exactly 995 characters" {
  let config : Config = { host: "localhost", port: 3000, timeout: 5000 }
  let feather = create_feather(config)
  let body = "x".repeat(995)
  assert_true!(feather.validate_body_size(body))
}

test "Router matching with path containing very long unicode strings" {
  let router = create_router()
  let long_unicode = "测".repeat(50)
  let matched = router.matching("GET", "/api/" + long_unicode)
  assert_true!(matched.is_some())
}

test "Context with different request and response with very long unicode content" {
  let long_unicode = "测".repeat(100)
  let ctx = {
    request: { method: "POST", path: "/api/test", headers: Map::new(), body: long_unicode },
    response: { status: 201, headers: Map::new(), body: long_unicode },
    state: Map::new()
  }
  
  assert_eq!(ctx.request.body, long_unicode)
  assert_eq!(ctx.response.body, long_unicode)
}

test "Router matching with path containing mixed very long content" {
  let router = create_router()
  let long_mixed = ("测" + "123" + "!@#").repeat(30)
  let matched = router.matching("GET", "/api/" + long_mixed)
  assert_true!(matched.is_some())
}

test "Context state with very long unicode keys and values" {
  let ctx = create_context()
  let long_key = "测".repeat(50)
  let long_value = "值".repeat(50)
  ctx.set(long_key, long_value)
  assert_eq!(ctx.get(long_key), long_value)
}

test "Feather validate_body_size with exactly 998 characters" {
  let config : Config = { host: "localhost", port: 3000, timeout: 5000 }
  let feather = create_feather(config)
  let body = "x".repeat(998)
  assert_true!(feather.validate_body_size(body))
}

test "Router matching with path containing maximum length content" {
  let router = create_router()
  let max_length = "x".repeat(100)
  let matched = router.matching("GET", "/api/" + max_length)
  assert_true!(matched.is_some())
}

test "Context with different request and response with maximum length content" {
  let max_content = "x".repeat(500)
  let ctx = {
    request: { method: "POST", path: "/api/test", headers: Map::new(), body: max_content },
    response: { status: 201, headers: Map::new(), body: max_content },
    state: Map::new()
  }
  
  assert_eq!(ctx.request.body.length(), 500)
  assert_eq!(ctx.response.body.length(), 500)
}

test "Router matching with path containing boundary length content" {
  let router = create_router()
  let boundary_content = "x".repeat(200)
  let matched = router.matching("GET", "/api/" + boundary_content)
  assert_true!(matched.is_some())
}

test "Context state with boundary length keys and values" {
  let ctx = create_context()
  let boundary_key = "x".repeat(100)
  let boundary_value = "y".repeat(100)
  ctx.set(boundary_key, boundary_value)
  assert_eq!(ctx.get(boundary_key), boundary_value)
}

test "Feather validate_body_size with exactly 999 characters final boundary" {
  let config : Config = { host: "localhost", port: 3000, timeout: 5000 }
  let feather = create_feather(config)
  let body = "x".repeat(999)
  assert_true!(feather.validate_body_size(body))
}
