///|
fn cache_control_ctx() -> @feather.Context {
  @feather.Context::new({ method: "GET", path: "/", headers: Map([]), body: "" })
}

///|
test "cache_public writes a shared cache policy" {
  let ctx = cache_control_ctx()
  ctx.cache_public(60)
  assert_eq(ctx.response.headers.get("Cache-Control"), Some("public, max-age=60"))
  ctx.cache_public(120, immutable=true)
  assert_eq(
    ctx.response.headers.get("Cache-Control"),
    Some("public, max-age=120, immutable"),
  )
}

///|
test "cache_private writes a private cache policy" {
  let ctx = cache_control_ctx()
  ctx.cache_private(30)
  assert_eq(
    ctx.response.headers.get("Cache-Control"),
    Some("private, max-age=30"),
  )
  ctx.cache_private(0, immutable=true)
  assert_eq(
    ctx.response.headers.get("Cache-Control"),
    Some("private, max-age=0, immutable"),
  )
}

///|
test "cache helpers clamp negative lifetimes to zero" {
  let ctx = cache_control_ctx()
  ctx.cache_public(-5)
  assert_eq(ctx.response.headers.get("Cache-Control"), Some("public, max-age=0"))
  ctx.cache_private(-1)
  assert_eq(
    ctx.response.headers.get("Cache-Control"),
    Some("private, max-age=0"),
  )
}

///|
test "no_store and no_cache replace an existing cache policy" {
  let ctx = cache_control_ctx()
  ctx.cache_public(60)
  ctx.no_store()
  assert_eq(ctx.response.headers.get("Cache-Control"), Some("no-store"))
  ctx.no_cache()
  assert_eq(ctx.response.headers.get("Cache-Control"), Some("no-cache"))
}

///|
test "cache-control helpers are visible through the offline facade" {
  let app = @feather.App::new()
    .get("/public", fn(ctx) {
      ctx.cache_public(300, immutable=true)
      ctx.text(200, "ok")
    })
    .get("/private", fn(ctx) {
      ctx.cache_private(10)
      ctx.text(200, "ok")
    })
  let public = app.respond({
    method: "GET",
    path: "/public",
    headers: Map([]),
    body: "",
  })
  assert_eq(
    public.headers.get("Cache-Control"),
    Some("public, max-age=300, immutable"),
  )
  let private = app.respond({
    method: "GET",
    path: "/private",
    headers: Map([]),
    body: "",
  })
  assert_eq(
    private.headers.get("Cache-Control"),
    Some("private, max-age=10"),
  )
}
