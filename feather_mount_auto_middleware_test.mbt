///|
fn mount_tag_middleware(name : String, value : String) -> @feather.Middleware {
  fn(next) {
    fn(ctx) raise {
      ctx.set_header(name, value)
      next(ctx)
    }
  }
}

///|
test "mounted middleware wraps automatic OPTIONS and 405 responses" {
  let child = @feather.App::new()
    .use(mount_tag_middleware("X-Child-App", "on"))
    .get("/thing", fn(ctx) { ctx.text(200, "get") })
  let parent = @feather.App::new()
    .mount_with(
      "/api",
      child,
      [mount_tag_middleware("X-Outer", "on")],
    )
  let options = parent.respond({
    method: "OPTIONS",
    path: "/api/thing",
    headers: Map([]),
    body: "",
  })
  assert_eq(options.status, 204)
  assert_eq(options.headers.get("X-Outer"), Some("on"))
  assert_eq(options.headers.get("X-Child-App"), Some("on"))
  let not_allowed = parent.respond({
    method: "POST",
    path: "/api/thing",
    headers: Map([]),
    body: "",
  })
  assert_eq(not_allowed.status, 405)
  assert_eq(not_allowed.headers.get("X-Outer"), Some("on"))
  assert_eq(not_allowed.headers.get("X-Child-App"), Some("on"))
}

///|
test "mounted middleware wraps automatic OPTIONS for async endpoints" {
  let child = @feather.App::new()
    .use(mount_tag_middleware("X-Child-App", "on"))
    .sse("/events", async fn(_ctx, _sse) { () })
  let parent = @feather.App::new()
    .mount_with(
      "/api",
      child,
      [mount_tag_middleware("X-Outer", "on")],
    )
  let options = parent.respond({
    method: "OPTIONS",
    path: "/api/events",
    headers: Map([]),
    body: "",
  })
  assert_eq(options.status, 204)
  assert_eq(options.headers.get("X-Outer"), Some("on"))
  assert_eq(options.headers.get("X-Child-App"), Some("on"))
}

///|
test "nested mounts keep every middleware layer for automatic responses" {
  let grandchild = @feather.App::new()
    .use(mount_tag_middleware("X-Grand-App", "on"))
    .get("/thing", fn(ctx) { ctx.text(200, "grandchild") })
  let child = @feather.App::new()
    .use(mount_tag_middleware("X-Child-App", "on"))
    .mount_with(
      "/deep",
      grandchild,
      [mount_tag_middleware("X-Grand-Outer", "on")],
    )
  let parent = @feather.App::new()
    .mount_with(
      "/api",
      child,
      [mount_tag_middleware("X-Outer", "on")],
    )
  let response = parent.respond({
    method: "DELETE",
    path: "/api/deep/thing",
    headers: Map([]),
    body: "",
  })
  assert_eq(response.status, 405)
  assert_eq(response.headers.get("X-Outer"), Some("on"))
  assert_eq(response.headers.get("X-Child-App"), Some("on"))
  assert_eq(response.headers.get("X-Grand-Outer"), Some("on"))
  assert_eq(response.headers.get("X-Grand-App"), Some("on"))
}
