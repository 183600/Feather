///|
test "scoped middleware on a wildcard mount sees the child-relative path" {
  let child = @feather.App::new()
    .use_prefix("/api", fn(next) {
      fn(ctx) raise {
        ctx.set_header("X-Scoped", "yes")
        next(ctx)
      }
    })
    .get("/*", fn(ctx) { ctx.text(200, "child") })
  let parent = @feather.App::new().mount("/*rest", child)
  let inside = parent.respond({
    method: "GET",
    path: "/api/users",
    headers: Map([]),
    body: "",
  })
  assert_eq(inside.status, 200)
  assert_eq(inside.body, "child")
  assert_eq(inside.headers.get("X-Scoped"), Some("yes"))
  let outside = parent.respond({
    method: "GET",
    path: "/other",
    headers: Map([]),
    body: "",
  })
  assert_eq(outside.status, 200)
  assert_eq(outside.body, "child")
  assert_eq(outside.headers.get("X-Scoped"), None)
}
