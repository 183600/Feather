///|
fn cache_control_request(path : String) -> @feather.Request {
  { method: "GET", path, headers: Map([]), body: "", }
}

///|
test "Context cache_control trims directives and removes an empty value" {
  let ctx = @feather.create_context()
  ctx.cache_control("  public, max-age=60, s-maxage=300  ")
  assert_eq(
    ctx.response.headers.get("Cache-Control"),
    Some("public, max-age=60, s-maxage=300"),
  )
  ctx.cache_control("\r\n")
  assert_eq(ctx.response.headers.get("Cache-Control"), None)
}

///|
test "Context cache_control strips control characters from directives" {
  let ctx = @feather.create_context()
  ctx.cache_control("no-store\r\nX-Injected: yes")
  let value = ctx.response.headers.get("Cache-Control").unwrap()
  assert_true(!value.contains("\r"))
  assert_true(!value.contains("\n"))
  assert_true(value.has_prefix("no-store"))
}

///|
test "cache control middleware keeps a handler supplied policy" {
  let app = @feather.App::new()
    .use(@feather.middleware_cache_control("no-store"))
    .get("/items", fn(ctx) {
      ctx.cache_public(60)
      ctx.text(200, "items")
    })
  let response = app.respond(cache_control_request("/items"))
  assert_eq(response.status, 200)
  assert_eq(response.headers.get("Cache-Control"), Some("public, max-age=60"))
}

///|
test "cache control middleware overwrite replaces a handler policy" {
  let app = @feather.App::new()
    .use(@feather.middleware_cache_control("no-store", overwrite=true))
    .get("/items", fn(ctx) {
      ctx.cache_public(60)
      ctx.text(200, "items")
    })
  let response = app.respond(cache_control_request("/items"))
  assert_eq(response.headers.get("Cache-Control"), Some("no-store"))
}

///|
test "cache control convenience middleware installs common policies" {
  let no_store = @feather.App::new()
    .use(@feather.middleware_no_store())
    .get("/private", fn(ctx) { ctx.text(200, "secret") })
  assert_eq(
    no_store.respond(cache_control_request("/private")).headers.get(
      "Cache-Control",
    ),
    Some("no-store"),
  )
  let no_cache = @feather.App::new()
    .use(@feather.middleware_no_cache())
    .get("/fresh", fn(ctx) { ctx.text(200, "fresh") })
  assert_eq(
    no_cache.respond(cache_control_request("/fresh")).headers.get(
      "Cache-Control",
    ),
    Some("no-cache"),
  )
}

///|
test "cache public and private middleware clamp and format max age" {
  let public = @feather.App::new()
    .use(@feather.middleware_cache_public(120, immutable=true))
    .get("/asset", fn(ctx) { ctx.text(200, "asset") })
  assert_eq(
    public.respond(cache_control_request("/asset")).headers.get("Cache-Control"),
    Some("public, max-age=120, immutable"),
  )
  let private = @feather.App::new()
    .use(@feather.middleware_cache_private(-5))
    .get("/account", fn(ctx) { ctx.text(200, "account") })
  assert_eq(
    private.respond(cache_control_request("/account")).headers.get(
      "Cache-Control",
    ),
    Some("private, max-age=0"),
  )
}

///|
test "cache control middleware can be scoped to a path prefix" {
  let app = @feather.App::new()
    .use_prefix("/api", @feather.middleware_cache_public(30))
    .get("/api/items", fn(ctx) { ctx.text(200, "items") })
    .get("/pages/home", fn(ctx) { ctx.text(200, "home") })
  assert_eq(
    app.respond(cache_control_request("/api/items")).headers.get(
      "Cache-Control",
    ),
    Some("public, max-age=30"),
  )
  assert_eq(
    app.respond(cache_control_request("/pages/home")).headers.get(
      "Cache-Control",
    ),
    None,
  )
}

///|
test "cache control middleware leaves an escaping error undecorated" {
  let app = @feather.App::new()
    .use(@feather.middleware_cache_control("public, max-age=60"))
    .get("/boom", fn(_ctx) { raise @feather.HttpError(500, "boom") })
  let response = app.respond(cache_control_request("/boom"))
  assert_eq(response.status, 500)
  assert_eq(response.headers.get("Cache-Control"), None)
}
