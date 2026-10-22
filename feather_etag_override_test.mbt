///|
fn etag_override_request(headers : Map[String, String]) -> @feather.Request {
  { method: "GET", path: "/api/items", headers, body: "", }
}

///|
test "Context etag opts a response in without application-wide etags" {
  let app = @feather.App::new().get("/api/items", fn(ctx) {
    ctx.etag()
    ctx.json(200, { "item": "one" })
  })
  let first = app.respond(etag_override_request(Map([])))
  assert_eq(first.status, 200)
  let etag = match first.headers.get("ETag") {
    Some(etag) => etag
    None => fail("missing generated ETag")
  }
  let second = app.respond(etag_override_request(Map([("If-None-Match", etag)])))
  assert_eq(second.status, 304)
  assert_eq(second.body, "")
  assert_eq(second.headers.get("ETag"), Some(etag))
}

///|
test "Context etag keeps route scope when the application is not cacheable" {
  let app = @feather.App::new()
    .get("/api/items", fn(ctx) {
      ctx.etag()
      ctx.text(200, "cached")
    })
    .get("/health", fn(ctx) { ctx.text(200, "ok") })
  let cached = app.respond({
    method: "GET",
    path: "/api/items",
    headers: Map([]),
    body: "",
  })
  assert_true(cached.headers.get("ETag") is Some(_))
  let plain = app.respond({
    method: "GET",
    path: "/health",
    headers: Map([]),
    body: "",
  })
  assert_eq(plain.headers.get("ETag"), None)
}

///|
test "Context no_etag suppresses application-wide etags" {
  let app = @feather.App::new().etag().get("/secret", fn(ctx) {
    ctx.no_etag()
    ctx.text(200, "no validator here")
  })
  let first = app.respond({
    method: "GET",
    path: "/secret",
    headers: Map([]),
    body: "",
  })
  assert_eq(first.status, 200)
  assert_eq(first.headers.get("ETag"), None)
  let second = app.respond({
    method: "GET",
    path: "/secret",
    headers: Map([("If-None-Match", "\"not-the-generated-tag\"")]),
    body: "",
  })
  assert_eq(second.status, 200)
  assert_eq(second.body, "no validator here")
}

///|
test "Context no_etag preserves an explicit handler validator" {
  let app = @feather.App::new().etag().get("/manual", fn(ctx) {
    ctx.set_header("ETag", "\"manual\"")
    ctx.no_etag()
    ctx.text(200, "body")
  })
  let response = app.respond({
    method: "GET",
    path: "/manual",
    headers: Map([]),
    body: "",
  })
  assert_eq(response.headers.get("ETag"), Some("\"manual\""))
}

///|
test "Context etag still honors no-store" {
  let app = @feather.App::new().get("/private", fn(ctx) {
    ctx.etag()
    ctx.no_store()
    ctx.text(200, "private")
  })
  let response = app.respond({
    method: "GET",
    path: "/private",
    headers: Map([]),
    body: "",
  })
  assert_eq(response.headers.get("ETag"), None)
}

///|
async test "server honors Context etag and no_etag overrides" {
  let app = @feather.App::new().etag()
    .get("/api/items", fn(ctx) {
      ctx.etag()
      ctx.json(200, { "item": "one" })
    })
    .get("/secret", fn(ctx) {
      ctx.no_etag()
      ctx.text(200, "hidden")
    })
  with_server(app, client => {
    let first = client.get("/api/items")
    assert_eq(first.code, 200)
    let etag = match first.headers.get(@http.CaseInsensitiveString("ETag")) {
      Some(etag) => etag
      None => fail("missing generated ETag")
    }
    ignore(client.read_all())
    let revalidated = client.get(
      "/api/items",
      extra_headers=Map([(@http.CaseInsensitiveString("If-None-Match"), etag)]),
    )
    assert_eq(revalidated.code, 304)
    assert_eq(client.read_all().text(), "")
    let secret = client.get("/secret")
    assert_eq(secret.code, 200)
    assert_eq(
      secret.headers.get(@http.CaseInsensitiveString("ETag")),
      None,
    )
    assert_eq(client.read_all().text(), "hidden")
  })
}
