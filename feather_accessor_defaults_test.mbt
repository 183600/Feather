///|
test "header_default returns values and distinguishes empty from absent" {
  let ctx = @feather.Context::new({
    method: "GET",
    path: "/",
    headers: Map([("X-Mode", "fast"), ("X-Empty", "")]),
    body: "",
  })
  assert_eq(ctx.header_default("x-mode", "slow"), "fast")
  assert_eq(ctx.header_default("X-Empty", "fallback"), "")
  assert_eq(ctx.header_default("X-Missing", "fallback"), "fallback")
}

///|
test "cookie_default returns values and distinguishes empty from absent" {
  let ctx = @feather.Context::new({
    method: "GET",
    path: "/",
    headers: Map([("Cookie", "theme=dark; empty=")]),
    body: "",
  })
  assert_eq(ctx.cookie_default("theme", "light"), "dark")
  assert_eq(ctx.cookie_default("empty", "fallback"), "")
  assert_eq(ctx.cookie_default("missing", "fallback"), "fallback")
  assert_eq(ctx.cookie_default("", "fallback"), "fallback")
}
