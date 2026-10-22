///|
test "dynamic mount keeps its middleware and params on automatic OPTIONS and 405" {
  let child = @feather.App::new()
    .use(fn(next) {
      fn(ctx) raise {
        ctx.set_header("X-Child", "on")
        ctx.set_header("X-Tenant", ctx.param("id"))
        next(ctx)
      }
    })
    .get("/thing", fn(ctx) { ctx.text(200, "get") })
  let parent = @feather.App::new().mount("/tenant/:id", child)
  let not_allowed = parent.respond({
    method: "POST",
    path: "/tenant/acme/thing",
    headers: Map([]),
    body: "",
  })
  assert_eq(not_allowed.status, 405)
  assert_eq(not_allowed.headers.get("X-Child"), Some("on"))
  assert_eq(not_allowed.headers.get("X-Tenant"), Some("acme"))
  let options = parent.respond({
    method: "OPTIONS",
    path: "/tenant/acme/thing",
    headers: Map([]),
    body: "",
  })
  assert_eq(options.status, 204)
  assert_eq(options.headers.get("X-Child"), Some("on"))
  assert_eq(options.headers.get("X-Tenant"), Some("acme"))
}

///|
test "dynamic mount prefixes resolve static files and encode their params" {
  let child = @feather.App::new().static_files("/assets", "/srv/public")
  let parent = @feather.App::new().mount("/tenant/:id", child)
  assert_eq(
    parent.static_file_for("/tenant/acme/assets/app.js"),
    Some("/srv/public/app.js"),
  )
  assert_eq(
    parent.static_file_for("/tenant/acme/assets"),
    Some("/srv/public/index.html"),
  )
  assert_eq(
    parent.static_file_for("/ten%61nt/acme/assets/app.js"),
    Some("/srv/public/app.js"),
  )
}

///|
async test "dynamic mount static files bind mount params for middleware" {
  let dir = @fs.tmpdir(prefix="feather-dynamic-static")
  @fs.write_file(dir + "/app.js", "console.log(1)")
  @fs.write_file(dir + "/index.html", "<h1>home</h1>")
  let child = @feather.App::new()
    .use(fn(next) {
      fn(ctx) raise {
        ctx.set_header("X-Tenant", ctx.param("id"))
        next(ctx)
      }
    })
    .static_files("/assets", dir)
  let parent = @feather.App::new().mount("/tenant/:id", child)
  with_server(parent, client => {
    let response = client.get("/tenant/acme/assets/app.js")
    assert_eq(response.code, 200)
    assert_eq(
      response.headers.get(@http.CaseInsensitiveString("X-Tenant")),
      Some("acme"),
    )
    assert_eq(client.read_all().text(), "console.log(1)")
    let redirect = client.get("/tenant/acme/assets")
    assert_eq(redirect.code, 301)
    assert_eq(
      redirect.headers.get(@http.CaseInsensitiveString("Location")),
      Some("/tenant/acme/assets/"),
    )
    ignore(client.read_all())
    let index = client.get("/tenant/acme/assets/")
    assert_eq(index.code, 200)
    assert_eq(client.read_all().text(), "<h1>home</h1>")
  })
  @fs.rmdir(dir, recursive=true)
}

///|
test "server-wide OPTIONS sees equivalent WebSocket route patterns" {
  let parameter_shadow = @feather.App::new()
    .get("/foo/:name", fn(ctx) { ctx.text(200, "get") })
    .websocket("/foo/:id", fn(_ctx, _ws) { () })
  assert_eq(
    parameter_shadow
    .respond({ method: "OPTIONS", path: "*", headers: Map([]), body: "" })
    .headers.get("Allow"),
    Some("GET, OPTIONS"),
  )
  let static_shadow = @feather.App::new()
    .get("/foo/bar", fn(ctx) { ctx.text(200, "get") })
    .websocket("/foo/:id", fn(_ctx, _ws) { () })
  assert_eq(
    static_shadow
    .respond({ method: "OPTIONS", path: "*", headers: Map([]), body: "" })
    .headers.get("Allow"),
    Some("GET, OPTIONS"),
  )
}

///|
test "server-wide OPTIONS drops HEAD for a WebSocket-shadowed SSE route" {
  let app = @feather.App::new()
    .sse("/events", async fn(_ctx, sse) { sse.close() })
    .websocket("/events", fn(_ctx, _ws) { () })
  let response = app.respond({
    method: "OPTIONS",
    path: "*",
    headers: Map([]),
    body: "",
  })
  assert_eq(response.headers.get("Allow"), Some("GET, OPTIONS"))
}

///|
test "server-wide OPTIONS drops a WebSocket-shadowed explicit HEAD route" {
  let app = @feather.App::new()
    .head("/ws", fn(ctx) { ctx.text(200, "head") })
    .websocket("/ws", fn(_ctx, _ws) { () })
  let response = app.respond({
    method: "OPTIONS",
    path: "*",
    headers: Map([]),
    body: "",
  })
  assert_eq(response.headers.get("Allow"), Some("GET, OPTIONS"))
}

///|
test "server-wide OPTIONS keeps HEAD for a partially shadowed wildcard route" {
  let app = @feather.App::new()
    .get("/foo/*rest", fn(ctx) { ctx.text(200, "get") })
    .websocket("/foo/:id", fn(_ctx, _ws) { () })
  let response = app.respond({
    method: "OPTIONS",
    path: "*",
    headers: Map([]),
    body: "",
  })
  assert_eq(response.headers.get("Allow"), Some("GET, HEAD, OPTIONS"))
}
