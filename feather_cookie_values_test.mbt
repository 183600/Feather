///|
fn cookie_values_context() -> @feather.Context {
  @feather.Context::new({
    method: "GET",
    path: "/",
    headers: Map([
      ("Cookie", "a=1; a=2; b=; c=\"x y\"; d=1=2; bad name=z; =empty; e"),
    ]),
    body: "",
  })
}

///|
test "cookies keeps the first value of a repeated cookie" {
  let ctx = cookie_values_context()
  let cookies = ctx.cookies()
  assert_eq(cookies.get("a"), Some("1"))
  assert_eq(cookies.get("b"), Some(""))
  assert_eq(cookies.get("c"), Some("x y"))
  assert_eq(cookies.get("d"), Some("1=2"))
  assert_eq(cookies.get("bad name"), None)
  assert_eq(cookies.get(""), None)
  assert_eq(cookies.get("e"), None)
}

///|
test "cookie_values returns every repeated value in header order" {
  let ctx = cookie_values_context()
  assert_eq(ctx.cookie_values("a").join("|"), "1|2")
  assert_eq(ctx.cookie_values("b").join("|"), "")
  assert_eq(ctx.cookie_values("c").join("|"), "x y")
  assert_eq(ctx.cookie_values("d").join("|"), "1=2")
  assert_eq(ctx.cookie_values("missing").length(), 0)
  assert_eq(ctx.cookie_values("").length(), 0)
  assert_eq(ctx.cookie_values("bad name").length(), 0)
}

///|
test "has_cookie distinguishes empty and missing cookies" {
  let ctx = cookie_values_context()
  assert_true(ctx.has_cookie("a"))
  assert_true(ctx.has_cookie("b"))
  assert_true(ctx.has_cookie("c"))
  assert_false(ctx.has_cookie("missing"))
  assert_false(ctx.has_cookie(""))
  assert_false(ctx.has_cookie("bad name"))
}

///|
test "cookies_all preserves duplicates and returns fresh arrays" {
  let ctx = cookie_values_context()
  let all = ctx.cookies_all()
  assert_eq(all.get("a").unwrap().join("|"), "1|2")
  assert_eq(all.get("b").unwrap().join("|"), "")
  assert_false(all.contains("bad name"))
  all.get("a").unwrap().push("mutated")
  assert_eq(ctx.cookie_values("a").join("|"), "1|2")
}

///|
test "cookie helpers return empty results without a Cookie header" {
  let ctx = @feather.Context::new({
    method: "GET",
    path: "/",
    headers: Map([]),
    body: "",
  })
  assert_eq(ctx.cookies().length(), 0)
  assert_eq(ctx.cookies_all().length(), 0)
  assert_eq(ctx.cookie_values("a").length(), 0)
  assert_false(ctx.has_cookie("a"))
}
