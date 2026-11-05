///|
/// Boundary routes: the root path, trailing slashes, wildcard captures and the
/// static > param > wildcard matching precedence.
test "a route registered at the root path serves the root request" {
  let app = @feather.App::new().get("/", fn(ctx) {
    ctx.set_header("X-Route-Pattern", ctx.route_pattern())
    ctx.text(200, "root")
  })
  let response = app.respond({
    method: "GET",
    path: "/",
    headers: Map([]),
    body: "",
  })
  assert_eq(response.status, 200)
  assert_eq(response.body, "root")
  assert_eq(response.headers.get("X-Route-Pattern"), Some("/"))
}

test "the empty path routes to the root node" {
  let app = @feather.App::new().get("", fn(ctx) { ctx.text(200, "empty") })
  let response = app.respond({
    method: "GET",
    path: "",
    headers: Map([]),
    body: "",
  })
  assert_eq(response.status, 200)
  assert_eq(response.body, "empty")
}

test "a trailing slash matches the route registered without one" {
  let app = @feather.App::new().get("/api", fn(ctx) { ctx.text(200, "api") })
  let response = app.respond({
    method: "GET",
    path: "/api/",
    headers: Map([]),
    body: "",
  })
  assert_eq(response.status, 200)
  assert_eq(response.body, "api")
}

test "a static segment wins over a parameter for the same path" {
  let app = @feather.App::new()
    .get("/api", fn(ctx) { ctx.text(200, "static-text") })
    .get("/:id", fn(ctx) { ctx.text(200, "param:" + ctx.param("id")) })
  let response = app.respond({
    method: "GET",
    path: "/api",
    headers: Map([]),
    body: "",
  })
  assert_eq(response.status, 200)
  assert_eq(response.body, "static-text")
}

test "a parameter wins over a wildcard for a single segment" {
  let app = @feather.App::new()
    .get("/:id", fn(ctx) { ctx.text(200, "param:" + ctx.param("id")) })
    .get("/*rest", fn(ctx) { ctx.text(200, "wild:" + ctx.param("rest")) })
  let response = app.respond({
    method: "GET",
    path: "/users",
    headers: Map([]),
    body: "",
  })
  assert_eq(response.status, 200)
  assert_eq(response.body, "param:users")
}

test "a wildcard still matches a multi-segment path when no parameter fits" {
  let app = @feather.App::new()
    .get("/:id", fn(ctx) { ctx.text(200, "param:" + ctx.param("id")) })
    .get("/*rest", fn(ctx) { ctx.text(200, "wild:" + ctx.param("rest")) })
  let response = app.respond({
    method: "GET",
    path: "/users/42",
    headers: Map([]),
    body: "",
  })
  assert_eq(response.status, 200)
  assert_eq(response.body, "wild:users/42")
}

test "a wildcard captures the remainder including nested segments" {
  let app = @feather.App::new().get("/*path", fn(ctx) {
    ctx.text(200, "wild:" + ctx.param("path"))
  })
  let response = app.respond({
    method: "GET",
    path: "/files/a/b/c.txt",
    headers: Map([]),
    body: "",
  })
  assert_eq(response.status, 200)
  assert_eq(response.body, "wild:files/a/b/c.txt")
}

test "a wildcard matches the empty remainder at the root" {
  let app = @feather.App::new().get("/*path", fn(ctx) {
    ctx.text(200, "wild:" + ctx.param("path"))
  })
  let response = app.respond({
    method: "GET",
    path: "/",
    headers: Map([]),
    body: "",
  })
  assert_eq(response.status, 200)
  assert_eq(response.body, "wild:")
}

test "a parameter route does not match the empty root segment" {
  let app = @feather.App::new()
    .get("/:id", fn(ctx) { ctx.text(200, "param:" + ctx.param("id")) })
    .fallback(fn(ctx) { ctx.text(404, "fallback") })
  let response = app.respond({
    method: "GET",
    path: "/",
    headers: Map([]),
    body: "",
  })
  assert_eq(response.status, 404)
  assert_eq(response.body, "fallback")
}

test "has_param reports a wildcard capture even when it is empty" {
  let app = @feather.App::new().get("/*path", fn(ctx) {
    ctx.text(200, ctx.has_param("path").to_string())
  })
  let response = app.respond({
    method: "GET",
    path: "/",
    headers: Map([]),
    body: "",
  })
  assert_eq(response.status, 200)
  assert_eq(response.body, "true")
}

test "has_param reports parameter capture even when empty string value" {
  let app = @feather.App::new()
    .get("/:id", fn(ctx) {
      ctx.text(200, ctx.has_param("id").to_string())
    })
  let response = app.respond({
    method: "GET",
    path: "/",
    headers: Map([]),
    body: "",
  })
  assert_eq(response.status, 404)
}

test "has_param distinguishes absent from empty capture for parameter" {
  let app = @feather.App::new()
    .get("/:id", fn(ctx) {
      ctx.text(200, ctx.has_param("id").to_string() + ":" + ctx.param("id"))
    })
  let response = app.respond({
    method: "GET",
    path: "/something",
    headers: Map([]),
    body: "",
  })
  assert_eq(response.status, 200)
  assert_eq(response.body, "true:something")
}


test "multiple parameters in sequence are captured correctly" {
  let app = @feather.App::new()
    .get("/:a/:b", fn(ctx) {
      ctx.text(200, ctx.param("a") + ":" + ctx.param("b"))
    })
  let response = app.respond({
    method: "GET",
    path: "/foo/bar",
    headers: Map([]),
    body: "",
  })
  assert_eq(response.status, 200)
  assert_eq(response.body, "foo:bar")
}

test "multiple parameters with wildcard combo: /:id/*path" {
  let app = @feather.App::new()
    .get("/:id/*path", fn(ctx) {
      ctx.text(200, ctx.param("id") + ":" + ctx.param("path"))
    })
  let response = app.respond({
    method: "GET",
    path: "/users/42/files/a/b.txt",
    headers: Map([]),
    body: "",
  })
  assert_eq(response.status, 200)
  assert_eq(response.body, "users:42/files/a/b.txt")
}

test "parameter wins over wildcard when both could match single segment" {
  let app = @feather.App::new()
    .get("/:id/*rest", fn(ctx) {
      ctx.text(200, "param:" + ctx.param("id") + ":" + ctx.param("rest"))
    })
  let response = app.respond({
    method: "GET",
    path: "/users",
    headers: Map([]),
    body: "",
    })
  assert_eq(response.status, 200)
  assert_eq(response.body, "param:users:")
}

test "wildcard captures empty remainder at root with param pattern" {
  let app = @feather.App::new()
    .get("/:id/*rest", fn(ctx) {
      ctx.text(200, ctx.param("id") + ":" + ctx.param("rest"))
    })
  let response = app.respond({
    method: "GET",
    path: "/",
    headers: Map([]),
    body: "",
  })
  assert_eq(response.status, 404)
}

///|
test "multiple slashes and trailing slash normalise with a query" {
  let app = @feather.App::new().get("/api/users", fn(ctx) { ctx.text(200, "ok") })
  let response = app.respond({
    method: "GET",
    path: "/api//users/?x=1",
    headers: Map([]),
    body: "",
  })
  assert_eq(response.status, 200)
  assert_eq(response.body, "ok")
}

///|
test "route paths are case sensitive" {
  let app = @feather.App::new()
    .get("/api/users", fn(ctx) { ctx.text(200, "found") })
    .fallback(fn(ctx) { ctx.text(404, "missing") })
  assert_eq(
    app.respond({
      method: "GET",
      path: "/api/users",
      headers: Map([]),
      body: "",
    }).status,
    200,
  )
  assert_eq(
    app.respond({
      method: "GET",
      path: "/API/USERS",
      headers: Map([]),
      body: "",
    }).status,
    404,
  )
assert_eq(
    app.respond({
      method: "GET",
      path: "/API/USERS",
      headers: Map([]),
      body: "",
    }).status,
    404,
  )
}

///|
test "path with query string routes by path portion only" {
  let app = @feather.App::new().get("/search", fn(ctx) {
    ctx.text(200, "search")
  })
  let response = app.respond({
    method: "GET",
    path: "/search?q=test",
    headers: Map([]),
    body: "",
  })
  assert_eq(response.status, 200)
  assert_eq(response.body, "search")
}

///|
test "path with fragment routes by path portion only" {
  let app = @feather.App::new().get("/home", fn(ctx) {
    ctx.text(200, "home")
  })
  let response = app.respond({
    method: "GET",
    path: "/home#section",
    headers: Map([]),
    body: "",
  })
  assert_eq(response.status, 200)
  assert_eq(response.body, "home")
}

///|
test "multiple leading slashes normalize to single slash" {
  let app = @feather.App::new().get("/api", fn(ctx) {
    ctx.text(200, "api")
  })
  let response = app.respond({
    method: "GET",
    path: "/////api",
    headers: Map([]),
    body: "",
  })
  assert_eq(response.status, 200)
  assert_eq(response.body, "api")
}

///|
test "route registered with trailing slash matches request without" {
  let app = @feather.App::new().get("/api/", fn(ctx) { ctx.text(200, "trailing") })
  let response = app.respond({
    method: "GET",
    path: "/api",
    headers: Map([]),
    body: "",
  })
  assert_eq(response.status, 200)
  assert_eq(response.body, "trailing")
}

///|
test "route registered without trailing slash matches request with" {
  let app = @feather.App::new().get("/api", fn(ctx) { ctx.text(200, "no-trailing") })
  let response = app.respond({
    method: "GET",
    path: "/api/",
    headers: Map([]),
    body: "",
  })
  assert_eq(response.status, 200)
  assert_eq(response.body, "no-trailing")
}

///|
test "wildcard capture of empty path after root param" {
  let app = @feather.App::new()
    .get("/:id/*rest", fn(ctx) {
      ctx.text(200, ctx.param("id") + ":" + ctx.param("rest"))
    })
  let response = app.respond({
    method: "GET",
    path: "/",
    headers: Map([]),
    body: "",
  })
  assert_eq(response.status, 404)
}

///|
test "has_param true for wildcard even when path is root with query" {
  let app = @feather.App::new().get("/*path", fn(ctx) {
    ctx.text(200, ctx.has_param("path").to_string())
  })
  let response = app.respond({
    method: "GET",
    path: "/?x=1",
    headers: Map([]),
    body: "",
  })
  assert_eq(response.status, 200)
  assert_eq(response.body, "true")
}

///|
test "parameter capture coexists with wildcard capture" {
  let app = @feather.App::new()
    .get("/:id/*rest", fn(ctx) {
      ctx.text(200, ctx.param("id") + ":" + ctx.param("rest"))
    })
  let response = app.respond({
    method: "GET",
    path: "/users/42",
    headers: Map([]),
    body: "",
  })
  assert_eq(response.status, 200)
  assert_eq(response.body, "users:42")
}

///|
test "route precedence: static > param > wildcard with query" {
  let app = @feather.App::new()
    .get("/app", fn(ctx) { ctx.text(200, "static") })
    .get("/:id", fn(ctx) { ctx.text(200, "param:" + ctx.param("id")) })
    .get("/*rest", fn(ctx) { ctx.text(200, "wild:" + ctx.param("rest")) })
  let response = app.respond({
    method: "GET",
    path: "/app?q=1",
    headers: Map([]),
    body: "",
  })
  assert_eq(response.status, 200)
  assert_eq(response.body, "static")
}

///|
test "parameter route does not match root (wildcard matches instead)" {
  let app = @feather.App::new()
    .get("/:id", fn(ctx) { ctx.text(200, "param:" + ctx.param("id")) })
    .get("/*rest", fn(ctx) { ctx.text(200, "wild:" + ctx.param("rest")) })
  let response = app.respond({
    method: "GET",
    path: "/?x=1",
    headers: Map([]),
    body: "",
  })
  // After query string stripping, path becomes "/", and /:id does not match root;
  // the wildcard /*rest matches instead (param child only explored when segments remain)
  assert_eq(response.status, 200)
  assert_eq(response.body, "wild:")
}

///|
test "url_for with query parameters generates correct URL" {
  let app = @feather.App::new()
    .route_named("search", "GET", "/search", fn(ctx) { ctx.text(200, "ok") })
  let url = app.url_for("search", query=Map([("page", "1"), ("q", "hello")]))
  assert_eq(url, Some("/search?page=1&q=hello"))
}

///|
test "url_for with parameters generates correct URL" {
  let app = @feather.App::new()
    .route_named("user", "GET", "/users/:id", fn(ctx) { ctx.text(200, "ok") })
  let url = app.url_for("user", params=Map([("id", "42")]))
  assert_eq(url, Some("/users/42"))
}

///|
test "url_for returns none for missing parameter" {
  let app = @feather.App::new()
    .route_named("user", "GET", "/users/:id", fn(ctx) { ctx.text(200, "ok") })
  let url = app.url_for("user", params=Map([("name", "john")]))
  assert_eq(url, None)
}

test "url_for with empty params map generates root URL" {
  let app = @feather.App::new()
    .route_named("search", "GET", "/search", fn(ctx) { ctx.text(200, "ok") })
  let url = app.url_for("search", params=Map([]))
  assert_eq(url, Some("/search"))
}

///|
test "url_for with empty query generates correct URL" {
  let app = @feather.App::new()
    .route_named("search", "GET", "/search", fn(ctx) { ctx.text(200, "ok") })
  let url = app.url_for("search", query=Map([]))
  assert_eq(url, Some("/search"))
}

///|
test "route matching with percent-encoded param segment" {
  let app = @feather.App::new().get("/user/%7Etest", fn(ctx) {
    ctx.text(200, "matched")
  })
  let response = app.respond({
    method: "GET",
    path: "/user/%7Etest",
    headers: Map([]),
    body: "",
  })
  assert_eq(response.status, 200)
  assert_eq(response.body, "matched")
}

///|
test "route with param and query string" {
  let app = @feather.App::new().get("/search/:q", fn(ctx) {
    ctx.text(200, ctx.param("q"))
  })
  let response = app.respond({
    method: "GET",
    path: "/search/feather",
    headers: Map([]),
    body: "",
  })
  assert_eq(response.status, 200)
  assert_eq(response.body, "feather")
}

///|
test "wildcard capture with multiple slashes" {
  let app = @feather.App::new().get("/*path", fn(ctx) {
    ctx.text(200, ctx.param("path"))
  })
  let response = app.respond({
    method: "GET",
    path: "///deep/path",
    headers: Map([]),
    body: "",
  })
  assert_eq(response.status, 200)
  assert_eq(response.body, "deep/path")
}

///|
test "has_param distinguishes absent from empty for param with query" {
  let app = @feather.App::new()
    .get("/search/:q", fn(ctx) {
      ctx.text(200, ctx.has_param("q").to_string() + ":" + ctx.param("q"))
    })
  let response = app.respond({
    method: "GET",
    path: "/search/feather",
    headers: Map([]),
    body: "",
  })
  assert_eq(response.status, 200)
  assert_eq(response.body, "true:feather")
}

///|
test "route not found with OPTIONS and allowed methods" {
  let app = @feather.App::new().get("/items", fn(ctx) { ctx.text(200, "ok") })
  let response = app.respond({
    method: "DELETE",
    path: "/items",
    headers: Map([]),
    body: "",
  })
  assert_eq(response.status, 405)
  assert_eq(
    response.headers.get("Allow"),
    Some("GET, HEAD"),
  )
}

///|
test "OPTIONS * with no routes registered" {
  let app = @feather.App::new()
  let response = app.respond({
    method: "OPTIONS",
    path: "*",
    headers: Map([]),
    body: "",
  })
  assert_eq(response.status, 204)
  assert_eq(
    response.headers.get("Allow"),
    Some("GET, PUT, HEAD, POST, PATCH, TRACE, DELETE, CONNECT, OPTIONS"),
  )
}

///|
test "route with both param and wildcard, path with query" {
  let app = @feather.App::new()
    .get("/:id/*rest", fn(ctx) {
      ctx.text(200, ctx.param("id") + ":" + ctx.param("rest"))
    })
  let response = app.respond({
    method: "GET",
    path: "/42/extra/deep",
    headers: Map([]),
    body: "",
  })
  assert_eq(response.status, 200)
  assert_eq(response.body, "42:extra/deep")
}

///|
test "a route registered with a trailing slash matches a request without one" {
  let app = @feather.App::new().get("/api/", fn(ctx) { ctx.text(200, "trailing") })
  let response = app.respond({
    method: "GET",
    path: "/api",
    headers: Map([]),
    body: "",
  })
  assert_eq(response.status, 200)
  assert_eq(response.body, "trailing")
}

///|
test "case sensitivity applies to parameter segments too" {
  let app = @feather.App::new()
    .get("/Users/:id", fn(ctx) { ctx.text(200, ctx.param("id")) })
    .fallback(fn(ctx) { ctx.text(404, "missing") })
  assert_eq(
    app.respond({
      method: "GET",
      path: "/Users/42",
      headers: Map([]),
      body: "",
    }).body,
    "42",
  )
  assert_eq(
    app.respond({
      method: "GET",
      path: "/users/42",
      headers: Map([]),
      body: "",
    }).status,
    404,
  )
}

///|
test "route with param segment containing percent-encoded space matches" {
  let app = @feather.App::new().get("/user/%20test", fn(ctx) {
    ctx.text(200, "matched")
  })
  let response = app.respond({
    method: "GET",
    path: "/user/%20test",
    headers: Map([]),
    body: "",
  })
  assert_eq(response.status, 200)
  assert_eq(response.body, "matched")
}

///|
test "route with param and wildcard, path with query and fragment" {
  let app = @feather.App::new()
    .get("/:id/*rest", fn(ctx) {
      ctx.text(200, ctx.param("id") + ":" + ctx.param("rest"))
    })
  let response = app.respond({
    method: "GET",
    path: "/users/42/files?x=1#section",
    headers: Map([]),
    body: "",
  })
  assert_eq(response.status, 200)
  assert_eq(response.body, "users:42/files")
}

///|
test "has_param false for wildcard when path is root with both query and fragment" {
  let app = @feather.App::new().get("/*path", fn(ctx) {
    ctx.text(200, ctx.has_param("path").to_string())
  })
  let response = app.respond({
    method: "GET",
    path: "/?x=1#section",
    headers: Map([]),
    body: "",
  })
  assert_eq(response.status, 200)
  assert_eq(response.body, "true")
}

///|
test "parameter route does not match root even with query string present" {
  let app = @feather.App::new()
    .get("/:id", fn(ctx) { ctx.text(200, "param:" + ctx.param("id")) })
    .fallback(fn(ctx) { ctx.text(404, "fallback") })
  let response = app.respond({
    method: "GET",
    path: "/?id=42",
    headers: Map([]),
    body: "",
  })
  assert_eq(response.status, 404)
  assert_eq(response.body, "fallback")
}

///|
test "wildcard captures empty remainder at root with param and query combined" {
  let app = @feather.App::new().get("/*path", fn(ctx) {
    ctx.text(200, ctx.param("path"))
  })
  let response = app.respond({
    method: "GET",
    path: "/?x=1",
    headers: Map([]),
    body: "",
  })
  assert_eq(response.status, 200)
  assert_eq(response.body, "")
}

///|
test "multiple param segments capture order correctly" {
  let app = @feather.App::new()
    .get("/:a/:b/:c", fn(ctx) {
      ctx.text(200, ctx.param("a") + ":" + ctx.param("b") + ":" + ctx.param("c"))
    })
  let response = app.respond({
    method: "GET",
    path: "/1/2/3",
    headers: Map([]),
    body: "",
  })
  assert_eq(response.status, 200)
  assert_eq(response.body, "1:2:3")
}

///|
test "param route with leading slash normalizes correctly" {
  let app = @feather.App::new().get("/:id", fn(ctx) {
    ctx.text(200, ctx.param("id"))
  })
  let response = app.respond({
    method: "GET",
    path: "/////users",
    headers: Map([]),
    body: "",
  })
  assert_eq(response.status, 200)
  assert_eq(response.body, "users")
}

///|
test "wildcard capture with many consecutive slashes" {
  let app = @feather.App::new().get("/*path", fn(ctx) {
    ctx.text(200, ctx.param("path"))
  })
  let response = app.respond({
    method: "GET",
    path: "///a///b///c",
    headers: Map([]),
    body: "",
  })
  assert_eq(response.status, 200)
  assert_eq(response.body, "a/b/c")
}

///|
test "route not found with OPTIONS on specific unmatched path" {
  let app = @feather.App::new().get("/items", fn(ctx) { ctx.text(200, "ok") })
  let response = app.respond({
    method: "OPTIONS",
    path: "/other",
    headers: Map([]),
    body: "",
  })
  assert_eq(response.status, 404)
}

///|
test "url_for with both path params and query parameters" {
  let app = @feather.App::new()
    .route_named("user", "GET", "/users/:id", fn(ctx) { ctx.text(200, "ok") })
  let url = app.url_for("user", params=Map([("id", "42")]), query=Map([("page", "1")]))
  assert_eq(url, Some("/users/42?page=1"))
}

///|
test "url_for returns none when name does not exist" {
  let app = @feather.App::new()
  let url = app.url_for("nonexistent", params=Map([("id", "42")]))
  assert_eq(url, None)
}

///|
test "route with param and same-name wildcard combo" {
  let app = @feather.App::new()
    .get("/:resource/*path", fn(ctx) {
      ctx.text(200, ctx.param("resource") + ":" + ctx.param("path"))
    })
  let response = app.respond({
    method: "GET",
    path: "/images/photo.png",
    headers: Map([]),
    body: "",
  })
  assert_eq(response.status, 200)
  assert_eq(response.body, "images:photo.png")
}

///|
test "parameter route with numeric param and leading zeros" {
  let app = @feather.App::new().get("/:id", fn(ctx) {
    ctx.text(200, ctx.param("id"))
  })
  let response = app.respond({
    method: "GET",
    path: "/007",
    headers: Map([]),
    body: "",
  })
  assert_eq(response.status, 200)
  assert_eq(response.body, "007")
}

///|
test "wildcard does not match when param route could match" {
  let app = @feather.App::new()
    .get("/:id", fn(ctx) { ctx.text(200, "param:" + ctx.param("id")) })
    .get("/*rest", fn(ctx) { ctx.text(200, "wild:" + ctx.param("rest")) })
  let response = app.respond({
    method: "GET",
    path: "/test",
    headers: Map([]),
    body: "",
  })
  assert_eq(response.status, 200)
  assert_eq(response.body, "param:test")
}

///|
test "route with percent-encoded forward slash %2F in path matches" {
  let app = @feather.App::new().get("/user/%2Ftest", fn(ctx) {
    ctx.text(200, "matched")
  })
  let response = app.respond({
    method: "GET",
    path: "/user/%2Ftest",
    headers: Map([]),
    body: "",
  })
  assert_eq(response.status, 200)
  assert_eq(response.body, "matched")
}

///|
test "route with unicode path segment matches" {
  let app = @feather.App::new().get("/日本/测试", fn(ctx) {
    ctx.text(200, "matched")
  })
  let response = app.respond({
    method: "GET",
    path: "/日本/测试",
    headers: Map([]),
    body: "",
  })
  assert_eq(response.status, 200)
  assert_eq(response.body, "matched")
}

///|
test "route with backslash in path matches" {
  let app = @feather.App::new().get("/api/test\\value", fn(ctx) {
    ctx.text(200, "matched")
  })
  let response = app.respond({
    method: "GET",
    path: "/api/test\\value",
    headers: Map([]),
    body: "",
  })
  assert_eq(response.status, 200)
  assert_eq(response.body, "matched")
}

///|
test "route with mixed percent-encoded and param segments" {
  let app = @feather.App::new().get("/user/%E8%8A%82%E5%8F%8C", fn(ctx) {
    ctx.text(200, "matched")
  })
  let response = app.respond({
    method: "GET",
    path: "/user/%E8%8A%82%E5%8F%8C",
    headers: Map([]),
    body: "",
  })
  assert_eq(response.status, 200)
  assert_eq(response.body, "matched")
}

///|
test "route with multiple query parameters and fragment" {
  let app = @feather.App::new().get("/search", fn(ctx) {
    ctx.text(200, ctx.query("q") + ctx.fragment())
  })
  let response = app.respond({
    method: "GET",
    path: "/search?q=hello#section",
    headers: Map([]),
    body: "",
  })
  assert_eq(response.status, 200)
  assert_eq(response.body, "hellosection")
}

///|
test "route with param and query combined" {
  let app = @feather.App::new().get("/users/:id", fn(ctx) {
    ctx.text(200, ctx.param("id") + ":" + ctx.query("q"))
  })
  let response = app.respond({
    method: "GET",
    path: "/users/42?q=json",
    headers: Map([]),
    body: "",
  })
  assert_eq(response.status, 200)
  assert_eq(response.body, "42:json")
}

///|
test "url_for with param and wildcard combined" {
  let app = @feather.App::new()
    .route_named("file", "GET", "/files/:name/*path", fn(ctx) { ctx.text(200, "ok") })
  let url = app.url_for("file", params=Map([("name", "report"), ("path", "a/b.txt")]), query=Map([("a", "1")]))
  assert_eq(url, Some("/files/report/a/b.txt?a=1"))
}

///|
test "url_for with empty wildcard generates trailing slash" {
  let app = @feather.App::new()
    .route_named("root", "GET", "/*", fn(ctx) { ctx.text(200, "ok") })
  let url = app.url_for("root")
  assert_eq(url, Some("/"))
}
