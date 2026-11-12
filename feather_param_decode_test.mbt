///|
fn param_decode_response(
  app : @feather.App,
  path : String,
) -> @feather.Response {
  app.respond({ method: "GET", path, headers: Map([]), body: "", })
}

///|
test "param_decoded decodes percent escapes" {
  let app = @feather.App::new().get("/users/:name", fn(ctx) {
    ctx.text(200, ctx.param_decoded("name"))
  })
  assert_eq(param_decode_response(app, "/users/John%20Doe").body, "John Doe")
}

///|
test "param_decoded keeps plus signs as data" {
  let app = @feather.App::new().get("/tags/:tag", fn(ctx) {
    ctx.text(200, ctx.param_decoded("tag"))
  })
  assert_eq(param_decode_response(app, "/tags/a+b").body, "a+b")
}

///|
test "param_decoded leaves invalid escapes untouched" {
  let app = @feather.App::new().get("/users/:name", fn(ctx) {
    ctx.text(200, ctx.param_decoded("name"))
  })
  assert_eq(param_decode_response(app, "/users/a%zz").body, "a%zz")
  assert_eq(param_decode_response(app, "/users/a%2").body, "a%2")
}

///|
test "param_decoded reports missing parameters as empty" {
  let app = @feather.App::new().get("/users/:name", fn(ctx) {
    ctx.text(200, "<" + ctx.param_decoded("absent") + ">")
  })
  assert_eq(param_decode_response(app, "/users/bob").body, "<>")
}

///|
test "param_decoded decodes wildcard captures" {
  let app = @feather.App::new().get("/static/*path", fn(ctx) {
    ctx.text(200, ctx.param("path") + "|" + ctx.param_decoded("path"))
  })
  assert_eq(
    param_decode_response(app, "/static/css%2Fapp.css").body,
    "css%2Fapp.css|css/app.css",
  )
}

///|
test "typed param accessors decode percent escapes" {
  let app = @feather.App::new()
    .get("/int/:v", fn(ctx) {
      ctx.text(200, ctx.param_int("v").unwrap_or(-1).to_string())
    })
    .get("/long/:v", fn(ctx) {
      ctx.text(200, ctx.param_int64("v").unwrap_or(-1L).to_string())
    })
    .get("/bool/:v", fn(ctx) {
      ctx.text(200, ctx.param_bool("v").unwrap_or(false).to_string())
    })
    .get("/float/:v", fn(ctx) {
      ctx.text(200, ctx.param_float("v").unwrap_or(0.0).to_string())
    })
  assert_eq(param_decode_response(app, "/int/%34%32").body, "42")
  assert_eq(param_decode_response(app, "/long/%39%32").body, "92")
  assert_eq(param_decode_response(app, "/bool/%74rue").body, "true")
  assert_eq(param_decode_response(app, "/float/%31%2E%35").body, "1.5")
}

///|
test "param_default_decoded decodes and falls back" {
  let app = @feather.App::new().get("/items/:id", fn(ctx) {
    let id = ctx.param_default_decoded("id", "none")
    let missing = ctx.param_default_decoded("missing", "fallback")
    ctx.text(200, id + "|" + missing)
  })
  assert_eq(param_decode_response(app, "/items/%41%42").body, "AB|fallback")
  assert_eq(param_decode_response(app, "/items/123").body, "123|fallback")
}

///|
test "param_default_decoded returns empty string for captured empty value" {
  let app = @feather.App::new().get("/*path", fn(ctx) {
    ctx.text(200, "|" + ctx.param_default_decoded("path", "default") + "|")
  })
  assert_eq(param_decode_response(app, "/").body, "||")
  assert_eq(param_decode_response(app, "/a%20b").body, "|a b|")
}
