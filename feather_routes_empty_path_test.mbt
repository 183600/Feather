///|
test "Router routes lists a route registered at the empty path" {
  let router = @feather.create_router()
  router.add_route("GET", "", fn(ctx) { ctx.text(200, "ok") })
  assert_true(router.route("GET", "") is @feather.RouteFound(_))
  assert_eq(router.routes().length(), 1)
  assert_eq(router.routes()[0], ("GET", ""))
}
