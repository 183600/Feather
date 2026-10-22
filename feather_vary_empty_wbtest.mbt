///|
test "context vary replaces an empty existing field" {
  let ctx = create_context()
  ctx.set_header("Vary", "")
  ctx.vary("Origin")
  assert_eq(ctx.response.headers.get("Vary"), Some("Origin"))
}

///|
test "compression vary helper replaces an empty existing field" {
  let ctx = create_context()
  ctx.set_header("Vary", " \t ")
  add_vary_accept_encoding(ctx.response)
  assert_eq(ctx.response.headers.get("Vary"), Some("Accept-Encoding"))
}

///|
test "static vary helper replaces an empty existing field" {
  let headers : @http.Headers = Map([(header_vary, "")])
  add_vary_header(headers, "Accept-Encoding")
  assert_eq(headers.get(header_vary), Some("Accept-Encoding"))
}
