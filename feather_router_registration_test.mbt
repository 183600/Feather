///|
test "router duplicate registration keeps the last handler" {
  let app = @feather.App::new()
    .get("/dupe", fn(ctx) { ctx.text(200, "first") })
    .get("/dupe", fn(ctx) { ctx.text(200, "second") })
  let response = app.respond({
    method: "GET",
    path: "/dupe",
    headers: Map([]),
    body: "",
  })
  assert_eq(response.status, 200)
  assert_eq(response.body, "second")
}

///|
test "router prefers static segments over parameters" {
  let app = @feather.App::new()
    .get("/a/:id", fn(ctx) { ctx.text(200, "param") })
    .get("/a/b", fn(ctx) { ctx.text(200, "static") })
  let response = app.respond({
    method: "GET",
    path: "/a/b",
    headers: Map([]),
    body: "",
  })
  assert_eq(response.body, "static")
  let other = app.respond({
    method: "GET",
    path: "/a/c",
    headers: Map([]),
    body: "",
  })
  assert_eq(other.body, "param")
}

///|
test "router param name with special characters" {
  let app = @feather.App::new().get("/x/:id|", fn(ctx) {
    ctx.text(200, "p=" + ctx.param("id|"))
  })
  let response = app.respond({
    method: "GET",
    path: "/x/5",
    headers: Map([]),
    body: "",
  })
  assert_eq(response.status, 200)
}

///|
test "router empty segment between slashes" {
  let app = @feather.App::new().get("/a//b", fn(ctx) { ctx.text(200, "hit") })
  let response = app.respond({
    method: "GET",
    path: "/a//b",
    headers: Map([]),
    body: "",
  })
  assert_eq(response.status, 200)
}

///|
test "router route with only a slash" {
  let app = @feather.App::new().get("/", fn(ctx) { ctx.text(200, "root") })
  let response = app.respond({
    method: "GET",
    path: "/",
    headers: Map([]),
    body: "",
  })
  assert_eq(response.status, 200)
}

///|
test "router registered path without leading slash" {
  let app = @feather.App::new().get("users", fn(ctx) { ctx.text(200, "u") })
  let response = app.respond({
    method: "GET",
    path: "/users",
    headers: Map([]),
    body: "",
  })
  assert_eq(response.status, 200)
  assert_eq(response.body, "u")
}

///|
test "router matches request methods case-insensitively" {
  let app = @feather.App::new().get("/m", fn(ctx) { ctx.text(200, "ok") })
  let response = app.respond({
    method: "get",
    path: "/m",
    headers: Map([]),
    body: "",
  })
  assert_eq(response.status, 200)
}

///|
test "router deep nesting beyond registered" {
  let app = @feather.App::new().get("/a/b", fn(ctx) { ctx.text(200, "ab") })
  let response = app.respond({
    method: "GET",
    path: "/a/b/c/d",
    headers: Map([]),
    body: "",
  })
  assert_eq(response.status, 404)
}

///|
test "router percent-encoded static route" {
  let app = @feather.App::new().get("/caf%C3%A9", fn(ctx) {
    ctx.text(200, "cafe")
  })
  let response = app.respond({
    method: "GET",
    path: "/caf%C3%A9",
    headers: Map([]),
    body: "",
  })
  assert_eq(response.status, 200)
  let raw = app.respond({
    method: "GET",
    path: "/café",
    headers: Map([]),
    body: "",
  })
  assert_eq(raw.status, 200)
}
