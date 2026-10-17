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
