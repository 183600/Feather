///|
fn middleware_etag_request(
  path : String,
  headers : Map[String, String],
) -> @feather.Request {
  { method: "GET", path, headers, body: "", }
}

///|
test "etag middleware makes only its scope cacheable" {
  let app = @feather.App::new()
    .use_prefix("/api", @feather.middleware_etag())
    .get("/api/items", fn(ctx) { ctx.json(200, { "item": "one" }) })
    .get("/health", fn(ctx) { ctx.text(200, "ok") })
  let first = app.respond(middleware_etag_request("/api/items", Map([])))
  assert_eq(first.status, 200)
  let etag = match first.headers.get("ETag") {
    Some(etag) => etag
    None => fail("missing generated ETag")
  }
  let second = app.respond(
    middleware_etag_request("/api/items", Map([("If-None-Match", etag)])),
  )
  assert_eq(second.status, 304)
  assert_eq(second.body, "")
  assert_eq(second.headers.get("ETag"), Some(etag))
  let health = app.respond(middleware_etag_request("/health", Map([])))
  assert_eq(health.headers.get("ETag"), None)
}

///|
test "etag middleware keeps explicit validators and opt outs" {
  let app = @feather.App::new()
    .use(@feather.middleware_etag())
    .get("/manual", fn(ctx) {
      ctx.set_header("ETag", "\"manual\"")
      ctx.text(200, "body")
    })
    .get("/skip", fn(ctx) {
      ctx.no_etag()
      ctx.text(200, "body")
    })
    .get("/private", fn(ctx) {
      ctx.no_store()
      ctx.text(200, "body")
    })
  assert_eq(
    app.respond(middleware_etag_request("/manual", Map([])))
      .headers.get("ETag"),
    Some("\"manual\""),
  )
  assert_eq(
    app.respond(middleware_etag_request("/skip", Map([])))
      .headers.get("ETag"),
    None,
  )
  assert_eq(
    app.respond(middleware_etag_request("/private", Map([])))
      .headers.get("ETag"),
    None,
  )
}

///|
test "etag middleware works on a single route" {
  let app = @feather.App::new()
    .route_with(
      "GET",
      "/cached",
      [@feather.middleware_etag()],
      fn(ctx) { ctx.text(200, "cached") },
    )
    .get("/plain", fn(ctx) { ctx.text(200, "plain") })
  assert_true(
    app.respond(middleware_etag_request("/cached", Map([])))
      .headers.get("ETag")
      is Some(_),
  )
  assert_eq(
    app.respond(middleware_etag_request("/plain", Map([])))
      .headers.get("ETag"),
    None,
  )
}
