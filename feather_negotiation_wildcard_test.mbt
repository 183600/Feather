///|
fn wildcard_accept_ctx(accept : String) -> @feather.Context {
  @feather.Context::new({
    method: "GET",
    path: "/",
    headers: Map([("Accept", accept)]),
    body: "",
  })
}

///|
test "wildcard offers use the most specific matching range" {
  let ctx = wildcard_accept_ctx("text/*;q=0.5, */*;q=1")
  assert_eq(
    ctx.preferred_type(["text/*", "application/json"]),
    Some("application/json"),
  )
  assert_eq(ctx.preferred_type(["text/*"]), Some("text/*"))
}

///|
test "an explicit wildcard rejection overrides a broader range" {
  let ctx = wildcard_accept_ctx("text/*;q=0, */*;q=1")
  assert_false(ctx.accepts("text/*"))
  assert_eq(ctx.preferred_type(["text/*"]), None)
  assert_true(ctx.accepts("application/json"))
}

///|
test "a narrower range does not hide an accepted wildcard offer" {
  let ctx = wildcard_accept_ctx("text/html;q=0, text/*;q=0.5")
  assert_true(ctx.accepts("text/*"))
}
