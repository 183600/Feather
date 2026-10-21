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
