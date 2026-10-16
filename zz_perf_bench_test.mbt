///|
fn make_app() -> App {
  let app = App::new()
  ignore(app.get("/", fn(ctx) { ctx.text(200, "hello") }))
  ignore(app.get("/api/users", fn(ctx) { ctx.json_value(200, Json::object(Map([]))) }))
  ignore(app.get("/api/users/:id", fn(ctx) { ctx.text(200, ctx.param("id")) }))
  ignore(app.get("/api/users/:id/posts/:post", fn(ctx) {
    ctx.text(200, ctx.param("id") + ":" + ctx.param("post"))
  }))
  ignore(app.post("/api/users", fn(ctx) { ctx.json_value(200, Json::object(Map([]))) }))
  ignore(app.get("/static/*path", fn(ctx) { ctx.text(200, ctx.param("path")) }))
  app
}

///|
test "bench-dispatch-static" (b : @bench.T) {
  let app = make_app()
  let req : Request = {
    method: "GET",
    path: "/api/users",
    headers: Map([("Accept", "application/json")]),
    body: "",
  }
  ignore(app.respond(req))
  b.bench(() => {
    let resp = app.respond(req)
    b.keep(resp.status)
  })
}

///|
test "bench-dispatch-param" (b : @bench.T) {
  let app = make_app()
  let req : Request = {
    method: "GET",
    path: "/api/users/12345/posts/678",
    headers: Map([("Accept", "application/json")]),
    body: "",
  }
  ignore(app.respond(req))
  b.bench(() => {
    let resp = app.respond(req)
    b.keep(resp.status)
  })
}

///|
test "bench-dispatch-miss" (b : @bench.T) {
  let app = make_app()
  let req : Request = {
    method: "POST",
    path: "/api/users/12345/posts/678",
    headers: Map([("Accept", "application/json")]),
    body: "",
  }
  ignore(app.respond(req))
  b.bench(() => {
    let resp = app.respond(req)
    b.keep(resp.status)
  })
}

///|
test "bench-url-encode" (b : @bench.T) {
  let source = "hello world/foo bar?baz=qux&name=\u{4e16}\u{754c}"
  b.bench(() => {
    b.keep(url_encode(source))
  })
}

///|
test "bench-url-decode" (b : @bench.T) {
  let source = "name=%E4%B8%96%E7%95%8C+test%20foo%2Fbar&x=1"
  b.bench(() => {
    b.keep(url_decode(source))
  })
}

///|
test "bench-query" (b : @bench.T) {
  let ctx = Context::new({
    method: "GET",
    path: "/search?q=moonbit+web&page=2&sort=desc&filter=active&lang=en",
    headers: Map([]),
    body: "",
  })
  b.bench(() => {
    b.keep(ctx.query("sort"))
  })
}

///|
test "bench-mime" (b : @bench.T) {
  b.bench(() => {
    b.keep(mime_type_for("/assets/scripts/app.min.JS"))
  })
}

///|
test "bench-multipart" (b : @bench.T) {
  let boundary = "----WebKitFormBoundary7MA4YWxkTrZu0gW"
  let mut body = ""
  for i = 0; i < 8; i = i + 1 {
    body = body +
      "--" +
      boundary +
      "\r\nContent-Disposition: form-data; name=\"field" +
      i.to_string() +
      "\"\r\n\r\nvalue-value-value-value-" +
      i.to_string() +
      "\r\n"
  }
  body = body + "--" + boundary + "--\r\n"
  let content_type = "multipart/form-data; boundary=" + boundary
  b.bench(() => {
    b.keep(parse_multipart(body, content_type))
  })
}

///|
test "bench-cookie" (b : @bench.T) {
  let ctx = Context::new({
    method: "GET",
    path: "/",
    headers: Map([
      (
        "Cookie",
        "session=abcdef123456; theme=dark; lang=en-US; tracking=xyz987654321",
      ),
    ]),
    body: "",
  })
  b.bench(() => {
    b.keep(ctx.cookies())
  })
}

///|
test "bench-context-new" (b : @bench.T) {
  let req : Request = {
    method: "GET",
    path: "/api/users",
    headers: Map([("Accept", "application/json")]),
    body: "",
  }
  b.bench(() => {
    b.keep(Context::new(req))
  })
}

///|
test "bench-router-route-static" (b : @bench.T) {
  let router = create_router()
  router.add_route("GET", "/api/users", fn(ctx) { ctx.text(200, "ok") })
  router.add_route("GET", "/api/users/:id", fn(ctx) { ctx.text(200, "ok") })
  b.bench(() => {
    b.keep(router.route("GET", "/api/users"))
  })
}

///|
test "bench-router-route-param" (b : @bench.T) {
  let router = create_router()
  router.add_route("GET", "/api/users", fn(ctx) { ctx.text(200, "ok") })
  router.add_route("GET", "/api/users/:id/posts/:post", fn(ctx) {
    ctx.text(200, "ok")
  })
  b.bench(() => {
    b.keep(router.route("GET", "/api/users/12345/posts/678"))
  })
}

///|
test "bench-response-build" (b : @bench.T) {
  let ctx = Context::new({
    method: "GET",
    path: "/",
    headers: Map([]),
    body: "",
  })
  b.bench(() => {
    ctx.text(200, "hello world")
    b.keep(ctx.response.body)
  })
}

///|
fn build_multipart_body(parts : Int) -> (String, String) {
  let boundary = "----WebKitFormBoundary7MA4YWxkTrZu0gW"
  let mut body = ""
  for i = 0; i < parts; i = i + 1 {
    body = body +
      "--" +
      boundary +
      "\r\nContent-Disposition: form-data; name=\"field" +
      i.to_string() +
      "\"\r\n\r\nvalue-value-value-value-" +
      i.to_string() +
      "\r\n"
  }
  body = body + "--" + boundary + "--\r\n"
  (body, "multipart/form-data; boundary=" + boundary)
}

///|
test "bench-multipart-1" (b : @bench.T) {
  let (body, ct) = build_multipart_body(1)
  b.bench(() => {
    b.keep(@feather.parse_multipart(body, ct))
  })
}

///|
test "bench-multipart-2" (b : @bench.T) {
  let (body, ct) = build_multipart_body(2)
  b.bench(() => {
    b.keep(@feather.parse_multipart(body, ct))
  })
}
