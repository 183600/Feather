///|
test "OPTIONS * responds with server methods sorted alphabetically" {
  let app = @feather.App::new()
    .get("/hello", fn(ctx) { ctx.text(200, "hello") })
    .post("/submit", fn(ctx) { ctx.text(201, "created") })
  let response = app.respond({
    method: "OPTIONS",
    path: "*",
    headers: Map([]),
    body: "",
  })
  assert_eq(response.status, 204)
  assert_eq(response.headers.get("Allow"), Some("GET, HEAD, POST, OPTIONS"))
}

///|
test "OPTIONS * includes WebSocket method" {
  let app = @feather.App::new()
    .websocket("/ws", fn(_ctx, _ws) { () })
  let response = app.respond({
    method: "OPTIONS",
    path: "*",
    headers: Map([]),
    body: "",
  })
  assert_eq(response.status, 204)
  assert_eq(response.headers.get("Allow"), Some("GET, OPTIONS"))
}

///|
test "OPTIONS * includes SSE and stream methods" {
  let app = @feather.App::new()
    .sse("/events", async fn(_ctx, _sse) { () })
    .stream("/feed", async fn(_ctx, _stream) { })
  let response = app.respond({
    method: "OPTIONS",
    path: "*",
    headers: Map([]),
    body: "",
  })
  assert_eq(response.status, 204)
  assert_eq(response.headers.get("Allow"), Some("GET, HEAD, OPTIONS"))
}

///|
test "CONNECT route can be registered and matched" {
  let connected = [false]
  let app = @feather.App::new()
    .connect("/tunnel", fn(ctx) {
      connected[0] = true
      ctx.text(201, "connected")
    })
  let response = app.respond({
    method: "CONNECT",
    path: "/tunnel",
    headers: Map([]),
    body: "",
  })
  assert_eq(response.status, 201)
  assert_eq(connected[0], true)
}

///|
test "TRACE route can be registered and matched" {
  let app = @feather.App::new()
    .trace("/echo", fn(ctx) { ctx.text(200, ctx.request.path) })
  let response = app.respond({
    method: "TRACE",
    path: "/echo",
    headers: Map([]),
    body: "",
  })
  assert_eq(response.status, 200)
  assert_eq(response.body, "/echo")
}

///|
test "all method handles HEAD specially with empty body" {
  let app = @feather.App::new().all("/test", fn(ctx) { ctx.text(200, "ok") })
  let response = app.respond({
    method: "HEAD",
    path: "/test",
    headers: Map([]),
    body: "",
  })
  assert_eq(response.status, 200)
  assert_eq(response.body, "")
}

///|
test "static mount with index file returns file for directory request" {
  let app = @feather.App::new()
    .static_files("/assets", "/srv/public", index="index.html")
  let file = app.static_file_for("/assets/")
  assert_eq(file, Some("/srv/public/index.html"))
}

///|
test "static mount without index returns None for directory request" {
  let app = @feather.App::new()
    .static_files("/assets", "/srv/public", index="")
  let file = app.static_file_for("/assets/")
  assert_eq(file, None)
}

///|
test "dynamic static mount binds captured params" {
  let app = @feather.App::new()
    .static_files("/:tenant/assets", "/srv/public")
  let file = app.static_file_for("/acme/assets/app.js")
  assert_eq(file, Some("/srv/public/app.js"))
}

///|
test "wildcard static mount captures remainder at root" {
  let app = @feather.App::new()
    .static_files("/*path", "/srv/root")
  let file = app.static_file_for("/some/deep/path.txt")
  assert_eq(file, Some("/srv/root/some/deep/path.txt"))
}

///|
test "wildcards at root match any path" {
  let app = @feather.App::new().get("/*path", fn(ctx) {
    ctx.text(200, ctx.param("path"))
  })
  let response = app.respond({
    method: "GET",
    path: "/anything/goes/here",
    headers: Map([]),
    body: "",
  })
  assert_eq(response.status, 200)
  assert_eq(response.body, "anything/goes/here")
}

///|
test "root wildcard does not match empty path" {
  let app = @feather.App::new()
    .get("/*path", fn(ctx) { ctx.text(200, "wildcard") })
    .get("/", fn(ctx) { ctx.text(200, "root") })
  let response = app.respond({
    method: "GET",
    path: "/",
    headers: Map([]),
    body: "",
  })
  assert_eq(response.status, 200)
  assert_eq(response.body, "root")
}

///|
test "named routes url_for with query parameters only" {
  let app = @feather.App::new()
    .route_named("search", "GET", "/search", fn(ctx) { ctx.text(200, "ok") })
  let url = app.url_for("search", query=Map([("page", "1"), ("q", "hello")]))
  assert_eq(url, Some("/search?page=1&q=hello"))
}

///|
test "url_for returns nil for unknown route name" {
  let app = @feather.App::new().get("/", fn(ctx) { ctx.text(200, "ok") })
  assert_eq(app.url_for("unknown"), None)
}

///|
test "route_pattern reports empty for unbound params" {
  let ctx = @feather.Context::new({
    method: "GET",
    path: "/test",
    headers: Map([]),
    body: "",
  })
  assert_eq(ctx.route_pattern(), "")
}

///|
test "route_method reports empty when no route matched" {
  let ctx = @feather.Context::new({
    method: "GET",
    path: "/missing",
    headers: Map([]),
    body: "",
  })
  assert_eq(ctx.route_method(), "")
}

///|
test "fallback handler sets empty route identity" {
  let app = @feather.App::new()
    .get("/known", fn(ctx) { ctx.text(200, "ok") })
    .fallback(fn(ctx) { ctx.text(404, "missing") })
  let response = app.respond({
    method: "GET",
    path: "/missing",
    headers: Map([]),
    body: "",
  })
  assert_eq(response.status, 404)
}

///|
test "url_for with named route and path params" {
  let app = @feather.App::new()
    .route_named("user", "GET", "/users/:id", fn(ctx) { ctx.text(200, "ok") })
  let url = app.url_for("user", params=Map([("id", "42")]))
  assert_eq(url, Some("/users/42"))
}

///|
test "url_for with named route and wildcard param" {
  let app = @feather.App::new()
    .route_named("file", "GET", "/static/*path", fn(ctx) { ctx.text(200, "ok") })
  let url = app.url_for("file", params=Map([("path", "css/app.css")]))
  assert_eq(url, Some("/static/css/app.css"))
}

///|
test "OPTIONS * with CONNECT route includes CONNECT method" {
  let app = @feather.App::new()
    .connect("/tunnel", fn(ctx) {
      ctx.text(201, "connected")
    })
  let response = app.respond({
    method: "OPTIONS",
    path: "*",
    headers: Map([]),
    body: "",
  })
  assert_eq(response.status, 204)
  assert_eq(response.headers.get("Allow"), Some("CONNECT, OPTIONS"))
}

///|
test "OPTIONS * with TRACE route includes TRACE method" {
  let app = @feather.App::new()
    .trace("/echo", fn(ctx) { ctx.text(200, ctx.request.path) })
  let response = app.respond({
    method: "OPTIONS",
    path: "*",
    headers: Map([]),
    body: "",
  })
  assert_eq(response.status, 204)
  assert_eq(response.headers.get("Allow"), Some("TRACE, OPTIONS"))
}

///|
test "HEAD falls back to GET for parameter route" {
  let app = @feather.App::new().get("/users/:id", fn(ctx) { ctx.text(200, "ok") })
  let response = app.respond({
    method: "HEAD",
    path: "/users/42",
    headers: Map([]),
    body: "",
  })
  assert_eq(response.status, 200)
  assert_eq(response.body, "")
}

///|
test "method not allowed returns Allow header with HEAD implicit" {
  let app = @feather.App::new()
    .get("/items", fn(ctx) { ctx.text(200, "ok") })
  let response = app.respond({
    method: "POST",
    path: "/items",
    headers: Map([]),
    body: "",
  })
  assert_eq(response.status, 405)
  assert_eq(response.headers.get("Allow"), Some("GET, HEAD"))
}

///|
test "static mount with dynamic prefix binds captured params" {
  let app = @feather.App::new()
    .static_files("/:tenant/assets", "/srv/public")
  let file = app.static_file_for("/acme/assets/app.js")
  assert_eq(file, Some("/srv/public/app.js"))
}

///|
test "wildcard route at root with empty path preference" {
  let app = @feather.App::new()
    .get("/*path", fn(ctx) { ctx.text(200, "wildcard") })
    .get("/", fn(ctx) { ctx.text(200, "root") })
  let response = app.respond({
    method: "GET",
    path: "/",
    headers: Map([]),
    body: "",
  })
  assert_eq(response.status, 200)
  assert_eq(response.body, "root")
}

///|
/// `OPTIONS` on a path answers `204` with the path's allowed methods. `HEAD`
/// is only advertised alongside `GET` (RFC 9110 §9.3.2), so a `HEAD`-only
/// route must not imply `GET`.
test "OPTIONS on a HEAD-only route advertises HEAD only" {
  let app = @feather.App::new().head("/items", fn(ctx) { ctx.text(200, "ok") })
  let response = app.respond({
    method: "OPTIONS",
    path: "/items",
    headers: Map([]),
    body: "",
  })
  assert_eq(response.status, 204)
  assert_eq(response.body, "")
  assert_eq(response.headers.get("Allow"), Some("HEAD"))
}

///|
/// A `POST`-only route advertises `POST`, not the implicit `HEAD` that `GET`
/// carries.
test "OPTIONS on a POST-only route advertises POST only" {
  let app = @feather.App::new().post("/items", fn(ctx) { ctx.text(201, "created") })
  let response = app.respond({
    method: "OPTIONS",
    path: "/items",
    headers: Map([]),
    body: "",
  })
  assert_eq(response.status, 204)
  assert_eq(response.headers.get("Allow"), Some("POST"))
}

///|
/// `OPTIONS` on a path matched by a wildcard route reports the wildcard's
/// methods, and the captured parameter is not exposed to the automatic answer.
test "OPTIONS on a wildcard-matched path advertises GET and HEAD" {
  let app = @feather.App::new().get("/*path", fn(ctx) { ctx.text(200, "wild") })
  let response = app.respond({
    method: "OPTIONS",
    path: "/anything/here",
    headers: Map([]),
    body: "",
  })
  assert_eq(response.status, 204)
  assert_eq(response.headers.get("Allow"), Some("GET, HEAD"))
}

///|
/// A path with several registered methods advertises all of them, with `HEAD`
/// implicit whenever `GET` is present.
test "OPTIONS on a multi-method path advertises every registered method" {
  let app = @feather.App::new()
    .get("/items", fn(ctx) { ctx.text(200, "list") })
    .post("/items", fn(ctx) { ctx.text(201, "created") })
  let response = app.respond({
    method: "OPTIONS",
    path: "/items",
    headers: Map([]),
    body: "",
  })
  assert_eq(response.status, 204)
  assert_eq(response.headers.get("Allow"), Some("GET, HEAD, POST"))
}

///|
/// `OPTIONS` on a path matched by a parameter route advertises that route's
/// methods.
test "OPTIONS on a parameter-matched path advertises GET and HEAD" {
  let app = @feather.App::new().get("/users/:id", fn(ctx) { ctx.text(200, "user") })
  let response = app.respond({
    method: "OPTIONS",
    path: "/users/42",
    headers: Map([]),
    body: "",
  })
  assert_eq(response.status, 204)
  assert_eq(response.headers.get("Allow"), Some("GET, HEAD"))
}

///|
/// `OPTIONS` on a path that no route matches is still `404`, without an
/// `Allow` header.
test "OPTIONS on an unmatched path is 404 without Allow" {
  let app = @feather.App::new().get("/items", fn(ctx) { ctx.text(200, "ok") })
  let response = app.respond({
    method: "OPTIONS",
    path: "/missing",
    headers: Map([]),
    body: "",
  })
  assert_eq(response.status, 404)
  assert_eq(response.headers.get("Allow"), None)
}
///|
test "url_for returns nil for an unregistered name on a single-route app" {
  let app = @feather.App::new().get("/", fn(ctx) { ctx.text(200, "ok") })
  assert_eq(app.url_for("unknown"), None)
}

///|
test "url_for substitutes a named :id path param" {
  let app = @feather.App::new()
    .route_named("user", "GET", "/users/:id", fn(ctx) { ctx.text(200, "ok") })
  let url = app.url_for("user", params=Map([("id", "42")]))
  assert_eq(url, Some("/users/42"))
}

///|
test "url_for with named route and wildcard param with content" {
  let app = @feather.App::new()
    .route_named("file", "GET", "/static/*path", fn(ctx) { ctx.text(200, "ok") })
  let url = app.url_for("file", params=Map([("path", "css/app.css")]))
  assert_eq(url, Some("/static/css/app.css"))
}

///|
test "url_for with named route and wildcard param empty value returns path with empty wildcard" {
  let app = @feather.App::new()
    .route_named("file", "GET", "/static/*path", fn(ctx) { ctx.text(200, "ok") })
  let url = app.url_for("file", params=Map([("path", "")]))
  // Empty wildcard value generates /static/ (trailing slash from the registered pattern)
  assert_eq(url, Some("/static/"))
}

///|
test "url_for with named route and query parameters sorted alphabetically" {
  let app = @feather.App::new()
    .route_named("search", "GET", "/search", fn(ctx) { ctx.text(200, "ok") })
  let url = app.url_for("search", query=Map([("page", "1"), ("q", "hello")]))
  // Query params are sorted alphabetically: page comes before q
  assert_eq(url, Some("/search?page=1&q=hello"))
}

///|
test "url_for with named route and no params or query returns registered path" {
  let app = @feather.App::new()
    .route_named("ping", "GET", "/api/ping", fn(ctx) { ctx.text(200, "ok") })
  let url = app.url_for("ping")
  assert_eq(url, Some("/api/ping"))
}

///|
test "CONNECT route OPTIONS * responds with CONNECT and OPTIONS methods" {
  let app = @feather.App::new()
    .connect("/tunnel", fn(ctx) { ctx.text(201, "connected") })
  let response = app.respond({
    method: "OPTIONS",
    path: "*",
    headers: Map([]),
    body: "",
  })
  assert_eq(response.status, 204)
  assert_eq(response.headers.get("Allow"), Some("CONNECT, OPTIONS"))
}

///|
test "TRACE route OPTIONS * responds with TRACE and OPTIONS methods" {
  let app = @feather.App::new()
    .trace("/echo", fn(ctx) { ctx.text(200, ctx.request.path) })
  let response = app.respond({
    method: "OPTIONS",
    path: "*",
    headers: Map([]),
    body: "",
  })
  assert_eq(response.status, 204)
  assert_eq(response.headers.get("Allow"), Some("TRACE, OPTIONS"))
}

///|
test "HEAD-only route specific path OPTIONS advertises HEAD only (no implicit OPTIONS)" {
  let app = @feather.App::new().head("/items", fn(ctx) { ctx.text(200, "ok") })
  let response = app.respond({
    method: "OPTIONS",
    path: "/items",
    headers: Map([]),
    body: "",
  })
  assert_eq(response.status, 204)
  assert_eq(response.body, "")
  assert_eq(response.headers.get("Allow"), Some("HEAD"))
}

///|
test "POST-only route specific path OPTIONS advertises POST only (no implicit OPTIONS)" {
  let app = @feather.App::new().post("/items", fn(ctx) { ctx.text(201, "created") })
  let response = app.respond({
    method: "OPTIONS",
    path: "/items",
    headers: Map([]),
    body: "",
  })
  assert_eq(response.status, 204)
  assert_eq(response.body, "")
  assert_eq(response.headers.get("Allow"), Some("POST"))
}

///|
test "OPTIONS on multi-method specific path advertises all methods with HEAD implicit" {
  let app = @feather.App::new()
    .get("/items", fn(ctx) { ctx.text(200, "list") })
    .post("/items", fn(ctx) { ctx.text(201, "created") })
  let response = app.respond({
    method: "OPTIONS",
    path: "/items",
    headers: Map([]),
    body: "",
  })
  assert_eq(response.status, 204)
  assert_eq(response.headers.get("Allow"), Some("GET, HEAD, POST"))
}

///|
test "OPTIONS on parameter-matched specific path advertises that route's methods with HEAD" {
  let app = @feather.App::new().get("/users/:id", fn(ctx) { ctx.text(200, "user") })
  let response = app.respond({
    method: "OPTIONS",
    path: "/users/42",
    headers: Map([]),
    body: "",
  })
  assert_eq(response.status, 204)
  assert_eq(response.headers.get("Allow"), Some("GET, HEAD"))
}

///|
test "OPTIONS on wildcard-matched specific path advertises GET and HEAD" {
  let app = @feather.App::new().get("/*path", fn(ctx) { ctx.text(200, "wild") })
  let response = app.respond({
    method: "OPTIONS",
    path: "/anything/here",
    headers: Map([]),
    body: "",
  })
  assert_eq(response.status, 204)
  assert_eq(response.headers.get("Allow"), Some("GET, HEAD"))
}

///|
test "OPTIONS on unmatched path is 404 without Allow header" {
  let app = @feather.App::new().get("/items", fn(ctx) { ctx.text(200, "ok") })
  let response = app.respond({
    method: "OPTIONS",
    path: "/missing",
    headers: Map([]),
    body: "",
  })
  assert_eq(response.status, 404)
  assert_eq(response.headers.get("Allow"), None)
}

///|
test "static mount with dynamic prefix :tenant binds captured params" {
  let app = @feather.App::new()
    .static_files("/:tenant/assets", "/srv/public")
  let file = app.static_file_for("/acme/assets/app.js")
  assert_eq(file, Some("/srv/public/app.js"))
}

///|
test "wildcard static mount at root captures remainder" {
  let app = @feather.App::new()
    .static_files("/*path", "/srv/root")
  let file = app.static_file_for("/some/deep/path.txt")
  assert_eq(file, Some("/srv/root/some/deep/path.txt"))
}

///|
test "root wildcard does not match empty path when / route also exists" {
  let app = @feather.App::new()
    .get("/*path", fn(ctx) { ctx.text(200, "wildcard") })
    .get("/", fn(ctx) { ctx.text(200, "root") })
  let response = app.respond({
    method: "GET",
    path: "/",
    headers: Map([]),
    body: "",
  })
  assert_eq(response.status, 200)
  assert_eq(response.body, "root")
}

///|
test "dynamic route param capture with url_for" {
  let app = @feather.App::new()
    .route_named("item", "GET", "/items/:id", fn(ctx) { ctx.text(200, "ok") })
  let url = app.url_for("item", params=Map([("id", "42")]))
  assert_eq(url, Some("/items/42"))
}

///|
test "method not allowed with only TRACE method advertises TRACE only" {
  let app = @feather.App::new().trace("/echo", fn(ctx) { ctx.text(200, "ok") })
  let response = app.respond({
    method: "POST",
    path: "/echo",
    headers: Map([]),
    body: "",
  })
  assert_eq(response.status, 405)
  // TRACE-only path: Allow lists TRACE only (no HEAD implicit for non-GET methods)
  assert_eq(response.headers.get("Allow"), Some("TRACE"))
}

///|
test "fallback handler preserves route pattern identity for matched routes" {
  let app = @feather.App::new()
    .get("/known", fn(ctx) { ctx.text(200, "ok") })
    .fallback(fn(ctx) { ctx.text(404, "missing") })
  let response = app.respond({
    method: "GET",
    path: "/unknown",
    headers: Map([]),
    body: "",
  })
  assert_eq(response.status, 404)
  // Route pattern for unmatched paths should be empty
  let ctx = @feather.Context::new({
    method: "GET",
    path: "/unknown",
    headers: Map([]),
    body: "",
  })
  assert_eq(ctx.route_pattern(), "")
}
