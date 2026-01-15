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
