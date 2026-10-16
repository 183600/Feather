// Tests for Feather features: URL helpers, error model, route groups, static files.

///|
test "url_encode keeps unreserved characters" {
  assert_eq(@feather.url_encode("abcXYZ012-._~"), "abcXYZ012-._~")
}

///|
test "url_encode escapes reserved characters" {
  assert_eq(@feather.url_encode("a b/c?d=e&f"), "a%20b%2Fc%3Fd%3De%26f")
}

///|
test "url_encode escapes utf8 bytes" {
  assert_eq(@feather.url_encode("世"), "%E4%B8%96")
}

///|
test "mime_type_for common extensions" {
  assert_eq(@feather.mime_type_for("index.html"), "text/html; charset=utf-8")
  assert_eq(@feather.mime_type_for("app.CSS"), "text/css; charset=utf-8")
  assert_eq(@feather.mime_type_for("main.js"), "text/javascript; charset=utf-8")
  assert_eq(
    @feather.mime_type_for("data.json"),
    "application/json; charset=utf-8",
  )
  assert_eq(@feather.mime_type_for("image.png"), "image/png")
  assert_eq(@feather.mime_type_for("archive.tar.gz"), "application/gzip")
  assert_eq(@feather.mime_type_for("noext"), "application/octet-stream")
}

///|
test "Router url_for builds parameterized path" {
  let router = @feather.create_router()
  router.add_named_route("user", "GET", "/users/:id", fn(ctx) {
    ctx.text(200, "u")
  })
  assert_eq(router.url_for("user", params={ "id": "42" }), Some("/users/42"))
}

///|
test "Router url_for encodes parameter values" {
  let router = @feather.create_router()
  router.add_named_route("search", "GET", "/search/:term", fn(ctx) {
    ctx.text(200, "s")
  })
  assert_eq(
    router.url_for("search", params={ "term": "hello world" }),
    Some("/search/hello%20world"),
  )
}

///|
test "Router url_for fails on unknown name or missing param" {
  let router = @feather.create_router()
  router.add_named_route("user", "GET", "/users/:id", fn(ctx) {
    ctx.text(200, "u")
  })
  assert_eq(router.url_for("missing", params={ "id": "1" }), None)
  assert_eq(router.url_for("user", params={ "other": "1" }), None)
}

///|
test "Router url_for handles wildcard and static names" {
  let router = @feather.create_router()
  router.add_named_route("file", "GET", "/files/*path", fn(ctx) {
    ctx.text(200, "f")
  })
  router.add_named_route("home", "GET", "/", fn(ctx) { ctx.text(200, "h") })
  assert_eq(
    router.url_for("file", params={ "path": "a/b.txt" }),
    Some("/files/a/b.txt"),
  )
  assert_eq(router.url_for("home"), Some("/"))
}

///|
test "App groups prefix routes and apply group middleware" {
  let order : Array[String] = []
  let app = @feather.App::new()
  let api = app.group("/api")
  ignore(
    api.use(fn(next) {
      fn(ctx) raise {
        order.push("group")
        next(ctx)
      }
    }),
  )
  ignore(
    api.get("/users", fn(ctx) {
      order.push("handler")
      ctx.text(200, "users")
    }),
  )
  let response = app.respond({
    method: "GET",
    path: "/api/users",
    headers: Map([]),
    body: "",
  })
  assert_eq(response.status, 200)
  assert_eq(response.body, "users")
  assert_eq(order.join(","), "group,handler")
  let miss = app.respond({
    method: "GET",
    path: "/users",
    headers: Map([]),
    body: "",
  })
  assert_eq(miss.status, 404)
}

///|
test "App nested groups join prefixes" {
  let app = @feather.App::new()
  let v1 = app.group("/api").group("v1")
  ignore(v1.get("/ping", fn(ctx) { ctx.text(200, "pong") }))
  let response = app.respond({
    method: "GET",
    path: "/api/v1/ping",
    headers: Map([]),
    body: "",
  })
  assert_eq(response.body, "pong")
}

///|
test "group named routes generate urls" {
  let app = @feather.App::new()
  ignore(
    app
    .group("/api")
    .route_named("api_user", "GET", "/users/:id", fn(ctx) { ctx.text(200, "u") }),
  )
  assert_eq(app.url_for("api_user", params={ "id": "7" }), Some("/api/users/7"))
}

///|
test "app middleware wraps group middleware" {
  let order : Array[String] = []
  let app = @feather.App::new().use(fn(next) {
    fn(ctx) raise {
      order.push("app")
      next(ctx)
      order.push("app_end")
    }
  })
  let group = app
    .group("/g")
    .use(fn(next) {
      fn(ctx) raise {
        order.push("group")
        next(ctx)
        order.push("group_end")
      }
    })
  ignore(
    group.get("/x", fn(ctx) {
      order.push("handler")
      ctx.text(200, "x")
    }),
  )
  let response = app.respond({
    method: "GET",
    path: "/g/x",
    headers: Map([]),
    body: "",
  })
  assert_eq(response.status, 200)
  assert_eq(order.join(","), "app,group,handler,group_end,app_end")
}

///|
test "HttpError produces json error response" {
  let app = @feather.App::new().get("/missing", fn(ctx) raise {
    ctx.fail(404, "user not found")
  })
  let response = app.respond({
    method: "GET",
    path: "/missing",
    headers: Map([]),
    body: "",
  })
  assert_eq(response.status, 404)
  assert_eq(
    response.headers.get("Content-Type"),
    Some("application/json; charset=utf-8"),
  )
  assert_true(response.body.contains("user not found"))
  assert_true(response.body.contains("404"))
}

///|
test "middleware_error_handler renders generic errors as json 500" {
  let app = @feather.App::new()
    .use(@feather.middleware_error_handler())
    .get("/boom", fn(_ctx) raise { raise Failure("kaboom") })
  let response = app.respond({
    method: "GET",
    path: "/boom",
    headers: Map([]),
    body: "",
  })
  assert_eq(response.status, 500)
  assert_true(response.body.contains("kaboom"))
}

///|
test "middleware_recover maps HttpError status" {
  let app = @feather.App::new()
    .use(@feather.middleware_recover())
    .get("/no", fn(ctx) raise { ctx.fail(401, "unauthorized") })
  let response = app.respond({
    method: "GET",
    path: "/no",
    headers: Map([]),
    body: "",
  })
  assert_eq(response.status, 401)
  assert_true(response.body.contains("unauthorized"))
}

///|
test "Context json_body parses request body" {
  let app = @feather.App::new().post("/echo", fn(ctx) raise {
    let data = ctx.json_body()
    let name = if data is Object(object) {
      match object.get("name") {
        Some(String(name)) => name
        _ => ""
      }
    } else {
      ""
    }
    ctx.text(200, name)
  })
  let response = app.respond({
    method: "POST",
    path: "/echo",
    headers: Map([]),
    body: "{\"name\":\"feather\"}",
  })
  assert_eq(response.status, 200)
  assert_eq(response.body, "feather")
}

///|
test "Context json_as decodes typed body" {
  let app = @feather.App::new().post("/sum", fn(ctx) {
    let numbers : Array[Int32] = ctx.json_as() catch {
      _ => {
        ctx.text(400, "bad")
        return
      }
    }
    let mut sum = 0
    for n in numbers {
      sum = sum + n
    }
    ctx.text(200, sum.to_string())
  })
  let response = app.respond({
    method: "POST",
    path: "/sum",
    headers: Map([]),
    body: "[1,2,3]",
  })
  assert_eq(response.body, "6")
  let bad = app.respond({
    method: "POST",
    path: "/sum",
    headers: Map([]),
    body: "not json",
  })
  assert_eq(bad.status, 400)
}

///|
test "invalid json body becomes 400 through HttpError" {
  let app = @feather.App::new().post("/data", fn(ctx) raise {
    ignore(ctx.json_body())
    ctx.text(200, "ok")
  })
  let response = app.respond({
    method: "POST",
    path: "/data",
    headers: Map([]),
    body: "{",
  })
  assert_eq(response.status, 400)
  assert_true(response.body.contains("invalid JSON body"))
}

///|
test "static_file_for resolves files and rejects traversal" {
  let app = @feather.App::new().static_files("/assets", "/srv/public")
  assert_eq(app.static_file_for("/assets/app.css"), Some("/srv/public/app.css"))
  assert_eq(
    app.static_file_for("/assets/nested/app.js"),
    Some("/srv/public/nested/app.js"),
  )
  assert_eq(app.static_file_for("/assets/"), Some("/srv/public/index.html"))
  assert_eq(app.static_file_for("/assets"), Some("/srv/public/index.html"))
  assert_eq(app.static_file_for("/assets/../secret"), None)
  assert_eq(app.static_file_for("/assets/a/../../secret"), None)
  assert_eq(app.static_file_for("/assets/a\\b"), None)
  assert_eq(app.static_file_for("/other/app.css"), None)
}

///|
test "static_file_for picks the longest matching prefix" {
  let app = @feather.App::new()
    .static_files("/", "/srv/www")
    .static_files("/img", "/srv/images")
  assert_eq(app.static_file_for("/img/logo.png"), Some("/srv/images/logo.png"))
  assert_eq(app.static_file_for("/app.css"), Some("/srv/www/app.css"))
}

///|
test "custom static index name is honored" {
  let app = @feather.App::new().static_files(
    "/docs",
    "/srv/docs",
    index="home.html",
  )
  assert_eq(app.static_file_for("/docs/"), Some("/srv/docs/home.html"))
}

///|
test "App fallback handles unmatched routes" {
  let app = @feather.App::new()
    .get("/known", fn(ctx) { ctx.text(200, "known") })
    .fallback(fn(_ctx) raise { raise @feather.HttpError(404, "custom missing") })
  let response = app.respond({
    method: "GET",
    path: "/unknown",
    headers: Map([]),
    body: "",
  })
  assert_eq(response.status, 404)
  assert_true(response.body.contains("custom missing"))
  let known = app.respond({
    method: "GET",
    path: "/known",
    headers: Map([]),
    body: "",
  })
  assert_eq(known.body, "known")
}

///|
test "App fallback does not swallow method not allowed" {
  let app = @feather.App::new()
    .get("/r", fn(ctx) { ctx.text(200, "g") })
    .fallback(fn(ctx) { ctx.text(404, "fallback") })
  let response = app.respond({
    method: "POST",
    path: "/r",
    headers: Map([]),
    body: "",
  })
  assert_eq(response.status, 405)
}

///|
test "App all registers every verb" {
  let app = @feather.App::new().all("/any", fn(ctx) {
    ctx.text(200, ctx.get_method())
  })
  for meth in ["GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"] {
    let response = app.respond({
      method: meth,
      path: "/any",
      headers: Map([]),
      body: "",
    })
    assert_eq(response.status, 200)
    assert_eq(response.body, meth)
  }
}

///|
test "Feather validate_body_size uses app max body size" {
  let config : @feather.Config = { host: "localhost", port: 8080, timeout: 0, }
  let feather = @feather.create_feather(config)
  ignore(feather.app.max_body_size(10))
  assert_true(feather.validate_body_size("1234567890"))
  assert_eq(feather.validate_body_size("12345678901"), false)
}

///|
async test "server maps HttpError to json status" {
  let app = @feather.App::new().get("/missing", fn(ctx) raise {
    ctx.fail(404, "not here")
  })
  with_server(app, client => {
    let response = client.get("/missing")
    assert_eq(response.code, 404)
    assert_true(client.read_all().text().contains("not here"))
  })
}

///|
async test "server uses fallback for unknown routes" {
  let app = @feather.App::new()
    .get("/known", fn(ctx) { ctx.text(200, "known") })
    .fallback(fn(ctx) { ctx.text(404, "custom 404") })
  with_server(app, client => {
    let response = client.get("/unknown")
    assert_eq(response.code, 404)
    assert_eq(client.read_all().text(), "custom 404")
  })
}

///|
async test "server streams static files with content type" {
  let dir = @fs.tmpdir(prefix="feather-static")
  @fs.write_file(dir + "/app.css", "body { color: red; }")
  let app = @feather.App::new().static_files("/assets", dir)
  with_server(app, client => {
    let response = client.get("/assets/app.css")
    assert_eq(response.code, 200)
    assert_eq(
      response.headers.get(@http.CaseInsensitiveString("Content-Type")),
      Some("text/css; charset=utf-8"),
    )
    assert_eq(client.read_all().text(), "body { color: red; }")
  })
  @fs.rmdir(dir, recursive=true)
}

///|
async test "server serves static index for directory requests" {
  let dir = @fs.tmpdir(prefix="feather-static")
  @fs.write_file(dir + "/index.html", "<h1>home</h1>")
  let app = @feather.App::new().static_files("/site", dir)
  with_server(app, client => {
    let response = client.get("/site/")
    assert_eq(response.code, 200)
    assert_eq(
      response.headers.get(@http.CaseInsensitiveString("Content-Type")),
      Some("text/html; charset=utf-8"),
    )
    assert_eq(client.read_all().text(), "<h1>home</h1>")
  })
  @fs.rmdir(dir, recursive=true)
}

///|
async test "server returns 404 for missing static file" {
  let dir = @fs.tmpdir(prefix="feather-static")
  let app = @feather.App::new().static_files("/assets", dir)
  with_server(app, client => {
    let response = client.get("/assets/missing.txt")
    assert_eq(response.code, 404)
    assert_eq(client.read_all().text(), "404 Not Found")
  })
  @fs.rmdir(dir, recursive=true)
}

///|
async test "server answers head requests for static files" {
  let dir = @fs.tmpdir(prefix="feather-static")
  @fs.write_file(dir + "/data.json", "{\"ok\":true}")
  let app = @feather.App::new().static_files("/assets", dir)
  with_server(app, client => {
    client.request(@http.RequestMethod::Head, "/assets/data.json")
    let response = client.end_request()
    assert_eq(response.code, 200)
    assert_eq(
      response.headers.get(@http.CaseInsensitiveString("Content-Type")),
      Some("application/json; charset=utf-8"),
    )
    assert_eq(client.read_all().text(), "")
  })
  @fs.rmdir(dir, recursive=true)
}

///|
async test "server still routes app handlers next to static mounts" {
  let dir = @fs.tmpdir(prefix="feather-static")
  @fs.write_file(dir + "/app.js", "console.log(1)")
  let app = @feather.App::new()
    .static_files("/assets", dir)
    .get("/api/hello", fn(ctx) { ctx.text(200, "hello") })
  with_server(app, client => {
    let static_response = client.get("/assets/app.js")
    assert_eq(static_response.code, 200)
    assert_eq(client.read_all().text(), "console.log(1)")
    let api_response = client.get("/api/hello")
    assert_eq(api_response.code, 200)
    assert_eq(client.read_all().text(), "hello")
  })
  @fs.rmdir(dir, recursive=true)
}
