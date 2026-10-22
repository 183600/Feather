///|
test "static mounts accept an explicit cache-control policy" {
  let app = @feather.App::new().static_files(
    "/assets",
    "/srv/public",
    cache_control="public, max-age=60, immutable",
  )
  assert_eq(
    app.static_cache_control_for("/assets/app.js"),
    "public, max-age=60, immutable",
  )
}

///|
test "explicit static cache control overrides max_age" {
  let app = @feather.App::new().static_files(
    "/assets",
    "/srv/public",
    max_age=3600,
    cache_control="no-cache",
  )
  assert_eq(app.static_cache_control_for("/assets/app.js"), "no-cache")
}

///|
test "empty explicit cache control suppresses the derived header" {
  let app = @feather.App::new().static_files(
    "/assets",
    "/srv/public",
    max_age=3600,
    cache_control="",
  )
  assert_eq(app.static_cache_control_for("/assets/app.js"), "")
}

///|
test "groups forward cache_control to static mounts" {
  let app = @feather.App::new()
  ignore(
    app.group("/api").static_files_with(
      "/files",
      "/srv/files",
      [],
      cache_control="private, max-age=5",
    ),
  )
  assert_eq(
    app.static_cache_control_for("/api/files/report.pdf"),
    "private, max-age=5",
  )
}

///|
async test "server keeps a custom cache policy on static responses" {
  let dir = @fs.tmpdir(prefix="feather-static-custom-cache")
  @fs.write_file(dir + "/app.js", "console.log(1)")
  let app = @feather.App::new().static_files(
    "/assets",
    dir,
    cache_control="private, max-age=0, must-revalidate",
  )
  with_server(app, client => {
    let first = client.get("/assets/app.js")
    assert_eq(first.code, 200)
    assert_eq(
      first.headers.get(@http.CaseInsensitiveString("Cache-Control")),
      Some("private, max-age=0, must-revalidate"),
    )
    let etag = match first.headers.get(@http.CaseInsensitiveString("ETag")) {
      Some(etag) => etag
      None => fail("missing ETag")
    }
    ignore(client.read_all())
    let revalidated = client.get(
      "/assets/app.js",
      extra_headers=Map([(@http.CaseInsensitiveString("If-None-Match"), etag)]),
    )
    assert_eq(revalidated.code, 304)
    assert_eq(
      revalidated.headers.get(@http.CaseInsensitiveString("Cache-Control")),
      Some("private, max-age=0, must-revalidate"),
    )
    ignore(client.read_all())
  })
  @fs.rmdir(dir, recursive=true)
}

///|
async test "static middleware representation headers override file headers" {
  let dir = @fs.tmpdir(prefix="feather-static-validators")
  @fs.write_file(dir + "/app.js", "console.log(1)")
  let custom_etag = "\"middleware-v1\""
  let custom_last_modified = "Thu, 01 Jan 1970 00:00:00 GMT"
  let custom_content_type = "text/x-middleware"
  let app = @feather.App::new().static_files_with("/assets", dir, [
    fn(next) {
      fn(ctx) {
        ctx.set_header("ETag", custom_etag)
        ctx.set_header("Last-Modified", custom_last_modified)
        ctx.set_header("Content-Type", custom_content_type)
        next(ctx)
      }
    },
  ])
  let etag_key = @http.CaseInsensitiveString("ETag")
  let last_modified_key = @http.CaseInsensitiveString("Last-Modified")
  let if_none_match_key = @http.CaseInsensitiveString("If-None-Match")
  let if_range_key = @http.CaseInsensitiveString("If-Range")
  let range_key = @http.CaseInsensitiveString("Range")
  with_server(app, client => {
    let first = client.get("/assets/app.js")
    assert_eq(first.code, 200)
    assert_eq(first.headers.get(etag_key), Some(custom_etag))
    assert_eq(
      first.headers.get(last_modified_key),
      Some(custom_last_modified),
    )
    assert_eq(
      first.headers.get(@http.CaseInsensitiveString("Content-Type")),
      Some(custom_content_type),
    )
    assert_eq(client.read_all().text(), "console.log(1)")
    let not_modified = client.get(
      "/assets/app.js",
      extra_headers=Map([(if_none_match_key, custom_etag)]),
    )
    assert_eq(not_modified.code, 304)
    assert_eq(not_modified.headers.get(etag_key), Some(custom_etag))
    ignore(client.read_all())
    let range = client.get(
      "/assets/app.js",
      extra_headers=Map([
        (if_range_key, custom_etag),
        (range_key, "bytes=0-3"),
      ]),
    )
    assert_eq(range.code, 206)
    assert_eq(range.headers.get(etag_key), Some(custom_etag))
    assert_eq(
      range.headers.get(@http.CaseInsensitiveString("Content-Type")),
      Some(custom_content_type),
    )
    assert_eq(client.read_all().text(), "cons")
  })
  @fs.rmdir(dir, recursive=true)
}
