///|
fn scratch_time_it(name : String, iterations : Int, f : () -> Unit) -> Unit {
  for i = 0; i < 200; i = i + 1 {
    f()
  }
  let start = @async.now()
  for i = 0; i < iterations; i = i + 1 {
    f()
  }
  let elapsed = @async.now() - start
  let per_op = elapsed.to_double() * 1000000.0 / iterations.to_double()
  println("\{name}: \{per_op} ns/op (\{elapsed}ms / \{iterations})")
}

///|
fn scratch_app() -> App {
  let app = App::new()
  ignore(app.get("/", fn(ctx) { ctx.text(200, "hello") }))
  ignore(app.get("/api/users", fn(ctx) {
    ctx.json_value(200, Json::object(Map([])))
  }))
  ignore(app.get("/api/users/:id", fn(ctx) { ctx.text(200, ctx.param("id")) }))
  ignore(app.get("/api/users/:id/posts/:post", fn(ctx) {
    ctx.text(200, ctx.param("id") + ":" + ctx.param("post"))
  }))
  ignore(app.post("/api/users", fn(ctx) { ctx.json_value(200, Json::object(Map([]))) }))
  ignore(app.get("/static/*path", fn(ctx) { ctx.text(200, ctx.param("path")) }))
  app
}

///|
fn scratch_multipart_body() -> (String, String) {
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
  (body, "multipart/form-data; boundary=" + boundary)
}

///|
test "scratch-timings" {
  let app = scratch_app()
  let static_req : Request = {
    method: "GET",
    path: "/api/users",
    headers: Map([("Accept", "application/json")]),
    body: "",
  }
  let param_req : Request = {
    method: "GET",
    path: "/api/users/12345/posts/678",
    headers: Map([("Accept", "application/json")]),
    body: "",
  }
  let miss_req : Request = {
    method: "POST",
    path: "/api/users/12345/posts/678",
    headers: Map([("Accept", "application/json")]),
    body: "",
  }
  ignore(app.respond(static_req))
  ignore(app.respond(param_req))
  ignore(app.respond(miss_req))
  scratch_time_it("respond-static", 20000, fn() {
    ignore(app.respond(static_req))
  })
  scratch_time_it("respond-param", 20000, fn() {
    ignore(app.respond(param_req))
  })
  scratch_time_it("respond-miss", 20000, fn() {
    ignore(app.respond(miss_req))
  })
  let text_app = App::new()
  ignore(text_app.get("/api/users", fn(ctx) { ctx.text(200, "hello") }))
  ignore(text_app.get("/api/users/:id", fn(ctx) { ctx.text(200, ctx.param("id")) }))
  let json_req : Request = {
    method: "GET",
    path: "/api/users",
    headers: Map([("Accept", "application/json")]),
    body: "",
  }
  ignore(text_app.respond(json_req))
  scratch_time_it("respond-static-textroute", 20000, fn() {
    ignore(text_app.respond(json_req))
  })
  let plain_app = App::new()
  ignore(plain_app.get("/api/users", fn(ctx) { ctx.text(200, "hello") }))
  ignore(plain_app.respond(json_req))
  scratch_time_it("respond-single-route", 20000, fn() {
    ignore(plain_app.respond(json_req))
  })
  let empty_json = Json::object(Map([]))
  scratch_time_it("json-stringify-empty", 2000000, fn() {
    ignore(empty_json.stringify())
  })
  scratch_time_it("json-value-call", 2000000, fn() {
    let c = Context::new(json_req)
    c.json_value(200, Json::object(Map([])))
  })
  let clone_app = App::new()
  ignore(clone_app.get("/", fn(ctx) { ctx.text(200, "hello") }))
  ignore(clone_app.get("/api/users", fn(ctx) {
    ctx.json_value(200, Json::object(Map([])))
  }))
  ignore(clone_app.get("/api/users/:id", fn(ctx) { ctx.text(200, ctx.param("id")) }))
  ignore(clone_app.get("/api/users/:id/posts/:post", fn(ctx) {
    ctx.text(200, ctx.param("id") + ":" + ctx.param("post"))
  }))
  ignore(clone_app.post("/api/users", fn(ctx) {
    ctx.json_value(200, Json::object(Map([])))
  }))
  ignore(clone_app.get("/static/*path", fn(ctx) { ctx.text(200, ctx.param("path")) }))
  ignore(clone_app.respond(json_req))
  scratch_time_it("respond-clone-allroutes", 20000, fn() {
    ignore(clone_app.respond(json_req))
  })
  let clone_dyn = App::new()
  ignore(clone_dyn.get("/api/users", fn(ctx) {
    ctx.json_value(200, Json::object(Map([])))
  }))
  ignore(clone_dyn.get("/api/users/:id", fn(ctx) { ctx.text(200, ctx.param("id")) }))
  ignore(clone_dyn.respond(json_req))
  scratch_time_it("respond-clone-one-dynamic", 20000, fn() {
    ignore(clone_dyn.respond(json_req))
  })
  let clone_wild = App::new()
  ignore(clone_wild.get("/api/users", fn(ctx) {
    ctx.json_value(200, Json::object(Map([])))
  }))
  ignore(clone_wild.get("/static/*path", fn(ctx) { ctx.text(200, ctx.param("path")) }))
  ignore(clone_wild.respond(json_req))
  scratch_time_it("respond-clone-one-wildcard", 20000, fn() {
    ignore(clone_wild.respond(json_req))
  })
  scratch_time_it("respond-static-again", 20000, fn() {
    ignore(app.respond(static_req))
  })
  scratch_time_it("respond-clone-again", 20000, fn() {
    ignore(clone_app.respond(json_req))
  })
  scratch_time_it("respond-static-again2", 100000, fn() {
    ignore(app.respond(static_req))
  })
  let full_router = create_router()
  full_router.add_route("GET", "/", fn(ctx) { ctx.text(200, "hello") })
  full_router.add_route("GET", "/api/users", fn(ctx) { ctx.text(200, "hello") })
  full_router.add_route("GET", "/api/users/:id", fn(ctx) { ctx.text(200, "id") })
  full_router.add_route("GET", "/api/users/:id/posts/:post", fn(ctx) {
    ctx.text(200, "id")
  })
  full_router.add_route("POST", "/api/users", fn(ctx) { ctx.text(200, "x") })
  full_router.add_route("GET", "/static/*path", fn(ctx) { ctx.text(200, "x") })
  ignore(full_router.route("GET", "/api/users"))
  scratch_time_it("full-router-route-static", 500000, fn() {
    ignore(full_router.route("GET", "/api/users"))
  })
  let dctx = Context::new(json_req)
  full_router.dispatch(dctx) catch {
    _ => ()
  }
  scratch_time_it("full-router-dispatch", 500000, fn() {
    full_router.dispatch(dctx) catch {
      _ => ()
    }
  })
  let json_handler : (Context) -> Unit = fn(ctx) {
    ctx.json_value(200, Json::object(Map([])))
  }
  let text_handler : (Context) -> Unit = fn(ctx) { ctx.text(200, "hello") }
  let probe_ctx = Context::new(json_req)
  json_handler(probe_ctx)
  scratch_time_it("handler-json-inline", 2000000, fn() {
    json_handler(probe_ctx)
  })
  scratch_time_it("handler-text-inline", 2000000, fn() {
    text_handler(probe_ctx)
  })
  let json_only_app = App::new()
  ignore(json_only_app.get("/api/users", fn(ctx) { ctx.json_value(200, Json::object(Map([]))) }))
  ignore(json_only_app.respond(json_req))
  scratch_time_it("respond-json-onlyroute", 20000, fn() {
    ignore(json_only_app.respond(json_req))
  })
  let router = create_router()
  router.add_route("GET", "/api/users", fn(ctx) { ctx.text(200, "ok") })
  router.add_route("GET", "/api/users/:id/posts/:post", fn(ctx) { ctx.text(200, "ok") })
  scratch_time_it("router-route-static", 500000, fn() {
    ignore(router.route("GET", "/api/users"))
  })
  scratch_time_it("router-route-param", 30000, fn() {
    ignore(router.route("GET", "/api/users/12345/posts/678"))
  })
  scratch_time_it("url-encode", 500000, fn() {
    ignore(
      url_encode("hello world/foo bar?baz=qux&name=\u{4e16}\u{754c}"),
    )
  })
  scratch_time_it("url-decode", 500000, fn() {
    ignore(
      url_decode("name=%E4%B8%96%E7%95%8C+test%20foo%2Fbar&x=1"),
    )
  })
  let qctx = Context::new({
    method: "GET",
    path: "/search?q=moonbit+web&page=2&sort=desc&filter=active&lang=en",
    headers: Map([]),
    body: "",
  })
  scratch_time_it("query", 10000000, fn() {
    ignore(qctx.query("sort"))
  })
  let cctx = Context::new({
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
  scratch_time_it("cookies", 10000000, fn() {
    ignore(cctx.cookies())
  })
  scratch_time_it("cookie-one", 10000000, fn() {
    ignore(cctx.cookie("tracking"))
  })
  scratch_time_it("cookie-miss", 10000000, fn() {
    ignore(cctx.cookie("missing"))
  })
  scratch_time_it("mime", 10000000, fn() {
    ignore(mime_type_for("/assets/scripts/app.min.JS"))
  })
  scratch_time_it("format-date", 500000, fn() {
    ignore(format_http_date(1750000000L))
  })
  scratch_time_it("parse-date", 500000, fn() {
    ignore(parse_http_date("Tue, 15 Jun 2025 10:00:00 GMT"))
  })
  scratch_time_it("base64-encode", 500000, fn() {
    ignore(base64_encode(@utf8.encode("hello world, this is a test payload for base64")))
  })
  scratch_time_it("base64-decode", 500000, fn() {
    ignore(
      base64_decode(
        "aGVsbG8gd29ybGQsIHRoaXMgaXMgYSB0ZXN0IHBheWxvYWQgZm9yIGJhc2U2NA==",
      ),
    )
  })
  let (mp_body, mp_ct) = scratch_multipart_body()
  scratch_time_it("multipart-8", 5000, fn() {
    ignore(parse_multipart(mp_body, mp_ct))
  })
  scratch_time_it("context-new", 10000000, fn() {
    ignore(Context::new(static_req))
  })
  scratch_time_it("status-text", 10000000, fn() {
    ignore(status_text(404))
  })
  let md = "\u{4e16}\u{754c}"
  let md_ok = Context::new({
    method: "GET",
    path: "/",
    headers: Map([("Header", md)]),
    body: "",
  })
  let text_app = App::new()
  ignore(text_app.get("/api/users", fn(ctx) { ctx.text(200, "hello") }))
  ignore(text_app.get("/api/users/:id", fn(ctx) { ctx.text(200, ctx.param("id")) }))
  let text_req : Request = {
    method: "GET",
    path: "/api/users",
    headers: Map([("Accept", "application/json")]),
    body: "",
  }
  let text_param_req : Request = {
    method: "GET",
    path: "/api/users/12345",
    headers: Map([("Accept", "application/json")]),
    body: "",
  }
  ignore(text_app.respond(text_req))
  scratch_time_it("respond-text-static", 200000, fn() {
    ignore(text_app.respond(text_req))
  })
  scratch_time_it("respond-text-param", 200000, fn() {
    ignore(text_app.respond(text_param_req))
  })
  scratch_time_it("json-value-empty", 1000000, fn() {
    ignore(qctx.response.headers.set("Content-Type", "application/json; charset=utf-8"))
  })
  scratch_time_it("param-lookup-map", 1000000, fn() {
    ignore(qctx.state.get("param:id"))
  })
  scratch_time_it("param-lookup-miss", 1000000, fn() {
    ignore(qctx.state.get("param:id2"))
  })
  scratch_time_it("param-concat", 1000000, fn() {
    ignore(PARAM_PREFIX + "id")
  })
  scratch_time_it("header-unicode", 10000000, fn() {
    ignore(md_ok.header("Missing-Key"))
  })
}
