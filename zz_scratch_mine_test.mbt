///|
test "dispatch leaves unnamed wildcard out of route params" {
  let router = create_router()
  router.add_route("GET", "/files/*", fn(ctx) { ctx.text(200, "ok") })
  let ctx = Context::new({
    method: "GET",
    path: "/files/a/b.txt",
    headers: Map([]),
    body: "",
  })
  router.dispatch(ctx)
  assert_eq(ctx.response.status, 200)
  assert_eq(ctx.params().length(), 0)
  assert_eq(ctx.param(""), "")
}

///|
test "dispatch binds named wildcard into route params" {
  let router = create_router()
  router.add_route("GET", "/files/*rest", fn(ctx) { ctx.text(200, "ok") })
  let ctx = Context::new({
    method: "GET",
    path: "/files/a/b.txt",
    headers: Map([]),
    body: "",
  })
  router.dispatch(ctx)
  assert_eq(ctx.response.status, 200)
  assert_eq(ctx.param("rest"), "a/b.txt")
  assert_eq(ctx.params().length(), 1)
}
