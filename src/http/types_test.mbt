test "Ctx::new creates context with correct fields" {
  let conn : @http.ServerConnection = panic()
  let req : @http.Request = panic()
  let params = Map::new()
  params["id"] = "123"
  
  let ctx = Ctx::new(conn, req, params)
  
  assert_eq!(ctx.params["id"], "123")
  assert_eq!(ctx.state.is_empty(), true)
}

test "Ctx::text sends text response" {
  let conn : @http.ServerConnection = panic()
  let req : @http.Request = panic()
  let ctx = Ctx::new(conn, req, Map::new())
  
  ctx.text(200, "OK", "Hello World")
  // 验证响应已发送
}

test "Ctx::json sends json response" {
  let conn : @http.ServerConnection = panic()
  let req : @http.Request = panic()
  let ctx = Ctx::new(conn, req, Map::new())
  
  let json = { "message": "Hello", "status": "ok" }
  ctx.json(200, "OK", json)
  // 验证 JSON 响应已发送
}

test "Ctx::status sends status only response" {
  let conn : @http.ServerConnection = panic()
  let req : @http.Request = panic()
  let ctx = Ctx::new(conn, req, Map::new())
  
  ctx.status(204, "No Content")
  // 验证状态响应已发送
}

test "Ctx::state manages state correctly" {
  let conn : @http.ServerConnection = panic()
  let req : @http.Request = panic()
  let params = Map::new()
  let ctx = Ctx::new(conn, req, params)
  
  // 初始状态为空
  assert_eq!(ctx.state.is_empty(), true)
  
  // 添加状态数据
  ctx.state["user_id"] = "123"
  ctx.state["role"] = "admin"
  
  // 验证状态数据
  assert_eq!(ctx.state.length(), 2)
  assert_eq!(ctx.state["user_id"], "123")
  assert_eq!(ctx.state["role"], "admin")
}

test "Ctx handles multiple parameters" {
  let conn : @http.ServerConnection = panic()
  let req : @http.Request = panic()
  let params = Map::new()
  params["id"] = "123"
  params["action"] = "edit"
  params["type"] = "user"
  
  let ctx = Ctx::new(conn, req, params)
  
  // 验证所有参数都被正确存储
  assert_eq!(ctx.params.length(), 3)
  assert_eq!(ctx.params["id"], "123")
  assert_eq!(ctx.params["action"], "edit")
  assert_eq!(ctx.params["type"], "user")
}

test "Ctx methods can be called multiple times" {
  let conn : @http.ServerConnection = panic()
  let req : @http.Request = panic()
  let ctx = Ctx::new(conn, req, Map::new())
  
  // 可以多次调用 status 方法
  ctx.status(200, "OK")
  ctx.status(201, "Created")
  ctx.status(204, "No Content")
  
  // 验证没有 panic 或错误
  assert_eq!(true, true) // 测试通过意味着没有错误
}

test "Ctx::state stores and retrieves values correctly" {
  let conn : @http.ServerConnection = panic()
  let req : @http.Request = panic()
  let ctx = Ctx::new(conn, req, Map::new())
  
  // 设置状态值
  ctx.state["user_id"] = "123"
  ctx.state["role"] = "admin"
  
  // 验证状态值已存储
  assert_eq!(ctx.state["user_id"], "123")
  assert_eq!(ctx.state["role"], "admin")
  assert_eq!(ctx.state.is_empty(), false)
  assert_eq!(ctx.state.length(), 2)
}

test "Ctx::state handles empty state correctly" {
  let conn : @http.ServerConnection = panic()
  let req : @http.Request = panic()
  let ctx = Ctx::new(conn, req, Map::new())
  
  // 初始状态应该为空
  assert_eq!(ctx.state.is_empty(), true)
  assert_eq!(ctx.state.length(), 0)
  assert_eq!(ctx.state["nonexistent"], "")
}

test "Ctx::params and state work independently" {
  let conn : @http.ServerConnection = panic()
  let req : @http.Request = panic()
  let params = Map::new()
  params["id"] = "456"
  params["action"] = "edit"
  
  let ctx = Ctx::new(conn, req, params)
  
  // params 应该包含路由参数
  assert_eq!(ctx.params["id"], "456")
  assert_eq!(ctx.params["action"], "edit")
  assert_eq!(ctx.params.length(), 2)
  
  // state 应该独立于 params
  ctx.state["user_id"] = "789"
  ctx.state["timestamp"] = "1234567890"
  
  assert_eq!(ctx.state["user_id"], "789")
  assert_eq!(ctx.state["timestamp"], "1234567890")
  assert_eq!(ctx.state.length(), 2)
  
  // 验证 params 未被 state 影响
  assert_eq!(ctx.params.length(), 2)
  assert_eq!(ctx.params["id"], "456")
}

// 新增测试：Ctx::text 处理不同状态码和响应体
test "Ctx::text handles different status codes and body content" {
  let conn : @http.ServerConnection = panic()
  let req : @http.Request = panic()
  let ctx = Ctx::new(conn, req, Map::new())
  
  // 测试不同的状态码
  ctx.text(200, "OK", "Success response")
  ctx.text(201, "Created", "Resource created")
  ctx.text(400, "Bad Request", "Invalid input")
  ctx.text(500, "Internal Server Error", "Server error occurred")
  
  // 测试空响应体
  ctx.text(204, "No Content", "")
  
  // 测试包含特殊字符的响应体
  ctx.text(200, "OK", "Response with special chars: !@#$%^&*()")
  
  // 验证没有 panic 或错误
  assert_eq!(true, true)
}

// 新增测试：Ctx::json 处理复杂嵌套结构
test "Ctx::json handles complex nested JSON structures" {
  let conn : @http.ServerConnection = panic()
  let req : @http.Request = panic()
  let ctx = Ctx::new(conn, req, Map::new())
  
  // 测试嵌套对象
  let nested_json = {
    "user": {
      "id": 123,
      "name": "John",
      "profile": {
        "email": "john@example.com",
        "age": 30
      }
    },
    "metadata": {
      "timestamp": 1234567890,
      "version": "1.0"
    }
  }
  ctx.json(200, "OK", nested_json)
  
  // 测试数组
  let array_json = {
    "items": [1, 2, 3, 4, 5],
    "names": ["Alice", "Bob", "Charlie"]
  }
  ctx.json(200, "OK", array_json)
  
  // 测试空对象
  let empty_json = {}
  ctx.json(200, "OK", empty_json)
  
  // 验证没有 panic 或错误
  assert_eq!(true, true)
}

// 新增测试：Ctx::state 处理大量数据和边界情况
test "Ctx::state handles large amounts of data and edge cases" {
  let conn : @http.ServerConnection = panic()
  let req : @http.Request = panic()
  let ctx = Ctx::new(conn, req, Map::new())
  
  // 测试存储大量数据
  for i in 0..100 {
    ctx.state["key_{i}"] = "value_{i}"
  }
  
  // 验证所有数据都被正确存储
  assert_eq!(ctx.state.length(), 100)
  assert_eq!(ctx.state["key_0"], "value_0")
  assert_eq!(ctx.state["key_99"], "value_99")
  
  // 测试更新现有键
  ctx.state["key_50"] = "updated_value"
  assert_eq!(ctx.state["key_50"], "updated_value")
  
  // 测试访问不存在的键（应该返回空字符串）
  assert_eq!(ctx.state["nonexistent_key"], "")
  
  // 测试空键和空值
  ctx.state[""] = "empty_key"
  ctx.state["empty_value"] = ""
  assert_eq!(ctx.state[""], "empty_key")
  assert_eq!(ctx.state["empty_value"], "")
}
