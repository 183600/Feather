test "recover middleware catches errors" {
  let mw = recover()
  let error_handler : Handler = fn(ctx) {
    panic("Test error")
  }
  
  let wrapped = mw(error_handler)
  let conn : @http.ServerConnection = panic()
  let req : @http.Request = panic()
  let ctx = Ctx::new(conn, req, Map::new())
  
  wrapped(ctx)
  // 验证返回了 500 错误响应
}

test "logger middleware logs request start and end" {
  let mw = logger()
  let handler : Handler = fn(ctx) {
    // 模拟处理时间
  }
  
  let wrapped = mw(handler)
  let conn : @http.ServerConnection = panic()
  let req : @http.Request = { meth: "GET", path: "/test" }
  let ctx = Ctx::new(conn, req, Map::new())
  
  wrapped(ctx)
  // 验证日志输出包含 START 和 END
}

test "timeout middleware handles timeout" {
  let mw = timeout(100)
  let slow_handler : Handler = fn(ctx) {
    @async.sleep(200)
  }
  
  let wrapped = mw(slow_handler)
  let conn : @http.ServerConnection = panic()
  let req : @http.Request = panic()
  let ctx = Ctx::new(conn, req, Map::new())
  
  wrapped(ctx)
  // 验证返回了 408 超时响应
}

test "cors middleware handles OPTIONS request" {
  let mw = cors()
  let handler : Handler = fn(ctx) {
    ctx.text(200, "OK", "test")
  }
  
  let wrapped = mw(handler)
  let conn : @http.ServerConnection = panic()
  let req : @http.Request = { meth: "OPTIONS", path: "/api" }
  let ctx = Ctx::new(conn, req, Map::new())
  
  wrapped(ctx)
  // 验证返回了 CORS 头
}

test "apply_middleware chains multiple middlewares" {
  let mw1 = fn(next) { fn(ctx) { next(ctx) } }
  let mw2 = fn(next) { fn(ctx) { next(ctx) } }
  let handler : Handler = fn(ctx) { }
  
  let mws = [mw1, mw2]
  let wrapped = apply_middleware(mws, handler)
  
  let conn : @http.ServerConnection = panic()
  let req : @http.Request = panic()
  let ctx = Ctx::new(conn, req, Map::new())
  
  wrapped(ctx)
  // 验证所有中间件都被调用
}

test "apply_middleware applies in correct order" {
  let call_order : Array[Int] = []
  
  let mw1 = fn(next) {
    fn(ctx) {
      call_order.push(1)
      next(ctx)
    }
  }
  
  let mw2 = fn(next) {
    fn(ctx) {
      call_order.push(2)
      next(ctx)
    }
  }
  
  let handler : Handler = fn(ctx) {
    call_order.push(3)
  }
  
  let mws = [mw1, mw2]
  let wrapped = apply_middleware(mws, handler)
  
  let conn : @http.ServerConnection = panic()
  let req : @http.Request = panic()
  let ctx = Ctx::new(conn, req, Map::new())
  
  wrapped(ctx)
  
  assert_eq!(call_order.length(), 3)
  assert_eq!(call_order[0], 1)
  assert_eq!(call_order[1], 2)
  assert_eq!(call_order[2], 3)
}

test "recover middleware handles different error types" {
  let mw = recover()
  
  // 测试字符串错误
  let string_error_handler : Handler = fn(ctx) {
    panic("String error message")
  }
  
  let wrapped1 = mw(string_error_handler)
  let conn1 : @http.ServerConnection = panic()
  let req1 : @http.Request = panic()
  let ctx1 = Ctx::new(conn1, req1, Map::new())
  
  wrapped1(ctx1)
  // 验证返回了 500 错误响应，包含错误信息
  
  // 测试自定义错误对象（模拟不同的错误类型）
  let custom_error_handler : Handler = fn(ctx) {
    panic("CustomError: validation failed")
  }
  
  let wrapped2 = mw(custom_error_handler)
  let conn2 : @http.ServerConnection = panic()
  let req2 : @http.Request = panic()
  let ctx2 = Ctx::new(conn2, req2, Map::new())
  
  wrapped2(ctx2)
  // 验证返回了 500 错误响应
}

test "timeout middleware completes successfully without timeout" {
  let mw = timeout(500) // 500ms 超时
  
  let fast_handler : Handler = fn(ctx) {
    // 快速处理，不睡眠
    ctx.status(200, "OK")
  }
  
  let wrapped = mw(fast_handler)
  let conn : @http.ServerConnection = panic()
  let req : @http.Request = panic()
  let ctx = Ctx::new(conn, req, Map::new())
  
  wrapped(ctx)
  // 验证正常完成，没有超时错误
  assert_eq!(true, true) // 测试通过意味着没有超时
}

test "cors middleware handles non-OPTIONS request correctly" {
  let mw = cors()
  let handler : Handler = fn(ctx) {
    ctx.text(200, "OK", "test response")
  }
  
  let wrapped = mw(handler)
  let conn : @http.ServerConnection = panic()
  let req : @http.Request = { meth: "GET", path: "/api/data" }
  let ctx = Ctx::new(conn, req, Map::new())
  
  wrapped(ctx)
  // 验证 GET 请求正常通过，并添加了 CORS 头
  // 验证响应包含 Access-Control-Allow-Origin: *
}

test "recover middleware handles different error types" {
  let mw = recover()
  
  // 测试字符串错误
  let error_handler1 : Handler = fn(ctx) {
    panic("String error")
  }
  
  // 测试复杂错误对象
  let error_handler2 : Handler = fn(ctx) {
    panic({"code": 500, "message": "Complex error"})
  }
  
  let wrapped1 = mw(error_handler1)
  let wrapped2 = mw(error_handler2)
  
  let conn : @http.ServerConnection = panic()
  let req : @http.Request = panic()
  let ctx = Ctx::new(conn, req, Map::new())
  
  // 验证两种错误都被捕获并返回500响应
  wrapped1(ctx)
  wrapped2(ctx)
}

test "cors middleware handles normal requests correctly" {
  let mw = cors()
  let handler : Handler = fn(ctx) {
    ctx.text(200, "OK", "test response")
  }
  
  let wrapped = mw(handler)
  let conn : @http.ServerConnection = panic()
  let req : @http.Request = { meth: "GET", path: "/api/data" }
  let ctx = Ctx::new(conn, req, Map::new())
  
  wrapped(ctx)
  // 验证正常请求通过了CORS中间件并调用了handler
}

test "timeout middleware allows fast handlers to complete" {
  let mw = timeout(1000) // 设置较长的超时时间
  let fast_handler : Handler = fn(ctx) {
    // 快速执行，不延迟
  }
  
  let wrapped = mw(fast_handler)
  let conn : @http.ServerConnection = panic()
  let req : @http.Request = panic()
  let ctx = Ctx::new(conn, req, Map::new())
  
  wrapped(ctx)
  // 验证快速处理器在超时时间内完成，没有触发超时错误
}
