///|
async test "static middleware overrides the configured cache policy" {
  let dir = @fs.tmpdir(prefix="feather-static-middleware-cache")
  @fs.write_file(dir + "/app.js", "console.log(1)")
  let custom = "private, max-age=5, must-revalidate"
  let app = @feather.App::new().static_files_with(
    "/assets",
    dir,
    [
      fn(next) {
        fn(ctx) {
          ctx.set_header("Cache-Control", custom)
          next(ctx)
        }
      },
    ],
    max_age=3600,
  )
  let cache_control = @http.CaseInsensitiveString("Cache-Control")
  let if_none_match = @http.CaseInsensitiveString("If-None-Match")
  let range_key = @http.CaseInsensitiveString("Range")
  with_server(app, client => {
    let first = client.get("/assets/app.js")
    assert_eq(first.code, 200)
    assert_eq(first.headers.get(cache_control), Some(custom))
    let etag = first.headers.get(
      @http.CaseInsensitiveString("ETag"),
    ).unwrap()
    ignore(client.read_all())
    let revalidated = client.get(
      "/assets/app.js",
      extra_headers=Map([(if_none_match, etag)]),
    )
    assert_eq(revalidated.code, 304)
    assert_eq(revalidated.headers.get(cache_control), Some(custom))
    ignore(client.read_all())
    let ranged = client.get(
      "/assets/app.js",
      extra_headers=Map([(range_key, "bytes=0-3")]),
    )
    assert_eq(ranged.code, 206)
    assert_eq(ranged.headers.get(cache_control), Some(custom))
    ignore(client.read_all())
  })
  @fs.rmdir(dir, recursive=true)
}
