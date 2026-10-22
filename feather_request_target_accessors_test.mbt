///|
fn target_ctx(target : String) -> @feather.Context {
  @feather.Context::new({
    method: "GET",
    path: target,
    headers: Map([]),
    body: "",
  })
}

///|
test "pathname strips the query and fragment but keeps percent escapes" {
  assert_eq(target_ctx("/users/42?tab=posts#bio").pathname(), "/users/42")
  assert_eq(target_ctx("/caf%C3%A9?x=1").pathname(), "/caf%C3%A9")
  assert_eq(target_ctx("/only/path").pathname(), "/only/path")
  assert_eq(target_ctx("/?#fragment").pathname(), "/")
  assert_eq(target_ctx("*").pathname(), "*")
  // `get_path` remains the complete request target.
  assert_eq(
    target_ctx("/users/42?tab=posts#bio").get_path(),
    "/users/42?tab=posts#bio",
  )
}

///|
test "query string preserves raw order duplicates and encoding" {
  assert_eq(
    target_ctx("/search?q=a+b&q=c%2Fd&empty=&flag").query_string(),
    "q=a+b&q=c%2Fd&empty=&flag",
  )
  assert_eq(target_ctx("/search?").query_string(), "")
  assert_eq(target_ctx("/search?#ignored").query_string(), "")
  assert_eq(target_ctx("/search#fragment?not-a-query").query_string(), "")
  assert_eq(target_ctx("/search").query_string(), "")
  assert_eq(target_ctx("*").query_string(), "")
}

///|
test "absolute-form targets expose normalized path and raw query" {
  let ctx = target_ctx("http://example.com/a/b?x=1&x=2#frag")
  assert_eq(ctx.pathname(), "/a/b")
  assert_eq(ctx.query_string(), "x=1&x=2")
  assert_eq(ctx.get_path(), "/a/b?x=1&x=2#frag")
  let root = target_ctx("http://example.com?q=1")
  assert_eq(root.pathname(), "/")
  assert_eq(root.query_string(), "q=1")
}

///|
async test "server target accessors keep the query spelling" {
  let app = @feather.App::new().get("/echo", fn(ctx) {
    ctx.text(200, ctx.pathname() + "|" + ctx.query_string())
  })
  with_server(app, client => {
    let response = client.get("/echo?q=a+b&q=c%2Fd&flag")
    assert_eq(response.code, 200)
    assert_eq(client.read_all().text(), "/echo|q=a+b&q=c%2Fd&flag")
  })
}
