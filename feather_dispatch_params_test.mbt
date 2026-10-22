///|
test "re-dispatching a context clears parameters from the previous route" {
  let router = @feather.create_router()
  router.add_route("GET", "/items/:id", fn(ctx) { ctx.text(200, "get") })
  router.add_route("POST", "/items/:slug", fn(ctx) {
    ctx.text(200, "slug=" + ctx.param("slug") + ",id=" + ctx.param("id"))
  })
  let ctx = @feather.Context::new({
    method: "GET",
    path: "/items/42",
    headers: Map([]),
    body: "",
  })
  router.dispatch(ctx)
  assert_eq(ctx.param("id"), "42")
  ctx.request.method = "POST"
  router.dispatch(ctx)
  assert_eq(ctx.param("slug"), "42")
  assert_eq(ctx.param("id"), "")
  assert_eq(ctx.response.body, "slug=42,id=")
}

///|
test "re-dispatching into the fallback exposes no stale parameter" {
  let router = @feather.create_router()
  router.add_route("GET", "/items/:id", fn(ctx) { ctx.text(200, "get") })
  let ctx = @feather.Context::new({
    method: "GET",
    path: "/items/42",
    headers: Map([]),
    body: "",
  })
  router.dispatch(ctx)
  let empty = @feather.create_router()
  empty.dispatch_with(ctx, Some(fn(ctx) {
    ctx.text(404, "<" + ctx.param("id") + ">")
  }))
  assert_eq(ctx.response.status, 404)
  assert_eq(ctx.response.body, "<>")
}
