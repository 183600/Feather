///|
fn route_encoding_get(
  app : @feather.App,
  path : String,
) -> @feather.Response {
  app.respond({ method: "GET", path, headers: Map([]), body: "" })
}

///|
test "url_for percent-encodes static path segments" {
  let app = @feather.App::new()
  ignore(
    app.route_named("cafe", "GET", "/café/:id", fn(ctx) {
      ctx.text(200, ctx.param("id"))
    }),
  )
  assert_eq(
    app.url_for("cafe", params={ "id": "42" }),
    Some("/caf%C3%A9/42"),
  )
  ignore(
    app.route_named("space", "GET", "/hello world/:id", fn(ctx) {
      ctx.text(200, ctx.param("id"))
    }),
  )
  assert_eq(
    app.url_for("space", params={ "id": "42" }),
    Some("/hello%20world/42"),
  )
}

///|
test "percent-encoded static paths match unicode routes" {
  let app = @feather.App::new()
    .get("/café/:id", fn(ctx) { ctx.text(200, ctx.param("id")) })
    .get("/hello world", fn(ctx) { ctx.text(200, "space") })
  assert_eq(route_encoding_get(app, "/caf%C3%A9/42").body, "42")
  assert_eq(route_encoding_get(app, "/caf%c3%a9/42").body, "42")
  assert_eq(route_encoding_get(app, "/café/42").body, "42")
  assert_eq(route_encoding_get(app, "/hello%20world").body, "space")
  assert_eq(route_encoding_get(app, "/hello world").body, "space")
}

///|
test "percent-encoded route registrations are canonicalized" {
  let app = @feather.App::new()
  ignore(
    app.route_named("cafe", "GET", "/caf%C3%A9/:id", fn(ctx) {
      ctx.text(200, ctx.param("id"))
    }),
  )
  assert_eq(
    app.url_for("cafe", params={ "id": "7" }),
    Some("/caf%C3%A9/7"),
  )
  assert_eq(route_encoding_get(app, "/caf%C3%A9/7").body, "7")
  assert_eq(route_encoding_get(app, "/café/7").body, "7")
}

///|
test "url_for encodes literal percent and space and round trips" {
  let app = @feather.App::new()
  ignore(
    app.route_named("discount", "GET", "/discount 100%/:id", fn(ctx) {
      ctx.text(200, ctx.param("id"))
    }),
  )
  let url = app.url_for("discount", params={ "id": "9" })
  assert_eq(url, Some("/discount%20100%25/9"))
  assert_eq(route_encoding_get(app, url.unwrap()).body, "9")
}

///|
test "url_for keeps a registered trailing slash" {
  let app = @feather.App::new()
  ignore(app.route_named("files", "GET", "/files/", fn(ctx) {
    ctx.text(200, "files")
  }))
  assert_eq(app.url_for("files"), Some("/files/"))
  assert_eq(route_encoding_get(app, "/files/").body, "files")
  ignore(app.route_named("root", "GET", "/", fn(ctx) { ctx.text(200, "root") }))
  assert_eq(app.url_for("root"), Some("/"))
  ignore(app.route_named("assets", "GET", "/assets/*path", fn(ctx) {
    ctx.text(200, ctx.param("path"))
  }))
  assert_eq(
    app.url_for("assets", params={ "path": "a/b" }),
    Some("/assets/a/b"),
  )
}

///|
test "static path decoding keeps parameter captures raw" {
  let app = @feather.App::new().get("/p/:id", fn(ctx) {
    ctx.text(200, ctx.param("id") + "|" + ctx.param_decoded("id"))
  })
  assert_eq(route_encoding_get(app, "/p/a%2Fb").body, "a%2Fb|a/b")
}
