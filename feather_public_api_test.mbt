///|
fn api_ctx(method : String, path : String) -> @feather.Context {
  @feather.Context::new({
    method,
    path,
    headers: Map([]),
    body: "",
  })
}

///|
test "url_decode handles plus, percent escapes and malformed input" {
  assert_eq(@feather.url_decode("hello+world"), "hello world")
  assert_eq(@feather.url_decode("%E4%B8%AD%E6%96%87"), "中文")
  assert_eq(@feather.url_decode("a%2Fb"), "a/b")
  assert_eq(@feather.url_decode("100%25%20done"), "100% done")
  assert_eq(@feather.url_decode("%zz"), "%zz")
  assert_eq(@feather.url_decode("plain"), "plain")
}

///|
test "parse_urlencoded splits pairs and keeps later duplicates" {
  let fields = @feather.parse_urlencoded("a=1&b=hello+world&flag&a=2=3")
  assert_eq(fields.get("a"), Some("2=3"))
  assert_eq(fields.get("b"), Some("hello world"))
  assert_eq(fields.get("flag"), Some(""))
  assert_eq(@feather.parse_urlencoded("").length(), 0)
}

///|
test "multipart_boundary reads quoted and bare boundary parameters" {
  assert_eq(
    @feather.multipart_boundary("multipart/form-data; boundary=abc"),
    Some("abc"),
  )
  assert_eq(
    @feather.multipart_boundary("multipart/form-data; boundary=\"x y\""),
    Some("x y"),
  )
  assert_eq(
    @feather.multipart_boundary("Multipart/Form-Data; Boundary=Q"),
    Some("Q"),
  )
  assert_eq(@feather.multipart_boundary("text/plain"), None)
  assert_eq(@feather.multipart_boundary("multipart/form-data"), None)
}

///|
test "json_object stringifies string keyed objects" {
  let json = @feather.json_object(Map([("ok", "true")]))
  assert_eq(json.stringify(), "{\"ok\":\"true\"}")
}

///|
test "not_found fills a plain 404 response" {
  let ctx = api_ctx("GET", "/nope")
  @feather.not_found(ctx)
  assert_eq(ctx.response.status, 404)
  assert_eq(ctx.response.body, "404 Not Found")
  assert_eq(
    ctx.response.headers.get("Content-Type"),
    Some("text/plain; charset=utf-8"),
  )
  assert_true(ctx.response.data is None)
}

///|
test "method_not_allowed lists implicit HEAD" {
  let ctx = api_ctx("DELETE", "/thing")
  @feather.method_not_allowed(ctx, ["GET"])
  assert_eq(ctx.response.status, 405)
  assert_eq(ctx.response.headers.get("Allow"), Some("GET, HEAD"))
  assert_eq(ctx.response.body, "405 Method Not Allowed")
}

///|
test "respond_options answers 204 with a sorted Allow header" {
  let ctx = api_ctx("OPTIONS", "/thing")
  @feather.respond_options(ctx, ["POST", "GET"])
  assert_eq(ctx.response.status, 204)
  assert_eq(ctx.response.headers.get("Allow"), Some("GET, HEAD, POST"))
  assert_eq(ctx.response.body, "")
}

///|
test "internal_error keeps the detail in state" {
  let ctx = api_ctx("GET", "/boom")
  @feather.internal_error(ctx, "database down")
  assert_eq(ctx.response.status, 500)
  assert_eq(ctx.response.body, "Internal Server Error")
  assert_eq(ctx.state.get("error"), Some("database down"))
}

///|
test "error_response emits a json error document" {
  let ctx = api_ctx("GET", "/missing")
  @feather.error_response(ctx, 404, "not here")
  assert_eq(ctx.response.status, 404)
  assert_eq(
    ctx.response.headers.get("Content-Type"),
    Some("application/json; charset=utf-8"),
  )
  assert_true(ctx.response.body.contains("\"error\":\"not here\""))
  assert_true(ctx.response.body.contains("\"status\":404"))
}

///|
test "error_response_with_payload merges object payloads" {
  let ctx = api_ctx("POST", "/form")
  @feather.error_response_with_payload(
    ctx,
    422,
    "invalid",
    Json::object(Map([("field", Json::string("email"))])),
  )
  assert_eq(ctx.response.status, 422)
  assert_true(ctx.response.body.contains("\"field\":\"email\""))
  assert_true(ctx.response.body.contains("\"error\":\"invalid\""))

  let plain = api_ctx("POST", "/form")
  @feather.error_response_with_payload(plain, 400, "bad", Json::string("hint"))
  assert_true(plain.response.body.contains("\"detail\":\"hint\""))
}

///|
test "Context::html sets the html content type" {
  let ctx = api_ctx("GET", "/page")
  ctx.html(200, "<h1>hi</h1>")
  assert_eq(ctx.response.status, 200)
  assert_eq(
    ctx.response.headers.get("Content-Type"),
    Some("text/html; charset=utf-8"),
  )
  assert_eq(ctx.response.body, "<h1>hi</h1>")
  assert_true(ctx.response.data is None)
}

///|
test "Router::dispatch_with runs the fallback only when nothing matches" {
  let router = @feather.create_router()
  router.add_route("GET", "/hello", fn(ctx) { ctx.text(200, "hi") })
  let hit = api_ctx("GET", "/hello")
  router.dispatch_with(hit, Some(fn(ctx) { ctx.text(418, "fallback") }))
  assert_eq(hit.response.status, 200)
  assert_eq(hit.response.body, "hi")
  let miss = api_ctx("GET", "/missing")
  router.dispatch_with(miss, Some(fn(ctx) { ctx.text(418, "fallback") }))
  assert_eq(miss.response.status, 418)
  assert_eq(miss.response.body, "fallback")
  let bare = api_ctx("GET", "/missing")
  router.dispatch_with(bare, None)
  assert_eq(bare.response.status, 404)
}

///|
test "static_cache_control_for follows the matching mount max_age" {
  let app = @feather.App::new()
    .static_files("/assets", "/tmp/feather-public-api", max_age=3600)
    .static_files("/media", "/tmp/feather-public-api")
  assert_eq(
    app.static_cache_control_for("/assets/app.css"),
    "public, max-age=3600",
  )
  assert_eq(app.static_cache_control_for("/media/logo.png"), "")
  assert_eq(app.static_cache_control_for("/elsewhere"), "")
}
