///|
fn int64_param(value : String) -> Int64? raise {
  let router = @feather.create_router()
  router.add_route("GET", "/items/:id", fn(ctx) { ctx.text(200, "ok") })
  let ctx = @feather.Context::new({
    method: "GET",
    path: "/items/" + value,
    headers: Map([]),
    body: "",
  })
  router.dispatch(ctx)
  ctx.param_int64("id")
}

///|
test "param_int64 covers the full signed 64-bit range" {
  assert_eq(int64_param("42"), Some(42L))
  assert_eq(int64_param("+42"), Some(42L))
  assert_eq(int64_param("00042"), Some(42L))
  assert_eq(int64_param("-0"), Some(0L))
  assert_eq(
    int64_param("9223372036854775807"),
    Some(9223372036854775807L),
  )
  assert_eq(
    int64_param("-9223372036854775808"),
    Some(-9223372036854775807L - 1L),
  )
  assert_eq(int64_param("9223372036854775808"), None)
  assert_eq(int64_param("-9223372036854775809"), None)
  assert_eq(int64_param("1.5"), None)
  assert_eq(int64_param("abc"), None)
  assert_eq(int64_param("+"), None)
  assert_eq(int64_param("-"), None)
}

///|
test "param_int stays limited to 32 bits alongside param_int64" {
  let router = @feather.create_router()
  router.add_route("GET", "/items/:id", fn(ctx) { ctx.text(200, "ok") })
  let ctx = @feather.Context::new({
    method: "GET",
    path: "/items/2147483648",
    headers: Map([]),
    body: "",
  })
  router.dispatch(ctx)
  assert_eq(ctx.param_int("id"), None)
  assert_eq(ctx.param_int64("id"), Some(2147483648L))
}

///|
test "query_int64 parses encoded signs and rejects overflow" {
  let ctx = @feather.Context::new({
    method: "GET",
    path: "/?max=9223372036854775807&min=-9223372036854775808&plus=%2B42&zeros=00042&over=9223372036854775808&under=-9223372036854775809&bad=12x&space=+42",
    headers: Map([]),
    body: "",
  })
  assert_eq(ctx.query_int64("max"), Some(9223372036854775807L))
  assert_eq(ctx.query_int64("min"), Some(-9223372036854775807L - 1L))
  assert_eq(ctx.query_int64("plus"), Some(42L))
  assert_eq(ctx.query_int64("zeros"), Some(42L))
  assert_eq(ctx.query_int64("over"), None)
  assert_eq(ctx.query_int64("under"), None)
  assert_eq(ctx.query_int64("bad"), None)
  assert_eq(ctx.query_int64("space"), None)
  assert_eq(ctx.query_int64("missing"), None)
}

///|
test "form_int64 parses form fields and ignores other media types" {
  let ctx = @feather.Context::new({
    method: "POST",
    path: "/",
    headers: Map([("Content-Type", "application/x-www-form-urlencoded")]),
    body: "max=9223372036854775807&min=-9223372036854775808&plus=%2B42&over=9223372036854775808&bad=1.0",
  })
  assert_eq(ctx.form_int64("max"), Some(9223372036854775807L))
  assert_eq(ctx.form_int64("min"), Some(-9223372036854775807L - 1L))
  assert_eq(ctx.form_int64("plus"), Some(42L))
  assert_eq(ctx.form_int64("over"), None)
  assert_eq(ctx.form_int64("bad"), None)
  assert_eq(ctx.form_int64("missing"), None)

  let json = @feather.Context::new({
    method: "POST",
    path: "/",
    headers: Map([("Content-Type", "application/json")]),
    body: "{\"id\":42}",
  })
  assert_eq(json.form_int64("id"), None)
}
