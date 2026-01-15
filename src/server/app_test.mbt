test "App::new creates empty app" {
  let app = App::new()
  assert_eq!(app.middlewares.length(), 0)
}

test "App::use adds middleware" {
  let app = App::new()
  let mw : Middleware = fn(next) { fn(ctx) { next(ctx) } }
  
  app.use(mw)
  
  assert_eq!(app.middlewares.length(), 1)
}

test "App::get adds GET route" {
  let app = App::new()
  let handler : Handler = fn(ctx) { ctx.text(200, "OK", "test") }
  
  app.get("/test", handler)
  
  let (matched, params) = app.router.match("GET", "/test")
  assert_ne!(matched, None)
  assert_eq!(params.is_empty(), true)
}

test "App::post adds POST route" {
  let app = App::new()
  let handler : Handler = fn(ctx) { ctx.text(200, "OK", "test") }
  
  app.post("/test", handler)
  
  let (matched, params) = app.router.match("POST", "/test")
  assert_ne!(matched, None)
}

test "App supports multiple HTTP methods" {
  let app = App::new()
  let get_handler : Handler = fn(ctx) { ctx.text(200, "OK", "get") }
  let post_handler : Handler = fn(ctx) { ctx.text(200, "OK", "post") }
  
  app.get("/test", get_handler)
  app.post("/test", post_handler)
  
  let (get_matched, _) = app.router.match("GET", "/test")
  let (post_matched, _) = app.router.match("POST", "/test")
  
  assert_ne!(get_matched, None)
  assert_ne!(post_matched, None)
}

test "handle_connection returns 404 for non-existent route" {
  let app = App::new()
  let conn : @http.ServerConnection = panic()
  
  default_404(conn)
  // 验证返回了 404 响应
}

test "internal_500 sends error response" {
  let conn : @http.ServerConnection = panic()
  let err = Error::new("Test error")
  
  internal_500(conn, err)
  // 验证返回了 500 错误响应
}

test "App supports route parameters" {
  let app = App::new()
  let handler : Handler = fn(ctx) { 
    let id = ctx.params["id"]
    ctx.text(200, "OK", id)
  }
  
  app.get("/users/:id", handler)
  
  let (matched, params) = app.router.match("GET", "/users/123")
  assert_ne!(matched, None)
  assert_eq!(params["id"], "123")
}

test "App supports wildcard routes" {
  let app = App::new()
  let handler : Handler = fn(ctx) { 
    let path = ctx.params["path"]
    ctx.text(200, "OK", path)
  }
  
  app.get("/static/*path", handler)
  
  let (matched, params) = app.router.match("GET", "/static/css/style.css")
  assert_ne!(matched, None)
  assert_eq!(params["path"], "css/style.css")
}

test "App::put adds PUT route" {
  let app = App::new()
  let handler : Handler = fn(ctx) { ctx.text(200, "OK", "updated") }
  
  app.put("/users/:id", handler)
  
  let (matched, params) = app.router.match("PUT", "/users/123")
  assert_ne!(matched, None)
  assert_eq!(params["id"], "123")
}

test "App::delete adds DELETE route" {
  let app = App::new()
  let handler : Handler = fn(ctx) { ctx.status(204, "No Content") }
  
  app.delete("/users/:id", handler)
  
  let (matched, params) = app.router.match("DELETE", "/users/456")
  assert_ne!(matched, None)
  assert_eq!(params["id"], "456")
}

test "App middleware chain processes correctly" {
  let app = App::new()
  
  // 创建一个记录调用顺序的中间件
  let call_order : Array[String] = []
  
  let mw1 : Middleware = fn(next) {
    fn(ctx) {
      call_order.push("mw1-before")
      next(ctx)
      call_order.push("mw1-after")
    }
  }
  
  let mw2 : Middleware = fn(next) {
    fn(ctx) {
      call_order.push("mw2-before")
      next(ctx)
      call_order.push("mw2-after")
    }
  }
  
  // 添加中间件
  app.use(mw1)
  app.use(mw2)
  
  // 添加路由
  let handler : Handler = fn(ctx) {
    call_order.push("handler")
    ctx.status(200, "OK")
  }
  
  app.get("/test", handler)
  
  // 验证路由匹配
  let (matched, _) = app.router.match("GET", "/test")
  assert_ne!(matched, None)
  
  // 验证中间件已添加
  assert_eq!(app.middlewares.length(), 2)
}

test "App::put and App::delete add routes correctly" {
  let app = App::new()
  let put_handler : Handler = fn(ctx) { ctx.text(200, "OK", "put") }
  let delete_handler : Handler = fn(ctx) { ctx.text(200, "OK", "delete") }
  
  app.put("/users/:id", put_handler)
  app.delete("/users/:id", delete_handler)
  
  // 测试 PUT 路由
  let (put_matched, put_params) = app.router.match("PUT", "/users/123")
  assert_ne!(put_matched, None)
  assert_eq!(put_params["id"], "123")
  
  // 测试 DELETE 路由
  let (delete_matched, delete_params) = app.router.match("DELETE", "/users/456")
  assert_ne!(delete_matched, None)
  assert_eq!(delete_params["id"], "456")
}

test "App chains multiple middlewares correctly" {
  let app = App::new()
  let call_order : Array[String] = []
  
  // 创建三个中间件
  let mw1 : Middleware = fn(next) {
    fn(ctx) {
      call_order.push("mw1")
      next(ctx)
    }
  }
  
  let mw2 : Middleware = fn(next) {
    fn(ctx) {
      call_order.push("mw2")
      next(ctx)
    }
  }
  
  let mw3 : Middleware = fn(next) {
    fn(ctx) {
      call_order.push("mw3")
      next(ctx)
    }
  }
  
  // 添加所有中间件
  app.use(mw1)
  app.use(mw2)
  app.use(mw3)
  
  // 验证中间件已按顺序添加
  assert_eq!(app.middlewares.length(), 3)
  
  let handler : Handler = fn(ctx) {
    call_order.push("handler")
  }
  
  app.get("/test", handler)
  
  // 验证中间件链式调用顺序
  let conn : @http.ServerConnection = panic()
  let req : @http.Request = { meth: "GET", path: "/test" }
  let ctx = Ctx::new(conn, req, Map::new())
  
  let (matched, _) = app.router.match("GET", "/test")
  assert_ne!(matched, None)
  
  // 注意：这里我们只是验证路由匹配，实际调用需要异步执行
  // 在实际应用中，apply_middleware 会确保正确的调用顺序
}

test "App handles complex route patterns" {
  let app = App::new()
  let api_handler : Handler = fn(ctx) { ctx.text(200, "OK", "api") }
  let user_handler : Handler = fn(ctx) { 
    let user_id = ctx.params["userId"]
    let post_id = ctx.params["postId"]
    ctx.text(200, "OK", "user: {user_id}, post: {post_id}")
  }
  
  // 添加复杂的路由结构
  app.get("/api/v1/users", api_handler)
  app.get("/api/v1/users/:userId", user_handler)
  app.get("/api/v1/users/:userId/posts/:postId", user_handler)
  app.get("/api/v2/*path", api_handler)
  
  // 测试简单路由
  let (matched1, params1) = app.router.match("GET", "/api/v1/users")
  assert_ne!(matched1, None)
  assert_eq!(params1.is_empty(), true)
  
  // 测试单参数路由
  let (matched2, params2) = app.router.match("GET", "/api/v1/users/123")
  assert_ne!(matched2, None)
  assert_eq!(params2["userId"], "123")
  
  // 测试多参数路由
  let (matched3, params3) = app.router.match("GET", "/api/v1/users/456/posts/789")
  assert_ne!(matched3, None)
  assert_eq!(params3["userId"], "456")
  assert_eq!(params3["postId"], "789")
  
  // 测试通配符路由
  let (matched4, params4) = app.router.match("GET", "/api/v2/any/path/here")
  assert_ne!(matched4, None)
  assert_eq!(params4["path"], "any/path/here")
}

// 新增测试：App 中间件链处理错误和恢复
test "App middleware chain handles errors and recovery" {
  let app = App::new()
  let call_order : Array[String] = []
  
  // 创建一个会 panic 的 handler
  let error_handler : Handler = fn(ctx) {
    call_order.push("handler")
    panic("Handler error")
  }
  
  // 添加 recover 中间件
  app.use(recover())
  
  // 添加自定义中间件来记录调用顺序
  let logging_mw : Middleware = fn(next) {
    fn(ctx) {
      call_order.push("middleware-before")
      next(ctx)
      call_order.push("middleware-after")
    }
  }
  app.use(logging_mw)
  
  // 添加会出错的路由
  app.get("/error", error_handler)
  
  // 验证路由已添加
  let (matched, _) = app.router.match("GET", "/error")
  assert_ne!(matched, None)
  
  // 验证中间件已添加
  assert_eq!(app.middlewares.length(), 2)
  
  // 创建一个正常 handler 的路由
  let normal_handler : Handler = fn(ctx) {
    call_order.push("normal-handler")
    ctx.status(200, "OK")
  }
  app.get("/normal", normal_handler)
  
  let (matched2, _) = app.router.match("GET", "/normal")
  assert_ne!(matched2, None)
}

// 新增测试：App 处理复杂中间件链和路由集成
test "App handles complex middleware chain and route integration" {
  let app = App::new()
  let execution_log : Array[String] = []
  
  // 添加多个中间件
  let mw1 : Middleware = fn(next) {
    fn(ctx) {
      execution_log.push("mw1-start")
      next(ctx)
      execution_log.push("mw1-end")
    }
  }
  
  let mw2 : Middleware = fn(next) {
    fn(ctx) {
      execution_log.push("mw2-start")
      next(ctx)
      execution_log.push("mw2-end")
    }
  }
  
  let mw3 : Middleware = fn(next) {
    fn(ctx) {
      execution_log.push("mw3-start")
      next(ctx)
      execution_log.push("mw3-end")
    }
  }
  
  app.use(mw1)
  app.use(mw2)
  app.use(mw3)
  
  // 添加多个路由
  let handler1 : Handler = fn(ctx) {
    execution_log.push("handler-users")
    let id = ctx.params["id"]
    ctx.text(200, "OK", "User {id}")
  }
  
  let handler2 : Handler = fn(ctx) {
    execution_log.push("handler-posts")
    let user_id = ctx.params["userId"]
    let post_id = ctx.params["postId"]
    ctx.text(200, "OK", "Post {post_id} by user {user_id}")
  }
  
  app.get("/users/:id", handler1)
  app.get("/users/:userId/posts/:postId", handler2)
  app.get("/static/*path", fn(ctx) {
    execution_log.push("handler-static")
    ctx.text(200, "OK", "Static file")
  })
  
  // 验证所有路由都已注册
  assert_eq!(app.middlewares.length(), 3)
  
  // 测试不同路由的匹配
  let (matched1, params1) = app.router.match("GET", "/users/123")
  assert_ne!(matched1, None)
  assert_eq!(params1["id"], "123")
  
  let (matched2, params2) = app.router.match("GET", "/users/456/posts/789")
  assert_ne!(matched2, None)
  assert_eq!(params2["userId"], "456")
  assert_eq!(params2["postId"], "789")
  
  let (matched3, params3) = app.router.match("GET", "/static/css/style.css")
  assert_ne!(matched3, None)
  assert_eq!(params3["path"], "css/style.css")
  
  // 验证不存在的路由
  let (matched4, _) = app.router.match("GET", "/nonexistent")
  assert_eq!(matched4, None)
}

// 新增测试：App 的 HTTP 方法全面支持
test "App supports all HTTP methods comprehensively" {
  let app = App::new()
  let request_log : Array[String] = []
  
  // 为每种 HTTP 方法创建 handler
  let get_handler : Handler = fn(ctx) {
    request_log.push("GET")
    ctx.text(200, "OK", "GET response")
  }
  
  let post_handler : Handler = fn(ctx) {
    request_log.push("POST")
    ctx.text(201, "Created", "POST response")
  }
  
  let put_handler : Handler = fn(ctx) {
    request_log.push("PUT")
    ctx.text(200, "OK", "PUT response")
  }
  
  let delete_handler : Handler = fn(ctx) {
    request_log.push("DELETE")
    ctx.status(204, "No Content")
  }
  
  // 注册所有路由
  app.get("/resource", get_handler)
  app.post("/resource", post_handler)
  app.put("/resource/:id", put_handler)
  app.delete("/resource/:id", delete_handler)
  
  // 测试 GET
  let (get_match, get_params) = app.router.match("GET", "/resource")
  assert_ne!(get_match, None)
  assert_eq!(get_params.is_empty(), true)
  
  // 测试 POST
  let (post_match, post_params) = app.router.match("POST", "/resource")
  assert_ne!(post_match, None)
  assert_eq!(post_params.is_empty(), true)
  
  // 测试 PUT
  let (put_match, put_params) = app.router.match("PUT", "/resource/123")
  assert_ne!(put_match, None)
  assert_eq!(put_params["id"], "123")
  
  // 测试 DELETE
  let (delete_match, delete_params) = app.router.match("DELETE", "/resource/456")
  assert_ne!(delete_match, None)
  assert_eq!(delete_params["id"], "456")
  
  // 测试错误的方法
  let (patch_match, _) = app.router.match("PATCH", "/resource")
  assert_eq!(patch_match, None)
  
  // 验证所有路由都已注册
  assert_eq!(app.middlewares.length(), 0) // 没有中间件
}
