///|
test "format_http_date renders the rfc example date" {
  assert_eq(
    @feather.format_http_date(784111777L),
    "Sun, 06 Nov 1994 08:49:37 GMT",
  )
  assert_eq(@feather.format_http_date(0L), "Thu, 01 Jan 1970 00:00:00 GMT")
}

///|
test "parse_http_date round trips formatted dates" {
  let samples = [
    0L, 784111777L, 1000000000L, 1735689600L, 4102444800L, 951782400L,
  ]
  for sample in samples {
    let formatted = @feather.format_http_date(sample)
    assert_eq(@feather.parse_http_date(formatted), Some(sample))
  }
}

///|
test "parse_http_date rejects malformed values" {
  assert_eq(@feather.parse_http_date("not a date"), None)
  assert_eq(@feather.parse_http_date("Sun, 06 Nov 1994 08:49 GMT"), None)
  assert_eq(@feather.parse_http_date("Sun, 32 Nov 1994 08:49:37 GMT"), None)
  assert_eq(@feather.parse_http_date("Sun, 06 Foo 1994 08:49:37 GMT"), None)
  assert_eq(@feather.parse_http_date("Sun, 06 Nov 1994 25:49:37 GMT"), None)
  assert_eq(@feather.parse_http_date("Sun, 06 Nov 1994 8:49:37 GMT"), None)
  assert_eq(@feather.parse_http_date("Sun, 06 Nov 1994 08:9:37 GMT"), None)
  assert_eq(@feather.parse_http_date("Sun, 06 Nov 1994 08:49:7 GMT"), None)
  assert_eq(@feather.parse_http_date("Sun Nov  6 8:49:37 1994"), None)
}

///|
test "parse_byte_range handles the single range forms" {
  assert_eq(
    @feather.parse_byte_range("bytes=0-4", 10L)
    is @feather.ByteRangeSpec(0L, 4L),
    true,
  )
  assert_eq(
    @feather.parse_byte_range("bytes=5-", 10L) is @feather.ByteRangeSpec(5L, 9L),
    true,
  )
  assert_eq(
    @feather.parse_byte_range("bytes=-3", 10L) is @feather.ByteRangeSpec(7L, 9L),
    true,
  )
  assert_eq(
    @feather.parse_byte_range("bytes=-100", 10L)
    is @feather.ByteRangeSpec(0L, 9L),
    true,
  )
  assert_eq(
    @feather.parse_byte_range("bytes=0-100", 10L)
    is @feather.ByteRangeSpec(0L, 9L),
    true,
  )
  assert_eq(
    @feather.parse_byte_range("bytes=10-", 10L) is @feather.ByteRangeInvalid,
    true,
  )
  assert_eq(
    @feather.parse_byte_range("bytes=12-14", 10L) is @feather.ByteRangeInvalid,
    true,
  )
  assert_eq(
    @feather.parse_byte_range("bytes=-0", 10L) is @feather.ByteRangeInvalid,
    true,
  )
  assert_eq(
    @feather.parse_byte_range("bytes=-1", 0L) is @feather.ByteRangeInvalid,
    true,
  )
  assert_eq(
    @feather.parse_byte_range("bytes=0-", 0L) is @feather.ByteRangeInvalid,
    true,
  )
  assert_eq(
    @feather.parse_byte_range("bytes=5-3", 10L) is @feather.ByteRangeFull,
    true,
  )
  assert_eq(
    @feather.parse_byte_range("items=0-4", 10L) is @feather.ByteRangeFull,
    true,
  )
  assert_eq(
    @feather.parse_byte_range("bytes=0-1,4-5", 10L) is @feather.ByteRangeFull,
    true,
  )
}

///|
test "parse_byte_range handles offsets beyond 100MB" {
  let total = 1_000_000_000L
  assert_eq(
    @feather.parse_byte_range("bytes=500000000-", total)
    is @feather.ByteRangeSpec(500000000L, 999999999L),
    true,
  )
  assert_eq(
    @feather.parse_byte_range("bytes=200000000-300000000", total)
    is @feather.ByteRangeSpec(200000000L, 300000000L),
    true,
  )
  assert_eq(
    @feather.parse_byte_range("bytes=-600000000", total)
    is @feather.ByteRangeSpec(400000000L, 999999999L),
    true,
  )
  assert_eq(
    @feather.parse_byte_range("bytes=1000000000-", total)
    is @feather.ByteRangeInvalid,
    true,
  )
}

///|
test "fresh matches etags containing commas and lists" {
  let make = fn(header) {
    @feather.Context::new({
      method: "GET",
      path: "/",
      headers: Map([("If-None-Match", header)]),
      body: "",
    })
  }
  let single = make("\"a,b\"")
  assert_true(single.fresh("\"a,b\""))
  assert_true(single.fresh("W/\"a,b\""))
  assert_false(single.fresh("\"a,c\""))
  let listed = make("\"x\", W/\"a,b\"")
  assert_true(listed.fresh("\"a,b\""))
  assert_true(listed.fresh("\"x\""))
  assert_false(listed.fresh("\"a\""))
  assert_true(make("*").fresh("\"a,b\""))
}

///|
test "Context bytes records a binary payload" {
  let ctx = @feather.create_context()
  ctx.bytes(200, b"\x00\x01\xfe\xff", content_type="application/octet-stream")
  assert_eq(ctx.response.status, 200)
  assert_eq(
    ctx.response.headers.get("Content-Type"),
    Some("application/octet-stream"),
  )
  assert_eq(ctx.response.body, "")
  assert_eq(ctx.response.data, Some(b"\x00\x01\xfe\xff"))
  ctx.text(200, "text wins")
  assert_eq(ctx.response.body, "text wins")
  assert_eq(ctx.response.data, None)
}

///|
test "Context add_cookie records several cookies" {
  let ctx = @feather.create_context()
  ctx.add_cookie("a", "1", path="/")
  ctx.add_cookie("b", "2", max_age=30L, http_only=true)
  assert_eq(ctx.response.cookies.length(), 2)
  ctx.clear_cookie("a", path="/")
  assert_eq(ctx.response.cookies.length(), 3)
  assert_eq(
    ctx.response.headers.get("Set-Cookie"),
    Some("a=; Path=/; Max-Age=0"),
  )
}

///|
test "middleware logger with duration reports timing" {
  let lines : Array[String] = []
  let app = @feather.App::new()
    .use(
      @feather.middleware_logger(
        log=line => lines.push(line),
        with_duration=true,
      ),
    )
    .get("/timed", fn(ctx) { ctx.text(200, "ok") })
  ignore(
    app.respond({ method: "GET", path: "/timed", headers: Map([]), body: "", }),
  )
  assert_eq(lines.length(), 1)
  assert_true(lines[0].has_prefix("[200] GET /timed ("))
  assert_true(lines[0].has_suffix("ms)"))
}

///|
test "middleware logger records failed requests" {
  let lines : Array[String] = []
  let app = @feather.App::new()
    .use(@feather.middleware_logger(log=line => lines.push(line)))
    .get("/boom", fn(_ctx) raise { raise Failure("kaboom") })
  let response = app.respond({
    method: "GET",
    path: "/boom",
    headers: Map([]),
    body: "",
  })
  assert_eq(response.status, 500)
  assert_eq(lines.length(), 1)
  assert_eq(lines[0], "[500] GET /boom")
}

///|
test "middleware cors supports credentials and preflight options" {
  let app = @feather.App::new()
    .use(
      @feather.middleware_cors(
        allow_origin="https://example.com",
        allow_methods="GET, POST",
        allow_headers="X-Token",
        expose_headers="X-Total",
        allow_credentials=true,
        max_age=600,
      ),
    )
    .get("/x", fn(ctx) { ctx.text(200, "ok") })
  let ctx = @feather.create_context()
  app.handle(ctx)
  assert_eq(
    ctx.response.headers.get("Access-Control-Allow-Origin"),
    Some("https://example.com"),
  )
  assert_eq(
    ctx.response.headers.get("Access-Control-Allow-Credentials"),
    Some("true"),
  )
  assert_eq(
    ctx.response.headers.get("Access-Control-Expose-Headers"),
    Some("X-Total"),
  )
  assert_eq(ctx.response.headers.get("Vary"), Some("Origin, Accept"))
  let preflight = @feather.Context::new({
    method: "OPTIONS",
    path: "/x",
    headers: Map([]),
    body: "",
  })
  app.handle(preflight)
  assert_eq(preflight.response.status, 204)
  assert_eq(
    preflight.response.headers.get("Access-Control-Allow-Methods"),
    Some("GET, POST"),
  )
  assert_eq(
    preflight.response.headers.get("Access-Control-Allow-Headers"),
    Some("X-Token"),
  )
  assert_eq(
    preflight.response.headers.get("Access-Control-Max-Age"),
    Some("600"),
  )
}

///|
async test "server sends binary response bytes" {
  let app = @feather.App::new().get("/blob", fn(ctx) {
    ctx.bytes(200, b"\x00\x01\xfe\xff", content_type="application/octet-stream")
  })
  with_server(app, client => {
    let response = client.get("/blob")
    assert_eq(response.code, 200)
    assert_eq(
      response.headers.get(@http.CaseInsensitiveString("Content-Length")),
      Some("4"),
    )
    assert_eq(client.read_all().binary(), b"\x00\x01\xfe\xff")
  })
}

///|
async test "server sends every cookie set on a response" {
  let app = @feather.App::new().get("/login", fn(ctx) {
    ctx.set_cookie("session", "abc", path="/")
    ctx.set_cookie("theme", "dark", max_age=60L, http_only=true)
    ctx.text(200, "ok")
  })
  with_server(app, client => {
    let response = client.get("/login")
    assert_eq(response.code, 200)
    assert_eq(response.cookies.length(), 2)
    let joined = response.cookies
      .map(cookie => cookie.to_json().stringify())
      .join(",")
    assert_true(joined.contains("session"))
    assert_true(joined.contains("theme"))
    ignore(client.read_all())
  })
}

///|
async test "server serves conditional static responses" {
  let dir = @fs.tmpdir(prefix="feather-static-cond")
  @fs.write_file(dir + "/style.css", "body { color: blue; }")
  let app = @feather.App::new().static_files("/assets", dir)
  with_server(app, client => {
    let first = client.get("/assets/style.css")
    assert_eq(first.code, 200)
    let etag = match first.headers.get(@http.CaseInsensitiveString("ETag")) {
      Some(etag) => etag
      None => fail("missing ETag")
    }
    let last_modified = match
      first.headers.get(@http.CaseInsensitiveString("Last-Modified")) {
      Some(value) => value
      None => fail("missing Last-Modified")
    }
    assert_eq(
      first.headers.get(@http.CaseInsensitiveString("Accept-Ranges")),
      Some("bytes"),
    )
    assert_eq(client.read_all().text(), "body { color: blue; }")
    let revalidated = client.get(
      "/assets/style.css",
      extra_headers=Map([(@http.CaseInsensitiveString("If-None-Match"), etag)]),
    )
    assert_eq(revalidated.code, 304)
    assert_eq(client.read_all().text(), "")
    let by_date = client.get(
      "/assets/style.css",
      extra_headers=Map([
        (@http.CaseInsensitiveString("If-Modified-Since"), last_modified),
      ]),
    )
    assert_eq(by_date.code, 304)
    ignore(client.read_all())
  })
  @fs.rmdir(dir, recursive=true)
}

///|
async test "server serves byte ranges" {
  let dir = @fs.tmpdir(prefix="feather-static-range")
  @fs.write_file(dir + "/digits.txt", "0123456789")
  let app = @feather.App::new().static_files("/assets", dir)
  with_server(app, client => {
    let ranged = client.get(
      "/assets/digits.txt",
      extra_headers=Map([(@http.CaseInsensitiveString("Range"), "bytes=2-5")]),
    )
    assert_eq(ranged.code, 206)
    assert_eq(
      ranged.headers.get(@http.CaseInsensitiveString("Content-Range")),
      Some("bytes 2-5/10"),
    )
    assert_eq(
      ranged.headers.get(@http.CaseInsensitiveString("Content-Length")),
      Some("4"),
    )
    assert_eq(client.read_all().text(), "2345")
    let suffix = client.get(
      "/assets/digits.txt",
      extra_headers=Map([(@http.CaseInsensitiveString("Range"), "bytes=-3")]),
    )
    assert_eq(suffix.code, 206)
    assert_eq(client.read_all().text(), "789")
    let invalid = client.get(
      "/assets/digits.txt",
      extra_headers=Map([(@http.CaseInsensitiveString("Range"), "bytes=99-")]),
    )
    assert_eq(invalid.code, 416)
    assert_eq(
      invalid.headers.get(@http.CaseInsensitiveString("Content-Range")),
      Some("bytes */10"),
    )
    ignore(client.read_all())
  })
  @fs.rmdir(dir, recursive=true)
}

///|
async test "server honors cache control on static mounts" {
  let dir = @fs.tmpdir(prefix="feather-static-cache")
  @fs.write_file(dir + "/app.js", "console.log(1)")
  let app = @feather.App::new().static_files("/assets", dir, max_age=3600)
  with_server(app, client => {
    let response = client.get("/assets/app.js")
    assert_eq(response.code, 200)
    assert_eq(
      response.headers.get(@http.CaseInsensitiveString("Cache-Control")),
      Some("public, max-age=3600"),
    )
    ignore(client.read_all())
  })
  @fs.rmdir(dir, recursive=true)
}

///|
async test "server redirects directory requests to a trailing slash" {
  let dir = @fs.tmpdir(prefix="feather-static-dir")
  @fs.mkdir(dir + "/guide")
  @fs.write_file(dir + "/guide/index.html", "<h1>guide</h1>")
  let app = @feather.App::new().static_files("/assets", dir)
  with_server(app, client => {
    let redirect = client.get("/assets/guide")
    assert_eq(redirect.code, 301)
    assert_eq(
      redirect.headers.get(@http.CaseInsensitiveString("Location")),
      Some("/assets/guide/"),
    )
    ignore(client.read_all())
    let page = client.get("/assets/guide/")
    assert_eq(page.code, 200)
    assert_eq(client.read_all().text(), "<h1>guide</h1>")
  })
  @fs.rmdir(dir, recursive=true)
}

///|
test "Context set_cookie renders same site" {
  let ctx = @feather.create_context()
  ctx.set_cookie("sid", "1", path="/", same_site="Lax")
  assert_eq(
    ctx.response.headers.get("Set-Cookie"),
    Some("sid=1; Path=/; SameSite=Lax"),
  )
  ctx.add_cookie("pref", "dark", same_site="Strict", secure=true)
  assert_eq(ctx.response.cookies.length(), 2)
}

///|
test "Context query_values collects repeated parameters" {
  let ctx = @feather.Context::new({
    method: "GET",
    path: "/search?tag=a&tag=b%20c&other=1&tag=",
    headers: Map([]),
    body: "",
  })
  assert_eq(ctx.query_values("tag").join("|"), "a|b c|")
  assert_eq(ctx.query_values("other").join("|"), "1")
  assert_eq(ctx.query_values("missing").length(), 0)
  assert_eq(@feather.create_context().query_values("tag").length(), 0)
}

///|
test "mime_type_for covers modern asset types" {
  assert_eq(
    @feather.mime_type_for("app.webmanifest"),
    "application/manifest+json; charset=utf-8",
  )
  assert_eq(
    @feather.mime_type_for("bundle.js.map"),
    "application/json; charset=utf-8",
  )
  assert_eq(
    @feather.mime_type_for("config.yaml"),
    "application/yaml; charset=utf-8",
  )
  assert_eq(
    @feather.mime_type_for("config.toml"),
    "application/toml; charset=utf-8",
  )
  assert_eq(@feather.mime_type_for("clip.webm"), "video/webm")
  assert_eq(@feather.mime_type_for("song.ogg"), "audio/ogg")
  assert_eq(@feather.mime_type_for("photo.avif"), "image/avif")
}

///|
test "mime_type_for covers office media and archive types" {
  assert_eq(@feather.mime_type_for("movie.mkv"), "video/x-matroska")
  assert_eq(
    @feather.mime_type_for("clip.m3u8"),
    "application/vnd.apple.mpegurl",
  )
  assert_eq(@feather.mime_type_for("track.flac"), "audio/flac")
  assert_eq(@feather.mime_type_for("voice.opus"), "audio/ogg")
  assert_eq(@feather.mime_type_for("scan.TIFF"), "image/tiff")
  assert_eq(@feather.mime_type_for("photo.heic"), "image/heic")
  assert_eq(
    @feather.mime_type_for("report.docx"),
    "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
  )
  assert_eq(
    @feather.mime_type_for("sheet.xlsx"),
    "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
  )
  assert_eq(
    @feather.mime_type_for("slides.pptx"),
    "application/vnd.openxmlformats-officedocument.presentationml.presentation",
  )
  assert_eq(@feather.mime_type_for("book.epub"), "application/epub+zip")
  assert_eq(@feather.mime_type_for("events.ics"), "text/calendar")
  assert_eq(@feather.mime_type_for("subs.vtt"), "text/vtt")
  assert_eq(@feather.mime_type_for("bundle.7z"), "application/x-7z-compressed")
  assert_eq(@feather.mime_type_for("archive.zst"), "application/zstd")
  assert_eq(
    @feather.mime_type_for("fonts.eot"),
    "application/vnd.ms-fontobject",
  )
}

///|
async test "server ignores ranges when if-range does not match" {
  let dir = @fs.tmpdir(prefix="feather-static-if-range")
  @fs.write_file(dir + "/digits.txt", "0123456789")
  let app = @feather.App::new().static_files("/assets", dir)
  with_server(app, client => {
    let first = client.get("/assets/digits.txt")
    let etag = match first.headers.get(@http.CaseInsensitiveString("ETag")) {
      Some(etag) => etag
      None => fail("missing ETag")
    }
    ignore(client.read_all())
    let matched = client.get(
      "/assets/digits.txt",
      extra_headers=Map([
        (@http.CaseInsensitiveString("Range"), "bytes=0-1"),
        (@http.CaseInsensitiveString("If-Range"), etag),
      ]),
    )
    assert_eq(matched.code, 206)
    assert_eq(client.read_all().text(), "01")
    let stale = client.get(
      "/assets/digits.txt",
      extra_headers=Map([
        (@http.CaseInsensitiveString("Range"), "bytes=0-1"),
        (@http.CaseInsensitiveString("If-Range"), "\"stale-etag\""),
      ]),
    )
    assert_eq(stale.code, 200)
    assert_eq(client.read_all().text(), "0123456789")
  })
  @fs.rmdir(dir, recursive=true)
}

///|
async test "server keeps cache control on revalidated responses" {
  let dir = @fs.tmpdir(prefix="feather-static-cc-304")
  @fs.write_file(dir + "/app.css", "body{}")
  let app = @feather.App::new().static_files("/assets", dir, max_age=120)
  with_server(app, client => {
    let first = client.get("/assets/app.css")
    let etag = match first.headers.get(@http.CaseInsensitiveString("ETag")) {
      Some(etag) => etag
      None => fail("missing ETag")
    }
    ignore(client.read_all())
    let revalidated = client.get(
      "/assets/app.css",
      extra_headers=Map([(@http.CaseInsensitiveString("If-None-Match"), etag)]),
    )
    assert_eq(revalidated.code, 304)
    assert_eq(
      revalidated.headers.get(@http.CaseInsensitiveString("Cache-Control")),
      Some("public, max-age=120"),
    )
    ignore(client.read_all())
  })
  @fs.rmdir(dir, recursive=true)
}

///|
async test "server keeps representation headers on revalidated queued files" {
  let dir = @fs.tmpdir(prefix="feather-file-cc-304")
  @fs.write_file(dir + "/report.css", "body{}")
  let app = @feather.App::new().get("/report.css", fn(ctx) {
    ctx.set_header("Cache-Control", "public, max-age=60")
    ctx.file(200, dir + "/report.css", download_name="report.css")
  })
  with_server(app, client => {
    let first = client.get("/report.css")
    let etag = match first.headers.get(@http.CaseInsensitiveString("ETag")) {
      Some(etag) => etag
      None => fail("missing ETag")
    }
    assert_eq(
      first.headers.get(@http.CaseInsensitiveString("Content-Disposition")),
      Some("attachment; filename=\"report.css\""),
    )
    ignore(client.read_all())
    let revalidated = client.get(
      "/report.css",
      extra_headers=Map([(@http.CaseInsensitiveString("If-None-Match"), etag)]),
    )
    assert_eq(revalidated.code, 304)
    assert_eq(
      revalidated.headers.get(@http.CaseInsensitiveString("ETag")),
      Some(etag),
    )
    assert_eq(
      revalidated.headers.get(@http.CaseInsensitiveString("Cache-Control")),
      Some("public, max-age=60"),
    )
    assert_true(
      revalidated.headers.get(@http.CaseInsensitiveString("Last-Modified"))
      is Some(_),
    )
    assert_eq(
      revalidated.headers.get(@http.CaseInsensitiveString("Content-Type")),
      None,
    )
    assert_eq(
      revalidated.headers.get(@http.CaseInsensitiveString("Content-Length")),
      None,
    )
    assert_eq(client.read_all().text(), "")
  })
  @fs.rmdir(dir, recursive=true)
}

///|
test "Context fresh and not_modified support dynamic caching" {
  let ctx = @feather.Context::new({
    method: "GET",
    path: "/api/item",
    headers: { "If-None-Match": "W/\"v1\", \"other\"" },
    body: "",
  })
  assert_true(ctx.fresh("\"v1\""))
  assert_false(ctx.fresh("\"v2\""))
  assert_false(@feather.create_context().fresh("\"v1\""))
  ctx.json(200, { "ok": "true" })
  ctx.not_modified(etag="\"v1\"", last_modified="Thu, 01 Jan 1970 00:00:00 GMT")
  assert_eq(ctx.response.status, 304)
  assert_eq(ctx.response.body, "")
  assert_eq(ctx.response.headers.get("ETag"), Some("\"v1\""))
  assert_eq(
    ctx.response.headers.get("Last-Modified"),
    Some("Thu, 01 Jan 1970 00:00:00 GMT"),
  )
  assert_eq(ctx.response.headers.get("Content-Type"), None)
}

///|
test "Router url_for appends sorted query parameters" {
  let app = @feather.App::new()
  ignore(
    app.route_named("user_posts", "GET", "/users/:id/posts", fn(ctx) {
      ctx.text(200, "p")
    }),
  )
  assert_eq(
    app.url_for("user_posts", params={ "id": "7" }, query={
      "page": "2",
      "q": "hello world",
    }),
    Some("/users/7/posts?page=2&q=hello%20world"),
  )
  assert_eq(
    app.url_for("user_posts", params={ "id": "7" }),
    Some("/users/7/posts"),
  )
  assert_eq(
    app.url_for("user_posts", params={ "id": "7" }, query={}),
    Some("/users/7/posts"),
  )
}

///|
test "Context forwarded_ip honors proxy headers" {
  let ctx = @feather.Context::new({
    method: "GET",
    path: "/",
    headers: { "X-Forwarded-For": "203.0.113.9, 10.0.0.1" },
    body: "",
  })
  assert_eq(ctx.forwarded_ip(), "203.0.113.9")
  let real_ip = @feather.Context::new({
    method: "GET",
    path: "/",
    headers: { "X-Real-IP": "198.51.100.7" },
    body: "",
  })
  assert_eq(real_ip.forwarded_ip(), "198.51.100.7")
  let direct = @feather.create_context()
  direct.state.set("remote_addr", "192.0.2.1:9000")
  assert_eq(direct.forwarded_ip(), "192.0.2.1:9000")
}

///|
async test "server ignores preconditions for non-2xx queued files" {
  let dir = @fs.tmpdir(prefix="feather-file-precondition-status")
  @fs.write_file(dir + "/nope.txt", "not found body")
  let app = @feather.App::new().get("/nope.txt", fn(ctx) {
    ctx.file(404, dir + "/nope.txt")
  })
  with_server(app, client => {
    let not_modified = client.get(
      "/nope.txt",
      extra_headers=Map([
        (@http.CaseInsensitiveString("If-None-Match"), "*"),
      ]),
    )
    assert_eq(not_modified.code, 404)
    assert_eq(client.read_all().text(), "not found body")
    let failed = client.get(
      "/nope.txt",
      extra_headers=Map([
        (@http.CaseInsensitiveString("If-Match"), "\"stale\""),
      ]),
    )
    assert_eq(failed.code, 404)
    assert_eq(client.read_all().text(), "not found body")
  })
  @fs.rmdir(dir, recursive=true)
}

///|
async test "server ignores range headers for non-200 queued files" {
  let dir = @fs.tmpdir(prefix="feather-file-range-status")
  @fs.write_file(dir + "/nope.txt", "0123456789")
  let app = @feather.App::new().get("/nope.txt", fn(ctx) {
    ctx.file(404, dir + "/nope.txt")
  })
  with_server(app, client => {
    let response = client.get(
      "/nope.txt",
      extra_headers=Map([(@http.CaseInsensitiveString("Range"), "bytes=0-3")]),
    )
    assert_eq(response.code, 404)
    assert_eq(
      response.headers.get(@http.CaseInsensitiveString("Content-Range")),
      None,
    )
    assert_eq(client.read_all().text(), "0123456789")
  })
  @fs.rmdir(dir, recursive=true)
}
