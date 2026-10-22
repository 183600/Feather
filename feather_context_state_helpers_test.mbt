///|
test "request state presence distinguishes empty values" {
  let ctx = @feather.create_context()
  assert_false(ctx.has_state("flag"))
  assert_false(ctx.remove_state("flag"))
  ctx.set("flag", "")
  assert_true(ctx.has_state("flag"))
  assert_eq(ctx.get("flag"), "")
  assert_true(ctx.remove_state("flag"))
  assert_false(ctx.has_state("flag"))
  assert_false(ctx.remove_state("flag"))
}

///|
test "request json state presence distinguishes stored null" {
  let ctx = @feather.create_context()
  assert_false(ctx.has_json_state("box"))
  assert_false(ctx.remove_json_state("box"))
  ctx.set_json("box", Json::null())
  assert_true(ctx.has_json_state("box"))
  assert_true(ctx.get_json("box") is Some(_))
  assert_true(ctx.remove_json_state("box"))
  assert_false(ctx.has_json_state("box"))
  assert_true(ctx.get_json("box") is None)
  assert_false(ctx.remove_json_state("box"))
}

///|
test "removing request state leaves application state intact" {
  let app = @feather.App::new()
    .set_state("tenant", "default")
    .set_json_state("limits", Json::number(10.0))
  let ctx = @feather.Context::new({
    method: "GET",
    path: "/",
    headers: Map([]),
    body: "",
  })
  app.handle(ctx)
  assert_true(ctx.has_state("tenant"))
  assert_true(ctx.has_json_state("limits"))
  assert_true(ctx.remove_state("tenant"))
  assert_true(ctx.remove_json_state("limits"))
  assert_false(ctx.has_state("tenant"))
  assert_false(ctx.has_json_state("limits"))
  assert_eq(app.get_state("tenant"), "default")
  assert_true(app.get_json_state("limits") is Some(_))
}
