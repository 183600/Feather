///|
test "Router matching with path containing quotes" {
  let router = create_router()
  let matched = router.matching("GET", "/api/test'value")
  assert_true(matched.is_some())
}

///|
test "Context state with special characters in keys" {
  let ctx = create_context()
  ctx.set("key-with-special!@#", "value")
  assert_eq(ctx.get("key-with-special!@#"), "value")
}

///|
test "Feather validate_body_size with exactly 1 character" {
  let config : Config = { host: "localhost", port: 3000, timeout: 5000, }
  let feather = create_feather(config)
  assert_true(feather.validate_body_size("x"))
}

///|
test "Router matching with path containing dollar signs" {
  let router = create_router()
  let matched = router.matching("GET", "/api/test$value")
  assert_true(matched.is_some())
}

///|
test "Context with different request methods and paths" {
  let get_root : Context = {
    request: { method: "GET", path: "/", headers: Map::new(), body: "", },
    response: {
      status: 200,
      headers: Map::new(),
      body: "",
      data: None,
      cookies: [],
    },
    state: Map::new(),
    json_state: Map::new(),
    cleanups: [],
    file: None,
    session: None,
  }

  let post_api : Context = {
    request: {
      method: "POST",
      path: "/api/test",
      headers: Map::new(),
      body: "data",
    },
    response: {
      status: 201,
      headers: Map::new(),
      body: "",
      data: None,
      cookies: [],
    },
    state: Map::new(),
    json_state: Map::new(),
    cleanups: [],
    file: None,
    session: None,
  }

  assert_eq(get_root.request.method, "GET")
  assert_eq(post_api.request.method, "POST")
}

///|
test "Router matching with path containing asterisks" {
  let router = create_router()
  let matched = router.matching("GET", "/api/test*value")
  assert_true(matched.is_some())
}

///|
test "Context state with empty key and value" {
  let ctx = create_context()
  ctx.set("", "")
  assert_eq(ctx.get(""), "")
}

///|
test "Feather validate_body_size with exactly 500 characters" {
  let config : Config = { host: "localhost", port: 3000, timeout: 5000, }
  let feather = create_feather(config)
  let body = "x".repeat(500)
  assert_true(feather.validate_body_size(body))
}

///|
test "Router matching with path containing plus signs" {
  let router = create_router()
  let matched = router.matching("GET", "/api/test+value")
  assert_true(matched.is_some())
}

///|
test "Context with different request headers and body" {
  let ctx : Context = {
    request: {
      method: "POST",
      path: "/api/test",
      headers: {
        "Content-Type": "application/json",
        "Authorization": "Bearer token",
      },
      body: "{\"data\": \"test\"}",
    },
    response: {
      status: 200,
      headers: Map::new(),
      body: "",
      data: None,
      cookies: [],
    },
    state: Map::new(),
    json_state: Map::new(),
    cleanups: [],
    file: None,
    session: None,
  }

  assert_eq(ctx.request.headers.size(), 2)
  assert_eq(ctx.request.body, "{\"data\": \"test\"}")
}

///|
test "Router matching with path containing equals and question marks" {
  let router = create_router()
  let matched = router.matching("GET", "/api/test?key=value")
  assert_true(matched.is_some())
}

///|
test "Context state with very long values" {
  let ctx = create_context()
  let long_value = "x".repeat(200)
  ctx.set("long", long_value)
  assert_eq(ctx.get("long"), long_value)
}

///|
test "Request with different methods and header configurations" {
  let get_no_headers : Request = {
    method: "GET",
    path: "/test",
    headers: Map::new(),
    body: "",
  }

  let post_with_headers : Request = {
    method: "POST",
    path: "/test",
    headers: { "Content-Type": "application/json" },
    body: "{\"data\": \"test\"}",
  }

  assert_eq(get_no_headers.headers.size(), 0)
  assert_eq(post_with_headers.headers.size(), 1)
}

///|
test "Response with different status codes and body configurations" {
  let ok_no_body : Response = {
    status: 200,
    headers: Map::new(),
    body: "",
    data: None,
    cookies: [],
  }

  let error_with_body : Response = {
    status: 500,
    headers: Map::new(),
    body: "{\"error\": \"Internal Server Error\"}",
    data: None,
    cookies: [],
  }

  assert_eq(ok_no_body.body, "")
  assert_eq(error_with_body.body, "{\"error\": \"Internal Server Error\"}")
}

///|
test "Router matching with path containing multiple special characters" {
  let router = create_router()
  let matched = router.matching("GET", "/api/test!@#$%^&*()")
  assert_true(matched.is_some())
}

///|
test "Context state with special characters in both keys and values" {
  let ctx = create_context()
  ctx.set("special!@#", "value$%^")
  assert_eq(ctx.get("special!@#"), "value$%^")
}

///|
test "Feather validate_body_size with exactly 100 characters" {
  let config : Config = { host: "localhost", port: 3000, timeout: 5000, }
  let feather = create_feather(config)
  let body = "x".repeat(100)
  assert_true(feather.validate_body_size(body))
}

///|
test "Router matching with path containing unicode characters" {
  let router = create_router()
  let matched = router.matching("GET", "/api/test/世界")
  assert_true(matched.is_some())
}

///|
test "Context with different request methods and paths with unicode" {
  let ctx : Context = {
    request: {
      method: "GET",
      path: "/api/测试",
      headers: Map::new(),
      body: "",
    },
    response: {
      status: 200,
      headers: Map::new(),
      body: "",
      data: None,
      cookies: [],
    },
    state: Map::new(),
    json_state: Map::new(),
    cleanups: [],
    file: None,
    session: None,
  }

  assert_eq(ctx.request.path, "/api/测试")
}

///|
test "Router matching with path containing spaces and special characters" {
  let router = create_router()
  let matched = router.matching("GET", "/api/test path!@#")
  assert_true(matched.is_some())
}

///|
test "Context state with unicode keys and values" {
  let ctx = create_context()
  ctx.set("测试", "值")
  assert_eq(ctx.get("测试"), "值")
}

///|
test "Feather validate_body_size with exactly 250 characters" {
  let config : Config = { host: "localhost", port: 3000, timeout: 5000, }
  let feather = create_feather(config)
  let body = "x".repeat(250)
  assert_true(feather.validate_body_size(body))
}

///|
test "Router matching with path containing mixed characters" {
  let router = create_router()
  let matched = router.matching("GET", "/api/test123!@#abc")
  assert_true(matched.is_some())
}

///|
test "Context with different request and response with unicode" {
  let ctx : Context = {
    request: {
      method: "GET",
      path: "/api/测试",
      headers: Map::new(),
      body: "数据",
    },
    response: {
      status: 200,
      headers: Map::new(),
      body: "响应",
      data: None,
      cookies: [],
    },
    state: Map::new(),
    json_state: Map::new(),
    cleanups: [],
    file: None,
    session: None,
  }

  assert_eq(ctx.request.body, "数据")
  assert_eq(ctx.response.body, "响应")
}

///|
test "Router matching with path containing numbers and special characters" {
  let router = create_router()
  let matched = router.matching("GET", "/api/123test!@#")
  assert_true(matched.is_some())
}

///|
test "Context state with numeric and special character keys" {
  let ctx = create_context()
  ctx.set("123!@#", "value")
  assert_eq(ctx.get("123!@#"), "value")
}

///|
test "Feather validate_body_size with exactly 750 characters" {
  let config : Config = { host: "localhost", port: 3000, timeout: 5000, }
  let feather = create_feather(config)
  let body = "x".repeat(750)
  assert_true(feather.validate_body_size(body))
}

///|
test "Router matching with path containing only numbers" {
  let router = create_router()
  let matched = router.matching("GET", "/123/456/789")
  assert_true(matched.is_some())
}

///|
test "Context with different request methods and unicode paths" {
  let get_ctx : Context = {
    request: {
      method: "GET",
      path: "/api/测试",
      headers: Map::new(),
      body: "",
    },
    response: {
      status: 200,
      headers: Map::new(),
      body: "",
      data: None,
      cookies: [],
    },
    state: Map::new(),
    json_state: Map::new(),
    cleanups: [],
    file: None,
    session: None,
  }

  let post_ctx : Context = {
    request: {
      method: "POST",
      path: "/api/测试",
      headers: Map::new(),
      body: "数据",
    },
    response: {
      status: 201,
      headers: Map::new(),
      body: "",
      data: None,
      cookies: [],
    },
    state: Map::new(),
    json_state: Map::new(),
    cleanups: [],
    file: None,
    session: None,
  }

  assert_eq(get_ctx.request.method, "GET")
  assert_eq(post_ctx.request.method, "POST")
}

///|
test "Router matching with path containing unicode and special characters" {
  let router = create_router()
  let matched = router.matching("GET", "/api/测试!@#")
  assert_true(matched.is_some())
}

///|
test "Context state with unicode and special character keys" {
  let ctx = create_context()
  ctx.set("测试!@#", "值$%^")
  assert_eq(ctx.get("测试!@#"), "值$%^")
}

///|
test "Feather validate_body_size with exactly 900 characters" {
  let config : Config = { host: "localhost", port: 3000, timeout: 5000, }
  let feather = create_feather(config)
  let body = "x".repeat(900)
  assert_true(feather.validate_body_size(body))
}

///|
test "Router matching with path containing mixed unicode and numbers" {
  let router = create_router()
  let matched = router.matching("GET", "/api/测试123")
  assert_true(matched.is_some())
}

///|
test "Context with different request and response with mixed content" {
  let ctx : Context = {
    request: {
      method: "POST",
      path: "/api/测试",
      headers: Map::new(),
      body: "数据!@#",
    },
    response: {
      status: 201,
      headers: Map::new(),
      body: "响应$%^",
      data: None,
      cookies: [],
    },
    state: Map::new(),
    json_state: Map::new(),
    cleanups: [],
    file: None,
    session: None,
  }

  assert_eq(ctx.request.body, "数据!@#")
  assert_eq(ctx.response.body, "响应$%^")
}

///|
test "Router matching with path containing only special characters" {
  let router = create_router()
  let matched = router.matching("GET", "/!@#$%^&*()")
  assert_true(matched.is_some())
}

///|
test "Context state with only special character keys and values" {
  let ctx = create_context()
  ctx.set("!@#", "$%^")
  assert_eq(ctx.get("!@#"), "$%^")
}

///|
test "Feather validate_body_size with exactly 990 characters" {
  let config : Config = { host: "localhost", port: 3000, timeout: 5000, }
  let feather = create_feather(config)
  let body = "x".repeat(990)
  assert_true(feather.validate_body_size(body))
}

///|
test "Router matching with path containing mixed special characters and numbers" {
  let router = create_router()
  let matched = router.matching("GET", "/!@#123$%^")
  assert_true(matched.is_some())
}

///|
test "Context with different request methods and special character paths" {
  let get_ctx : Context = {
    request: { method: "GET", path: "/!@#", headers: Map::new(), body: "", },
    response: {
      status: 200,
      headers: Map::new(),
      body: "",
      data: None,
      cookies: [],
    },
    state: Map::new(),
    json_state: Map::new(),
    cleanups: [],
    file: None,
    session: None,
  }

  let post_ctx : Context = {
    request: {
      method: "POST",
      path: "/$%^",
      headers: Map::new(),
      body: "data",
    },
    response: {
      status: 201,
      headers: Map::new(),
      body: "",
      data: None,
      cookies: [],
    },
    state: Map::new(),
    json_state: Map::new(),
    cleanups: [],
    file: None,
    session: None,
  }

  assert_eq(get_ctx.request.method, "GET")
  assert_eq(post_ctx.request.method, "POST")
}

///|
test "Router matching with path containing unicode and numbers and special characters" {
  let router = create_router()
  let matched = router.matching("GET", "/api/测试123!@#")
  assert_true(matched.is_some())
}

///|
test "Context state with unicode numbers and special character keys" {
  let ctx = create_context()
  ctx.set("测试123!@#", "值$%^")
  assert_eq(ctx.get("测试123!@#"), "值$%^")
}

///|
test "Feather validate_body_size with exactly 995 characters" {
  let config : Config = { host: "localhost", port: 3000, timeout: 5000, }
  let feather = create_feather(config)
  let body = "x".repeat(995)
  assert_true(feather.validate_body_size(body))
}

///|
test "Router matching with path containing very long unicode strings" {
  let router = create_router()
  let long_unicode = "测".repeat(50)
  let matched = router.matching("GET", "/api/" + long_unicode)
  assert_true(matched.is_some())
}

///|
test "Context with different request and response with very long unicode content" {
  let long_unicode = "测".repeat(100)
  let ctx : Context = {
    request: {
      method: "POST",
      path: "/api/test",
      headers: Map::new(),
      body: long_unicode,
    },
    response: {
      status: 201,
      headers: Map::new(),
      body: long_unicode,
      data: None,
      cookies: [],
    },
    state: Map::new(),
    json_state: Map::new(),
    cleanups: [],
    file: None,
    session: None,
  }

  assert_eq(ctx.request.body, long_unicode)
  assert_eq(ctx.response.body, long_unicode)
}

///|
test "Router matching with path containing mixed very long content" {
  let router = create_router()
  let long_mixed = ("测" + "123" + "!@#").repeat(30)
  let matched = router.matching("GET", "/api/" + long_mixed)
  assert_true(matched.is_some())
}

///|
test "Context state with very long unicode keys and values" {
  let ctx = create_context()
  let long_key = "测".repeat(50)
  let long_value = "值".repeat(50)
  ctx.set(long_key, long_value)
  assert_eq(ctx.get(long_key), long_value)
}

///|
test "Feather validate_body_size with exactly 998 characters" {
  let config : Config = { host: "localhost", port: 3000, timeout: 5000, }
  let feather = create_feather(config)
  let body = "x".repeat(998)
  assert_true(feather.validate_body_size(body))
}

///|
test "Router matching with path containing maximum length content" {
  let router = create_router()
  let max_length = "x".repeat(100)
  let matched = router.matching("GET", "/api/" + max_length)
  assert_true(matched.is_some())
}

///|
test "Context with different request and response with maximum length content" {
  let max_content = "x".repeat(500)
  let ctx : Context = {
    request: {
      method: "POST",
      path: "/api/test",
      headers: Map::new(),
      body: max_content,
    },
    response: {
      status: 201,
      headers: Map::new(),
      body: max_content,
      data: None,
      cookies: [],
    },
    state: Map::new(),
    json_state: Map::new(),
    cleanups: [],
    file: None,
    session: None,
  }

  assert_eq(ctx.request.body.length(), 500)
  assert_eq(ctx.response.body.length(), 500)
}

///|
test "Router matching with path containing boundary length content" {
  let router = create_router()
  let boundary_content = "x".repeat(200)
  let matched = router.matching("GET", "/api/" + boundary_content)
  assert_true(matched.is_some())
}

///|
test "Context state with boundary length keys and values" {
  let ctx = create_context()
  let boundary_key = "x".repeat(100)
  let boundary_value = "y".repeat(100)
  ctx.set(boundary_key, boundary_value)
  assert_eq(ctx.get(boundary_key), boundary_value)
}

///|
test "Feather validate_body_size with exactly 999 characters final boundary" {
  let config : Config = { host: "localhost", port: 3000, timeout: 5000, }
  let feather = create_feather(config)
  let body = "x".repeat(999)
  assert_true(feather.validate_body_size(body))
}
