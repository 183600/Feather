///|
test "Context float and form typed accessors" {
  let router = @feather.create_router()
  router.add_route("POST", "/items/:price/:flag", fn(ctx) { ctx.text(200, "ok") })
  let ctx = @feather.Context::new({
    method: "POST",
    path: "/items/12.5/true?ratio=2.25&bad=abc&nan=nan&inf=inf&big=1e309&neg=-0.5",
    headers: Map([("Content-Type", "application/x-www-form-urlencoded")]),
    body: "count=3&enabled=true&ratio=1.25&bad=abc&nan=nan",
  })
  router.dispatch(ctx)
  assert_eq(ctx.param_float("price"), Some(12.5))
  assert_eq(ctx.param_float("flag"), None)
  assert_eq(ctx.param_float("missing"), None)
  assert_eq(ctx.query_float("ratio"), Some(2.25))
  assert_eq(ctx.query_float("neg"), Some(-0.5))
  assert_eq(ctx.query_float("bad"), None)
  assert_eq(ctx.query_float("nan"), None)
  assert_eq(ctx.query_float("inf"), None)
  assert_eq(ctx.query_float("big"), None)
  assert_eq(ctx.query_float("missing"), None)
  assert_eq(ctx.form_int("count"), Some(3))
  assert_eq(ctx.form_bool("enabled"), Some(true))
  assert_eq(ctx.form_float("ratio"), Some(1.25))
  assert_eq(ctx.form_int("ratio"), None)
  assert_eq(ctx.form_bool("count"), None)
  assert_eq(ctx.form_float("bad"), None)
  assert_eq(ctx.form_float("nan"), None)
  assert_eq(ctx.form_int("missing"), None)
}

///|
test "form typed accessors ignore non-form bodies" {
  let ctx = @feather.Context::new({
    method: "POST",
    path: "/",
    headers: Map([("Content-Type", "application/json")]),
    body: "{\"count\":3}",
  })
  assert_eq(ctx.form_int("count"), None)
  assert_eq(ctx.form_bool("count"), None)
  assert_eq(ctx.form_float("count"), None)
}
