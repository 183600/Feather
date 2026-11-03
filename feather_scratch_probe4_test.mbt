///|
/// A base language range matches a more specific regional tag: `en` is a
/// prefix of `en-US`, so the server answers with `en-US` when that is the only
/// offer the client's `en` range can reach.
test "preferred_language falls back to the longest matching region" {
  let app = @feather.App::new().get("/l", fn(ctx) {
    let value = ctx.preferred_language(["en-US", "fr"])
    ctx.text(200, value.unwrap_or("none"))
  })
  let response = app.respond({
    method: "GET",
    path: "/l",
    headers: Map([("Accept-Language", "en")]),
    body: "",
  })
  assert_eq(response.status, 200)
  assert_eq(response.body, "en-US")
}

///|
/// Parameters on a media range (`text/html;level=1`) must not prevent a match.
test "preferred_type ignores parameters on media ranges" {
  let app = @feather.App::new().get("/a", fn(ctx) {
    let value = ctx.preferred_type(["text/html", "application/json"])
    ctx.text(200, value.unwrap_or("none"))
  })
  let response = app.respond({
    method: "GET",
    path: "/a",
    headers: Map([("Accept", "text/html;level=1")]),
    body: "",
  })
  assert_eq(response.status, 200)
  assert_eq(response.body, "text/html")
}

///|
/// `preferred_encoding` picks the highest quality coding the client accepts.
/// `identity` is acceptable by default, so it is omitted from the offers to
/// test the quality ordering between `gzip` and `deflate`.
test "preferred_encoding picks the highest quality coding" {
  let app = @feather.App::new().get("/e", fn(ctx) {
    let value = ctx.preferred_encoding(["gzip", "deflate"])
    ctx.text(200, value.unwrap_or("none"))
  })
  let response = app.respond({
    method: "GET",
    path: "/e",
    headers: Map([("Accept-Encoding", "gzip;q=0.5, deflate;q=0.8")]),
    body: "",
  })
  assert_eq(response.status, 200)
  assert_eq(response.body, "deflate")
}

///|
/// A precompressed `.gz` sibling is served with `Content-Encoding: gzip` when
/// the client accepts gzip.
async test "static precompressed files are served gzip-encoded" {
  let dir = @fs.tmpdir(prefix="feather-probe-static")
  @fs.write_file(dir + "/asset.txt", "plain body")
  @fs.write_file(dir + "/asset.txt.gz", "gzipped body")
  let app = @feather.App::new().static_files(
    "/assets",
    dir,
    precompressed=true,
  )
  with_server(app, client => {
    let response = client.get(
      "/assets/asset.txt",
      extra_headers=Map([("Accept-Encoding", "gzip")]),
    )
    assert_eq(response.code, 200)
    assert_eq(
      response.headers.get(@http.CaseInsensitiveString("Content-Encoding")),
      Some("gzip"),
    )
    assert_eq(client.read_all().text(), "gzipped body")
  })
  @fs.rmdir(dir, recursive=true)
}

///|
/// A CSRF token minted on a safe GET authorizes the matching unsafe POST.
test "csrf token issued on safe request authorizes the unsafe request" {
  let store = @feather.SessionStore::new()
  let chain = @feather.apply_middleware(
    [@feather.middleware_session(store), @feather.middleware_csrf()],
    fn(ctx) { ctx.text(200, ctx.csrf_token()) },
  )
  // GET mints a token and stores it in a fresh session.
  let get_ctx = @feather.Context::new({
    method: "GET",
    path: "/token",
    headers: Map([]),
    body: "",
  })
  chain(get_ctx)
  assert_eq(get_ctx.response.status, 200)
  let token = get_ctx.response.body
  assert_true(token.length() == 32)
  let session = match get_ctx.session() {
    Some(session) => session
    None => fail("expected a session")
  }
  // POST carrying that session and token is accepted.
  let post_ctx = @feather.Context::new({
    method: "POST",
    path: "/submit",
    headers: Map([
      ("Cookie", "feather_session=" + session.id),
      ("X-CSRF-Token", token),
    ]),
    body: "",
  })
  chain(post_ctx)
  assert_eq(post_ctx.response.status, 200)
}

///|
/// `If-Match: *` succeeds when the resource exists (a strong validator is
/// present) and fails with `412` when only a weak validator is present.
test "if match star on an existing resource succeeds" {
  let app = @feather.App::new().get("/p", fn(ctx) {
    ctx.set_header("ETag", "\"v1\"")
    ctx.text(200, "body")
  })
  let response = app.respond({
    method: "GET",
    path: "/p",
    headers: Map([("If-Match", "*")]),
    body: "",
  })
  assert_eq(response.status, 200)
}

///|
/// `If-Match` requires a strong validator, so a weak tag never matches.
test "if match weak etag fails" {
  let app = @feather.App::new().get("/p", fn(ctx) {
    ctx.set_header("ETag", "W/\"v1\"")
    ctx.text(200, "body")
  })
  let response = app.respond({
    method: "GET",
    path: "/p",
    headers: Map([("If-Match", "W/\"v1\"")]),
    body: "",
  })
  assert_eq(response.status, 412)
}

///|
/// `If-Unmodified-Since` matching the resource's last-modified time succeeds.
test "if unmodified since matching last modified succeeds" {
  let app = @feather.App::new().get("/p", fn(ctx) {
    ctx.set_header("Last-Modified", "Wed, 21 Oct 2015 07:28:00 GMT")
    ctx.text(200, "body")
  })
  let response = app.respond({
    method: "GET",
    path: "/p",
    headers: Map([("If-Unmodified-Since", "Wed, 21 Oct 2015 07:28:00 GMT")]),
    body: "",
  })
  assert_eq(response.status, 200)
}

///|
/// With one trusted proxy, `X-Forwarded-Proto: https` upgrades the scheme of
/// `Context::full_url`.
test "full url uses forwarded proto when trusting one proxy" {
  let app = @feather.App::new().trust_proxy(1).get("/u", fn(ctx) {
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
  assert_eq(response.status, 200)
  assert_eq(response.body, "https://example.com/u")
}

///|
/// `Content-Type` parameter lookup is case-insensitive (`CharSet` finds
/// `charset`).
test "content type parameter lookup is case insensitive" {
  let app = @feather.App::new().post("/c", fn(ctx) {
    let value = ctx.content_type_parameter("CharSet")
    ctx.text(200, value.unwrap_or("none"))
  })
  let response = app.respond({
    method: "POST",
    path: "/c",
    headers: Map([("Content-Type", "text/plain; charset=utf-8")]),
    body: "x",
  })
  assert_eq(response.status, 200)
  assert_eq(response.body, "utf-8")
}

///|
/// `Context::content_type` returns the lowercased media type without
/// parameters, so `text/plain; charset=utf-8` becomes `text/plain`.
test "content type strips parameters and lowercases" {
  let app = @feather.App::new().post("/ct", fn(ctx) {
    ctx.text(200, ctx.content_type())
  })
  let response = app.respond({
    method: "POST",
    path: "/ct",
    headers: Map([("Content-Type", "Text/Plain; Charset=UTF-8")]),
    body: "x",
  })
  assert_eq(response.status, 200)
  assert_eq(response.body, "text/plain")
}

///|
/// `Context::is_json` recognizes `application/json` and `+json` suffixes.
test "content type is_json recognizes json and structured suffixes" {
  let app = @feather.App::new()
    .post("/j", fn(ctx) { ctx.text(200, ctx.is_json().to_string()) })
    .post("/pj", fn(ctx) { ctx.text(200, ctx.is_json().to_string()) })
    .post("/t", fn(ctx) { ctx.text(200, ctx.is_json().to_string()) })
  let json = app.respond({
    method: "POST",
    path: "/j",
    headers: Map([("Content-Type", "application/json")]),
    body: "{}",
  })
  assert_eq(json.body, "true")
  let problem = app.respond({
    method: "POST",
    path: "/pj",
    headers: Map([("Content-Type", "application/problem+json")]),
    body: "{}",
  })
  assert_eq(problem.body, "true")
  let text = app.respond({
    method: "POST",
    path: "/t",
    headers: Map([("Content-Type", "text/plain")]),
    body: "hi",
  })
  assert_eq(text.body, "false")
}
