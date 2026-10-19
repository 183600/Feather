///|
fn many_headers() -> Map[String, String] {
  Map([
    ("Host", "example.com"),
    ("User-Agent", "Mozilla/5.0 (X11; Linux x86_64) probe"),
    ("Accept", "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8"),
    ("Accept-Language", "en-US,en;q=0.9"),
    ("Accept-Encoding", "gzip, deflate, br"),
    ("Connection", "keep-alive"),
    ("Cookie", "a=1; b=2; session=abcdef"),
    ("Upgrade-Insecure-Requests", "1"),
    ("Cache-Control", "max-age=0"),
    ("If-None-Match", "\"abc\""),
  ])
}

///|
test "bench respond many headers" (it : @bench.T) {
  let app = @feather.App::new().get("/users", fn(_ctx) { () })
  let req : @feather.Request = {
    method: "GET",
    path: "/users",
    headers: many_headers(),
    body: "",
  }
  it.bench(fn() { it.keep(app.respond(req)) })
}

///|
test "bench respond middleware chain" (it : @bench.T) {
  let app = @feather.App::new()
    .use(@feather.middleware_recover())
    .use(@feather.middleware_logger(log=fn(_s) { () }))
    .use(@feather.middleware_cors())
    .get("/users/:id", fn(ctx) { ctx.json(200, { "ok": "true" }) })
  let req : @feather.Request = {
    method: "GET",
    path: "/users/123",
    headers: many_headers(),
    body: "",
  }
  it.bench(fn() { it.keep(app.respond(req)) })
}

///|
test "bench urlencoded big" (it : @bench.T) {
  let body = "field1=value1&field2=value2&field3=value3&field4=value4&field5=value5&field6=value6&field7=value7&field8=value8&field9=value9&field10=value10"
  it.bench(fn() { it.keep(@feather.parse_urlencoded(body)) })
}

///|
test "bench url_for" (it : @bench.T) {
  let router = @feather.create_router()
  router.add_route("GET", "/users/:id/posts/*rest", fn(_ctx) { () })
  it.bench(fn() {
    it.keep(router.url_for("nope", params={ "id": "42", "rest": "a/b" }))
  })
}

///|
test "bench base64_decode" (it : @bench.T) {
  it.bench(fn() {
    it.keep(
      @feather.base64_decode(
        "dGhlIHF1aWNrIGJyb3duIGZveCBqdW1wcyBvdmVyIHRoZSBsYXp5IGRvZw==",
      ),
    )
  })
}

///|
test "bench signed token" (it : @bench.T) {
  it.bench(fn() {
    it.keep(@feather.signed_cookie_token("secret-key", "session", "user=42&role=admin"))
  })
}

///|
test "bench session create save get" (it : @bench.T) {
  let store = @feather.SessionStore::new()
  it.bench(fn() {
    let s = store.create()
    store.save(s)
    it.keep(store.get(s.id))
  })
}

///|
test "bench ratelimit allow" (it : @bench.T) {
  let limiter = @feather.RateLimiter::new(max=1000, window=60L)
  it.bench(fn() { it.keep(limiter.allow("127.0.0.1")) })
}

///|
test "bench mime" (it : @bench.T) {
  it.bench(fn() { it.keep(@feather.mime_type_for("assets/app.min.js")) })
}

///|
test "bench preferred_type" (it : @bench.T) {
  let ctx = @feather.Context::new({
    method: "GET",
    path: "/",
    headers: Map([
      ("Accept", "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8"),
    ]),
    body: "",
  })
  it.bench(fn() {
    it.keep(ctx.preferred_type(["application/json", "text/html", "text/plain"]))
  })
}

///|
test "bench parse multipart" (it : @bench.T) {
  let body = "--boundary\r\nContent-Disposition: form-data; name=\"field1\"\r\n\r\nvalue1\r\n--boundary\r\nContent-Disposition: form-data; name=\"file\"; filename=\"a.txt\"\r\nContent-Type: text/plain\r\n\r\nhello world\r\n--boundary--\r\n"
  it.bench(fn() {
    it.keep(@feather.parse_multipart(body, "multipart/form-data; boundary=boundary"))
  })
}

///|
test "bench static_lookup" (it : @bench.T) {
  let app = @feather.App::new().static_files("/static", "examples/hello/public")
  it.bench(fn() { it.keep(app.static_file_for("/static/index.html")) })
}

///|
test "bench url_encode unicode" (it : @bench.T) {
  it.bench(fn() { it.keep(@feather.url_encode("hello wörld 你好 🎉")) })
}

///|
test "bench context new" (it : @bench.T) {
  let headers = many_headers()
  it.bench(fn() {
    it.keep(@feather.Context::new({
      method: "GET",
      path: "/users",
      headers,
      body: "",
    }))
  })
}

///|
test "bench respond many headers no cond" (it : @bench.T) {
  let app = @feather.App::new().get("/users", fn(_ctx) { () })
  let headers = many_headers()
  ignore(headers.remove("If-None-Match"))
  let req : @feather.Request = {
    method: "GET",
    path: "/users",
    headers,
    body: "",
  }
  it.bench(fn() { it.keep(app.respond(req)) })
}

///|
test "bench respond empty handler" (it : @bench.T) {
  let app = @feather.App::new().get("/users", fn(_ctx) { () })
  let req : @feather.Request = {
    method: "GET",
    path: "/users",
    headers: Map([]),
    body: "",
  }
  it.bench(fn() { it.keep(app.respond(req)) })
}

///|
fn big_router() -> @feather.Router {
  let r = @feather.create_router()
  for i = 0; i < 500; i = i + 1 {
    r.add_route("GET", "/api/resource\{i}/detail", fn(_ctx) { () })
    r.add_route("POST", "/api/resource\{i}/detail", fn(_ctx) { () })
  }
  for i = 0; i < 100; i = i + 1 {
    r.add_route("GET", "/users/:id/posts/:post/comment/:comment", fn(_ctx) { () })
  }
  r
}

///|
test "bench router 1000 routes hit" (it : @bench.T) {
  let r = big_router()
  it.bench(fn() {
    it.keep(r.route("GET", "/api/resource499/detail"))
  })
}

///|
test "bench router miss" (it : @bench.T) {
  let r = big_router()
  it.bench(fn() { it.keep(r.route("GET", "/api/resource499/missing")) })
}

///|
test "bench router dynamic" (it : @bench.T) {
  let r = big_router()
  it.bench(fn() {
    it.keep(r.route("GET", "/users/42/posts/7/comment/99"))
  })
}

///|
test "bench router head fallback" (it : @bench.T) {
  let r = big_router()
  it.bench(fn() { it.keep(r.route("HEAD", "/api/resource55/detail")) })
}


///|
test "bench sha256 64b" (it : @bench.T) {
  let data = FixedArray::make(64, b'a').unsafe_reinterpret_as_bytes()
  it.bench(fn() { it.keep(@feather.sha256(data)) })
}

///|
test "bench sha256 1024b" (it : @bench.T) {
  let data = FixedArray::make(1024, b'a').unsafe_reinterpret_as_bytes()
  it.bench(fn() { it.keep(@feather.sha256(data)) })
}


