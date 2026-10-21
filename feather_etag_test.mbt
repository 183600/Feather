///|
let etag_key : @http.CaseInsensitiveString = @http.CaseInsensitiveString("ETag")

///|
let if_none_match_key : @http.CaseInsensitiveString = @http.CaseInsensitiveString(
  "If-None-Match",
)

///|
let etag_accept_encoding_key : @http.CaseInsensitiveString = @http.CaseInsensitiveString(
  "Accept-Encoding",
)

///|
let etag_content_encoding_key : @http.CaseInsensitiveString = @http.CaseInsensitiveString(
  "Content-Encoding",
)

///|
async test "App etag adds a validator and answers if-none-match" {
  let app = @feather.App::new()
    .etag()
    .get("/api", fn(ctx) { ctx.json(200, { "ok": "true" }) })
  with_server(app, client => {
    let first = client.get("/api")
    assert_eq(first.code, 200)
    let etag = first.headers.get(etag_key).unwrap()
    assert_true(etag.has_prefix("\""))
    assert_true(etag.has_suffix("\""))
    assert_eq(client.read_all().text(), "{\"ok\":\"true\"}")
    let second = client.get(
      "/api",
      extra_headers=Map([(if_none_match_key, etag)]),
    )
    assert_eq(second.code, 304)
    assert_eq(second.headers.get(etag_key), Some(etag))
    assert_eq(client.read_all().text(), "")
  })
}

///|
async test "App etag honors weak and wildcard validators" {
  let app = @feather.App::new()
    .etag()
    .get("/api", fn(ctx) { ctx.text(200, "hello") })
  with_server(app, client => {
    let first = client.get("/api")
    let etag = first.headers.get(etag_key).unwrap()
    ignore(client.read_all())
    let weak = client.get(
      "/api",
      extra_headers=Map([(if_none_match_key, "W/" + etag)]),
    )
    assert_eq(weak.code, 304)
    ignore(client.read_all())
    let star = client.get("/api", extra_headers=Map([(if_none_match_key, "*")]))
    assert_eq(star.code, 304)
    ignore(client.read_all())
  })
}

///|
async test "App etag changes with the response body" {
  let app = @feather.App::new()
    .etag()
    .get("/api/:v", fn(ctx) { ctx.text(200, ctx.param("v")) })
  with_server(app, client => {
    let one = client.get("/api/one")
    let etag_one = one.headers.get(etag_key).unwrap()
    ignore(client.read_all())
    let two = client.get("/api/two")
    let etag_two = two.headers.get(etag_key).unwrap()
    ignore(client.read_all())
    assert_true(etag_one != etag_two)
    let replay = client.get(
      "/api/one",
      extra_headers=Map([(if_none_match_key, etag_one)]),
    )
    assert_eq(replay.code, 304)
    ignore(client.read_all())
  })
}

///|
async test "App etag respects explicit validators and no-store" {
  let app = @feather.App::new()
    .etag()
    .get("/custom", fn(ctx) {
      ctx.set_header("ETag", "\"custom\"")
      ctx.text(200, "hi")
    })
    .get("/nostore", fn(ctx) {
      ctx.set_header("Cache-Control", "no-store")
      ctx.text(200, "hi")
    })
    .get("/empty", fn(ctx) { ctx.no_content() })
  with_server(app, client => {
    let custom = client.get("/custom")
    assert_eq(custom.headers.get(etag_key), Some("\"custom\""))
    assert_eq(client.read_all().text(), "hi")
    let custom_hit = client.get(
      "/custom",
      extra_headers=Map([(if_none_match_key, "\"custom\"")]),
    )
    assert_eq(custom_hit.code, 304)
    ignore(client.read_all())
    let no_store = client.get("/nostore")
    assert_eq(no_store.headers.get(etag_key), None)
    ignore(client.read_all())
    let empty = client.get("/empty")
    assert_eq(empty.code, 204)
    assert_eq(empty.headers.get(etag_key), None)
    ignore(client.read_all())
    let missing = client.get("/missing")
    assert_eq(missing.code, 404)
    assert_eq(missing.headers.get(etag_key), None)
    ignore(client.read_all())
  })
}

///|
async test "App etag combines with compression" {
  let payload = "feather etag payload ".repeat(64)
  let app = @feather.App::new()
    .etag()
    .compress(min_size=16)
    .get("/big", fn(ctx) { ctx.text(200, payload) })
  with_server(app, client => {
    let first = client.get(
      "/big",
      extra_headers=Map([(etag_accept_encoding_key, "gzip")]),
    )
    assert_eq(first.headers.get(etag_content_encoding_key), Some("gzip"))
    let etag = first.headers.get(etag_key).unwrap()
    ignore(client.read_all())
    let second = client.get(
      "/big",
      extra_headers=Map([
        (etag_accept_encoding_key, "gzip"),
        (if_none_match_key, etag),
      ]),
    )
    assert_eq(second.code, 304)
    ignore(client.read_all())
    let identity = client.get(
      "/big",
      extra_headers=Map([(etag_accept_encoding_key, "identity")]),
    )
    assert_true(identity.headers.get(etag_key).unwrap() != etag)
    ignore(client.read_all())
  })
}

///|
async test "feather facade enables etag" {
  let feather = @feather.create_feather({
      host: "127.0.0.1",
      port: 0,
      timeout: 0,
    })
    .etag()
    .get("/api", fn(ctx) { ctx.text(200, "hello") })
  with_server(feather.app, client => {
    let first = client.get("/api")
    let etag = first.headers.get(etag_key).unwrap()
    ignore(client.read_all())
    let second = client.get(
      "/api",
      extra_headers=Map([(if_none_match_key, etag)]),
    )
    assert_eq(second.code, 304)
    ignore(client.read_all())
  })
}

///|
async test "precondition failure drops the compressed encoding" {
  let payload = "feather compression payload ".repeat(64)
  let app = @feather.App::new()
    .etag()
    .compress(min_size=16)
    .get("/api", fn(ctx) {
      ctx.set_header("ETag", "\"handler\"")
      ctx.text(200, payload)
    })
  with_server(app, client => {
    let response = client.get(
      "/api",
      extra_headers=Map([
        (etag_accept_encoding_key, "gzip"),
        (@http.CaseInsensitiveString("If-Match"), "\"other\""),
      ]),
    )
    assert_eq(response.code, 412)
    assert_eq(response.headers.get(etag_content_encoding_key), None)
    assert_eq(client.read_all().text(), "412 Precondition Failed")
  })
}

///|
async test "App etag applies to non-GET responses" {
  let app = @feather.App::new()
    .etag()
    .post("/api", fn(ctx) { ctx.text(200, "created") })
  with_server(app, client => {
    let response = client.post("/api", "")
    assert_eq(response.code, 200)
    assert_true(response.headers.get(etag_key) is Some(_))
    assert_eq(client.read_all().text(), "created")
  })
}

///|
async test "empty if-none-match elements never match an absent validator" {
  let app = @feather.App::new().get("/plain", fn(ctx) { ctx.text(200, "hi") })
  with_server(app, client => {
    let comma = client.get(
      "/plain",
      extra_headers=Map([(if_none_match_key, ",")]),
    )
    assert_eq(comma.code, 200)
    ignore(client.read_all())
    let empty = client.get(
      "/plain",
      extra_headers=Map([(if_none_match_key, "")]),
    )
    assert_eq(empty.code, 200)
    ignore(client.read_all())
  })
}

///|
async test "generated etag satisfies if-match next to last-modified" {
  let if_match_key : @http.CaseInsensitiveString = @http.CaseInsensitiveString(
    "If-Match",
  )
  let app = @feather.App::new()
    .etag()
    .get("/lm", fn(ctx) {
      ctx.set_header("Last-Modified", "Wed, 21 Oct 2015 07:28:00 GMT")
      ctx.text(200, "hello world")
    })
  with_server(app, client => {
    let first = client.get("/lm")
    let etag = first.headers.get(etag_key).unwrap()
    assert_eq(client.read_all().text(), "hello world")
    let matched = client.get("/lm", extra_headers=Map([(if_match_key, etag)]))
    assert_eq(matched.code, 200)
    assert_eq(client.read_all().text(), "hello world")
    let stale = client.get(
      "/lm",
      extra_headers=Map([(if_match_key, "\"stale\"")]),
    )
    assert_eq(stale.code, 412)
    assert_eq(client.read_all().text(), "412 Precondition Failed")
  })
}

///|
async test "strong if-match survives compression weakening" {
  let if_match_key : @http.CaseInsensitiveString = @http.CaseInsensitiveString(
    "If-Match",
  )
  let payload = "feather compression payload ".repeat(64)
  let app = @feather.App::new()
    .etag()
    .compress(min_size=16)
    .get("/strong", fn(ctx) {
      ctx.set_header("ETag", "\"handler\"")
      ctx.text(200, payload)
    })
  with_server(app, client => {
    let response = client.get(
      "/strong",
      extra_headers=Map([
        (etag_accept_encoding_key, "gzip"),
        (if_match_key, "\"handler\""),
      ]),
    )
    assert_eq(response.code, 200)
    assert_eq(response.headers.get(etag_key), Some("W/\"handler\""))
    assert_eq(response.headers.get(etag_content_encoding_key), Some("gzip"))
    ignore(client.read_all())
  })
}

///|
test "etag body hash matches standard FNV-1a 64" {
  let app = @feather.App::new()
    .etag()
    .get("/foobar", fn(ctx) { ctx.text(200, "foobar") })
    .get("/long", fn(ctx) { ctx.text(200, "hello world") })
  let short = app.respond({
    method: "GET",
    path: "/foobar",
    headers: Map([]),
    body: "",
  })
  assert_eq(short.status, 200)
  assert_eq(short.headers.get("ETag"), Some("\"6-85944171f73967e8\""))
  let long = app.respond({
    method: "GET",
    path: "/long",
    headers: Map([]),
    body: "",
  })
  assert_eq(long.status, 200)
  assert_eq(long.headers.get("ETag"), Some("\"11-779a65e7023cd2e7\""))
}

///|
test "etag generation skips partial content" {
  let app = @feather.App::new()
    .etag()
    .get("/partial", fn(ctx) { ctx.text(206, "partial") })
  let response = app.respond({
    method: "GET",
    path: "/partial",
    headers: Map([]),
    body: "",
  })
  assert_eq(response.status, 206)
  assert_eq(response.headers.get("ETag"), None)
}

///|
async test "generated etags evaluate if-match before if-none-match" {
  let if_match_key : @http.CaseInsensitiveString = @http.CaseInsensitiveString(
    "If-Match",
  )
  let app = @feather.App::new()
    .etag()
    .get("/guard", fn(ctx) { ctx.text(200, "guarded") })
  with_server(app, client => {
    let first = client.get("/guard")
    let etag = first.headers.get(etag_key).unwrap()
    ignore(client.read_all())
    let stale = client.get(
      "/guard",
      extra_headers=Map([(if_match_key, "\"stale\""), (if_none_match_key, "*")]),
    )
    assert_eq(stale.code, 412)
    assert_eq(client.read_all().text(), "412 Precondition Failed")
    let matched = client.get(
      "/guard",
      extra_headers=Map([(if_match_key, etag), (if_none_match_key, "*")]),
    )
    assert_eq(matched.code, 304)
    assert_eq(client.read_all().text(), "")
  })
}
