///|
test "probe accept language region fallback" {
  let app = App::new().get("/l", fn(ctx) {
    let value = ctx.preferred_language(["en", "fr"])
    ctx.text(200, value.unwrap_or("none"))
  })
  let response = app.respond({
    method: "GET",
    path: "/l",
    headers: Map([("Accept-Language", "en-US")]),
    body: "",
  })
  println("accept-language-region: \{response.body}")
}

///|
test "probe accept with parameters" {
  let app = App::new().get("/a", fn(ctx) {
    let value = ctx.preferred_type(["text/html", "application/json"])
    ctx.text(200, value.unwrap_or("none"))
  })
  let response = app.respond({
    method: "GET",
    path: "/a",
    headers: Map([("Accept", "text/html;level=1")]),
    body: "",
  })
  println("accept-with-parameters: \{response.body}")
}

///|
test "probe accept encoding quality" {
  let app = App::new().get("/e", fn(ctx) {
    let value = ctx.preferred_encoding(["gzip", "deflate", "identity"])
    ctx.text(200, value.unwrap_or("none"))
  })
  let response = app.respond({
    method: "GET",
    path: "/e",
    headers: Map([("Accept-Encoding", "gzip;q=0.5, deflate;q=0.8")]),
    body: "",
  })
  println("accept-encoding-quality: \{response.body}")
}

///|
async test "probe static precompressed" {
  let dir = @fs.tmpdir(prefix="feather-probe-static")
  @fs.write_file(dir + "/asset.txt", "plain body")
  @fs.write_file(dir + "/asset.txt.gz", "gzipped body")
  let app = App::new().static_files(
    "/assets",
    dir,
    precompressed=true,
  )
  with_server(app, client => {
    let response = client.get(
      "/assets/asset.txt",
      extra_headers=Map([("Accept-Encoding", "gzip")]),
    )
    println(
      "static precompressed: code=\{response.code} ce=\{response.headers.get("Content-Encoding")} vary=\{response.headers.get("Vary")}",
    )
    println("static precompressed body: \{client.read_all().text()}")
  })
  @fs.rmdir(dir, recursive=true)
}

///|
test "probe csrf rotation" {
  let store = SessionStore::new()
  let app = App::new()
    .use(middleware_session(store))
    .use(middleware_csrf())
    .get("/token", fn(ctx) {
      ctx.text(200, ctx.csrf_token())
    })
    .post("/submit", fn(ctx) {
      ctx.text(200, "accepted")
    })
  let token_response = app.respond({
    method: "GET",
    path: "/token",
    headers: Map([]),
    body: "",
  })
  let token = token_response.body
  let accepted = app.respond({
    method: "POST",
    path: "/submit",
    headers: Map([("X-CSRF-Token", token)]),
    body: "",
  })
  println("csrf token: \{token} accepted=\{accepted.status}")
}

///|
test "probe if match star" {
  let app = App::new().get("/p", fn(ctx) {
    ctx.set_header("ETag", "\"v1\"")
    ctx.text(200, "body")
  })
  let response = app.respond({
    method: "GET",
    path: "/p",
    headers: Map([("If-Match", "*")]),
    body: "",
  })
  println("if-match-star: status=\{response.status}")
}

///|
test "probe if match weak etag" {
  let app = App::new().get("/p", fn(ctx) {
    ctx.set_header("ETag", "W/\"v1\"")
    ctx.text(200, "body")
  })
  let response = app.respond({
    method: "GET",
    path: "/p",
    headers: Map([("If-Match", "W/\"v1\"")]),
    body: "",
  })
  println("if-match-weak: status=\{response.status}")
}

///|
test "probe if unmodified since" {
  let app = App::new().get("/p", fn(ctx) {
    ctx.set_header("Last-Modified", "Wed, 21 Oct 2015 07:28:00 GMT")
    ctx.text(200, "body")
  })
  let response = app.respond({
    method: "GET",
    path: "/p",
    headers: Map([("If-Unmodified-Since", "Wed, 21 Oct 2015 07:28:00 GMT")]),
    body: "",
  })
  println("if-unmodified-since: status=\{response.status}")
}

///|
test "probe full url with forwarded proto" {
  let app = App::new().trust_proxy(1).get("/u", fn(ctx) {
    ctx.text(200, ctx.full_url())
  })
  let response = app.respond({
    method: "GET",
    path: "/u",
    headers: Map([
      ("Host", "example.com"),
      ("X-Forwarded-Proto", "https"),
    ]),
    body: "",
  })
  println("full-url-forwarded: \{response.body}")
}

///|
test "probe content type parameter case" {
  let app = App::new().post("/c", fn(ctx) {
    let value = ctx.content_type_parameter("CharSet")
    ctx.text(200, value.unwrap_or("none"))
  })
  let response = app.respond({
    method: "POST",
    path: "/c",
    headers: Map([("Content-Type", "text/plain; charset=utf-8")]),
    body: "x",
  })
  println("content-type-parameter-case: \{response.body}")
}
