test "Router::new creates empty router" {
  let router = Router::new()
  assert_eq!(router.routes.is_empty(), true)
}

test "Router::add_route adds static route" {
  let router = Router::new()
  let handler : Handler = fn(ctx) { }
  
  router.add_route("GET", "/users", handler)
  
  let (matched_handler, params) = router.match("GET", "/users")
  assert_ne!(matched_handler, None)
  assert_eq!(params.is_empty(), true)
}

test "Router::add_route adds param route" {
  let router = Router::new()
  let handler : Handler = fn(ctx) { }
  
  router.add_route("GET", "/users/:id", handler)
  
  let (matched_handler, params) = router.match("GET", "/users/123")
  assert_ne!(matched_handler, None)
  assert_eq!(params["id"], "123")
}

test "Router::add_route adds wildcard route" {
  let router = Router::new()
  let handler : Handler = fn(ctx) { }
  
  router.add_route("GET", "/static/*path", handler)
  
  let (matched_handler, params) = router.match("GET", "/static/css/style.css")
  assert_ne!(matched_handler, None)
  assert_eq!(params["path"], "css/style.css")
}

test "Router::match returns None for non-existent route" {
  let router = Router::new()
  let handler : Handler = fn(ctx) { }
  
  router.add_route("GET", "/users", handler)
  
  let (matched_handler, params) = router.match("GET", "/posts")
  assert_eq!(matched_handler, None)
}

test "Router::match respects method distinction" {
  let router = Router::new()
  let get_handler : Handler = fn(ctx) { }
  let post_handler : Handler = fn(ctx) { }
  
  router.add_route("GET", "/users", get_handler)
  router.add_route("POST", "/users", post_handler)
  
  let (get_matched, _) = router.match("GET", "/users")
  let (post_matched, _) = router.match("POST", "/users")
  let (put_matched, _) = router.match("PUT", "/users")
  
  assert_ne!(get_matched, None)
  assert_ne!(post_matched, None)
  assert_eq!(put_matched, None)
}

test "parse_path correctly splits paths" {
  let parts1 = parse_path("/users")
  assert_eq!(parts1.length(), 1)
  assert_eq!(parts1[0], "users")
  
  let parts2 = parse_path("/users/123/posts")
  assert_eq!(parts2.length(), 3)
  assert_eq!(parts2[0], "users")
  assert_eq!(parts2[1], "123")
  assert_eq!(parts2[2], "posts")
  
  let parts3 = parse_path("/")
  assert_eq!(parts3.length(), 0)
}

test "Router handles nested parameter routes" {
  let router = Router::new()
  let handler : Handler = fn(ctx) { }
  
  // 添加嵌套参数路由 /users/:userId/posts/:postId
  router.add_route("GET", "/users/:userId/posts/:postId", handler)
  
  // 测试匹配嵌套路由
  let (matched_handler, params) = router.match("GET", "/users/123/posts/456")
  assert_ne!(matched_handler, None)
  assert_eq!(params["userId"], "123")
  assert_eq!(params["postId"], "456")
  assert_eq!(params.length(), 2)
}

test "Router handles mixed static and parameter segments" {
  let router = Router::new()
  let handler : Handler = fn(ctx) { }
  
  // 添加混合路由 /api/v1/users/:id
  router.add_route("GET", "/api/v1/users/:id", handler)
  
  // 测试匹配
  let (matched_handler, params) = router.match("GET", "/api/v1/users/789")
  assert_ne!(matched_handler, None)
  assert_eq!(params["id"], "789")
  assert_eq!(params.length(), 1)
  
  // 测试不匹配的情况
  let (not_matched, _) = router.match("GET", "/api/v2/users/789")
  assert_eq!(not_matched, None)
}

test "Router handles multiple routes of different types" {
  let router = Router::new()
  let static_handler : Handler = fn(ctx) { }
  let param_handler : Handler = fn(ctx) { }
  let wildcard_handler : Handler = fn(ctx) { }
  
  // 添加三种不同类型的路由
  router.add_route("GET", "/static", static_handler)
  router.add_route("GET", "/users/:id", param_handler)
  router.add_route("GET", "/files/*path", wildcard_handler)
  
  // 测试静态路由
  let (static_match, static_params) = router.match("GET", "/static")
  assert_ne!(static_match, None)
  assert_eq!(static_params.is_empty(), true)
  
  // 测试参数路由
  let (param_match, param_params) = router.match("GET", "/users/123")
  assert_ne!(param_match, None)
  assert_eq!(param_params["id"], "123")
  
  // 测试通配符路由
  let (wildcard_match, wildcard_params) = router.match("GET", "/files/images/photo.jpg")
  assert_ne!(wildcard_match, None)
  assert_eq!(wildcard_params["path"], "images/photo.jpg")
}

test "Router handles multiple parameters in one route" {
  let router = Router::new()
  let handler : Handler = fn(ctx) { }
  
  // 添加带多个参数的路由
  router.add_route("GET", "/users/:userId/posts/:postId", handler)
  
  // 测试匹配并提取所有参数
  let (matched_handler, params) = router.match("GET", "/users/123/posts/456")
  assert_ne!(matched_handler, None)
  assert_eq!(params["userId"], "123")
  assert_eq!(params["postId"], "456")
  assert_eq!(params.length(), 2)
}

test "Router prioritizes static routes over parameter routes" {
  let router = Router::new()
  
  let static_handler : Handler = fn(ctx) { }
  let param_handler : Handler = fn(ctx) { }
  
  // 添加静态路由 /users/me
  router.add_route("GET", "/users/me", static_handler)
  // 添加参数路由 /users/:id
  router.add_route("GET", "/users/:id", param_handler)
  
  // 测试 /users/me 应该匹配静态路由
  let (matched1, params1) = router.match("GET", "/users/me")
  assert_ne!(matched1, None)
  assert_eq!(params1.is_empty(), true)
  
  // 测试 /users/123 应该匹配参数路由
  let (matched2, params2) = router.match("GET", "/users/123")
  assert_ne!(matched2, None)
  assert_eq!(params2["id"], "123")
}

test "Router handles complex nested routes" {
  let router = Router::new()
  let handler : Handler = fn(ctx) { }
  
  // 添加多层嵌套路由
  router.add_route("GET", "/api/v1/users/:userId/profile", handler)
  router.add_route("GET", "/api/v1/users/:userId/posts/:postId/comments/:commentId", handler)
  router.add_route("GET", "/api/v2/*path", handler)
  
  // 测试第一层嵌套
  let (matched1, params1) = router.match("GET", "/api/v1/users/123/profile")
  assert_ne!(matched1, None)
  assert_eq!(params1["userId"], "123")
  
  // 测试第二层嵌套
  let (matched2, params2) = router.match("GET", "/api/v1/users/456/posts/789/comments/999")
  assert_ne!(matched2, None)
  assert_eq!(params2["userId"], "456")
  assert_eq!(params2["postId"], "789")
  assert_eq!(params2["commentId"], "999")
  
  // 测试通配符路由
  let (matched3, params3) = router.match("GET", "/api/v2/some/nested/path")
  assert_ne!(matched3, None)
  assert_eq!(params3["path"], "some/nested/path")
}
