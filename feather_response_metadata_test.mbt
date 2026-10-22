///|
fn response_metadata_ctx() -> @feather.Context {
  let ctx = @feather.create_context()
  ctx.set_header("ETag", "\"stale\"")
  ctx.set_header("Last-Modified", "Wed, 21 Oct 2015 07:28:00 GMT")
  ctx.set_header("Content-Disposition", "attachment; filename=\"old.txt\"")
  ctx
}

///|
fn has_representation_metadata(ctx : @feather.Context) -> Bool {
  ctx.response.headers.get("ETag") is Some(_) ||
  ctx.response.headers.get("Last-Modified") is Some(_) ||
  ctx.response.headers.get("Content-Disposition") is Some(_)
}

///|
test "bodyless response helpers drop stale representation metadata" {
  let no_content = response_metadata_ctx()
  no_content.no_content()
  assert_false(has_representation_metadata(no_content))

  let redirect = response_metadata_ctx()
  redirect.redirect(302, "/next")
  assert_false(has_representation_metadata(redirect))
}

///|
test "automatic options drops stale representation metadata" {
  let app = @feather.App::new()
    .use(fn(next) {
      fn(ctx) {
        ctx.set_header("ETag", "\"stale\"")
        ctx.set_header("Last-Modified", "Wed, 21 Oct 2015 07:28:00 GMT")
        ctx.set_header("Content-Disposition", "attachment; filename=\"old.txt\"")
        next(ctx)
      }
    })
    .get("/resource", fn(ctx) { ctx.text(200, "ok") })
  let response = app.respond({
    method: "OPTIONS",
    path: "/resource",
    headers: Map([]),
    body: "",
  })
  assert_eq(response.status, 204)
  assert_eq(response.headers.get("ETag"), None)
  assert_eq(response.headers.get("Last-Modified"), None)
  assert_eq(response.headers.get("Content-Disposition"), None)
}

///|
test "dynamic errors drop stale representation metadata" {
  let app = @feather.App::new()
    .use(fn(next) {
      fn(ctx) {
        ctx.set_header("ETag", "\"stale\"")
        ctx.set_header("Last-Modified", "Wed, 21 Oct 2015 07:28:00 GMT")
        ctx.set_header("Content-Disposition", "attachment; filename=\"old.txt\"")
        next(ctx)
      }
    })
    .get("/boom", fn(_ctx) { raise @feather.HttpError(500, "boom") })
  let response = app.respond({
    method: "GET",
    path: "/boom",
    headers: Map([]),
    body: "",
  })
  assert_eq(response.status, 500)
  assert_eq(response.headers.get("ETag"), None)
  assert_eq(response.headers.get("Last-Modified"), None)
  assert_eq(response.headers.get("Content-Disposition"), None)
}

///|
test "middleware denials drop stale representation metadata" {
  let app = @feather.App::new()
    .use(fn(next) {
      fn(ctx) {
        ctx.set_header("ETag", "\"stale\"")
        ctx.set_header("Last-Modified", "Wed, 21 Oct 2015 07:28:00 GMT")
        ctx.set_header("Content-Disposition", "attachment; filename=\"old.txt\"")
        next(ctx)
      }
    })
    .use(@feather.middleware_body_limit(0))
    .post("/upload", fn(ctx) { ctx.text(200, "ok") })
  let response = app.respond({
    method: "POST",
    path: "/upload",
    headers: Map([]),
    body: "payload",
  })
  assert_eq(response.status, 413)
  assert_eq(response.headers.get("ETag"), None)
  assert_eq(response.headers.get("Last-Modified"), None)
  assert_eq(response.headers.get("Content-Disposition"), None)
}

///|
async test "static redirects drop stale representation metadata" {
  let dir = @fs.tmpdir(prefix="feather-static-redirect-metadata")
  @fs.mkdir(dir + "/guide")
  @fs.write_file(dir + "/guide/index.html", "guide")
  let app = @feather.App::new().static_files_with("/assets", dir, [
    fn(next) {
      fn(ctx) {
        ctx.set_header("ETag", "\"stale\"")
        ctx.set_header("Last-Modified", "Wed, 21 Oct 2015 07:28:00 GMT")
        ctx.set_header("Content-Disposition", "attachment; filename=\"old.txt\"")
        next(ctx)
      }
    },
  ])
  with_server(app, client => {
    let response = client.get("/assets/guide")
    assert_eq(response.code, 301)
    assert_eq(
      response.headers.get(@http.CaseInsensitiveString("ETag")),
      None,
    )
    assert_eq(
      response.headers.get(@http.CaseInsensitiveString("Last-Modified")),
      None,
    )
    assert_eq(
      response.headers.get(@http.CaseInsensitiveString("Content-Disposition")),
      None,
    )
    ignore(client.read_all())
  })
  @fs.rmdir(dir, recursive=true)
}

///|
async test "precondition failures drop stale representation metadata" {
  let app = @feather.App::new()
    .etag()
    .get("/item", fn(ctx) {
      ctx.set_header("ETag", "\"current\"")
      ctx.set_header("Content-Disposition", "attachment; filename=\"old.txt\"")
      ctx.text(200, "body")
    })
  with_server(app, client => {
    let response = client.get(
      "/item",
      extra_headers=Map([
        (@http.CaseInsensitiveString("If-Match"), "\"stale\""),
      ]),
    )
    assert_eq(response.code, 412)
    assert_eq(
      response.headers.get(@http.CaseInsensitiveString("ETag")),
      None,
    )
    assert_eq(
      response.headers.get(@http.CaseInsensitiveString("Content-Disposition")),
      None,
    )
    assert_eq(client.read_all().text(), "412 Precondition Failed")
  })
}

///|
test "explicit bodyless statuses drop representation metadata offline" {
  let app = @feather.App::new().get("/empty", fn(ctx) {
    ctx.set_header("ETag", "\"stale\"")
    ctx.set_header("Last-Modified", "Wed, 21 Oct 2015 07:28:00 GMT")
    ctx.set_header("Content-Disposition", "attachment; filename=\"old.txt\"")
    ctx.text(200, "ignored")
    ctx.status(204)
  })
  let response = app.respond({
    method: "GET",
    path: "/empty",
    headers: Map([]),
    body: "",
  })
  assert_eq(response.status, 204)
  assert_eq(response.headers.get("ETag"), None)
  assert_eq(response.headers.get("Last-Modified"), None)
  assert_eq(response.headers.get("Content-Disposition"), None)
}

///|
async test "explicit bodyless statuses drop representation metadata on the wire" {
  let app = @feather.App::new().get("/empty", fn(ctx) {
    ctx.set_header("ETag", "\"stale\"")
    ctx.set_header("Last-Modified", "Wed, 21 Oct 2015 07:28:00 GMT")
    ctx.set_header("Content-Disposition", "attachment; filename=\"old.txt\"")
    ctx.text(200, "ignored")
    ctx.status(205)
  })
  with_server(app, client => {
    let response = client.get("/empty")
    assert_eq(response.code, 205)
    assert_eq(
      response.headers.get(@http.CaseInsensitiveString("ETag")),
      None,
    )
    assert_eq(
      response.headers.get(@http.CaseInsensitiveString("Last-Modified")),
      None,
    )
    assert_eq(
      response.headers.get(@http.CaseInsensitiveString("Content-Disposition")),
      None,
    )
    assert_eq(client.read_all().text(), "")
  })
}

///|
async test "streams with bodyless statuses drop representation metadata" {
  let app = @feather.App::new().stream("/empty", async fn(ctx, stream) {
    ctx.set_header("ETag", "\"stale\"")
    ctx.set_header("Last-Modified", "Wed, 21 Oct 2015 07:28:00 GMT")
    ctx.set_header("Content-Disposition", "attachment; filename=\"old.txt\"")
    stream.set_status(204)
    stream.write("ignored")
  })
  with_stream_server(app, client => {
    let response = client.get("/empty")
    assert_eq(response.code, 204)
    assert_eq(
      response.headers.get(@http.CaseInsensitiveString("ETag")),
      None,
    )
    assert_eq(
      response.headers.get(@http.CaseInsensitiveString("Last-Modified")),
      None,
    )
    assert_eq(
      response.headers.get(@http.CaseInsensitiveString("Content-Disposition")),
      None,
    )
    assert_eq(client.read_all().text(), "")
  })
}

///|
test "304 responses keep validators and drop stale body metadata offline" {
  let app = @feather.App::new().get("/cached", fn(ctx) {
    ctx.set_header("ETag", "\"current\"")
    ctx.set_header("Last-Modified", "Wed, 21 Oct 2015 07:28:00 GMT")
    ctx.set_header("Content-Disposition", "attachment; filename=\"old.txt\"")
    ctx.text(304, "ignored")
  })
  let response = app.respond({
    method: "GET",
    path: "/cached",
    headers: Map([]),
    body: "",
  })
  assert_eq(response.status, 304)
  assert_eq(response.headers.get("ETag"), Some("\"current\""))
  assert_eq(
    response.headers.get("Last-Modified"),
    Some("Wed, 21 Oct 2015 07:28:00 GMT"),
  )
  assert_eq(response.headers.get("Content-Type"), None)
  assert_eq(response.headers.get("Content-Disposition"), None)
}

///|
async test "304 responses keep validators and drop stale body metadata on the wire" {
  let app = @feather.App::new().get("/cached", fn(ctx) {
    ctx.set_header("ETag", "\"current\"")
    ctx.set_header("Last-Modified", "Wed, 21 Oct 2015 07:28:00 GMT")
    ctx.set_header("Content-Disposition", "attachment; filename=\"old.txt\"")
    ctx.text(304, "ignored")
  })
  with_server(app, client => {
    let response = client.get("/cached")
    assert_eq(response.code, 304)
    assert_eq(
      response.headers.get(@http.CaseInsensitiveString("ETag")),
      Some("\"current\""),
    )
    assert_eq(
      response.headers.get(@http.CaseInsensitiveString("Last-Modified")),
      Some("Wed, 21 Oct 2015 07:28:00 GMT"),
    )
    assert_eq(
      response.headers.get(@http.CaseInsensitiveString("Content-Type")),
      None,
    )
    assert_eq(
      response.headers.get(@http.CaseInsensitiveString("Content-Disposition")),
      None,
    )
    assert_eq(client.read_all().text(), "")
  })
}

///|
async test "static 304 responses drop stale content disposition" {
  let dir = @fs.tmpdir(prefix="feather-static-304-disposition")
  @fs.write_file(dir + "/asset.txt", "asset")
  let app = @feather.App::new().static_files_with("/assets", dir, [
    fn(next) {
      fn(ctx) {
        ctx.set_header("Content-Disposition", "attachment; filename=\"old.txt\"")
        next(ctx)
      }
    },
  ])
  with_server(app, client => {
    let first = client.get("/assets/asset.txt")
    let etag = first.headers.get(@http.CaseInsensitiveString("ETag")).unwrap()
    ignore(client.read_all())
    let second = client.get(
      "/assets/asset.txt",
      extra_headers=Map([(@http.CaseInsensitiveString("If-None-Match"), etag)]),
    )
    assert_eq(second.code, 304)
    assert_eq(
      second.headers.get(@http.CaseInsensitiveString("Content-Disposition")),
      None,
    )
    ignore(client.read_all())
  })
  @fs.rmdir(dir, recursive=true)
}

///|
async test "queued file 304 responses drop stale content disposition" {
  let dir = @fs.tmpdir(prefix="feather-file-304-disposition")
  @fs.write_file(dir + "/asset.txt", "asset")
  let app = @feather.App::new().get("/download", fn(ctx) {
    ctx.file(200, dir + "/asset.txt")
    ctx.set_header("Content-Disposition", "attachment; filename=\"old.txt\"")
  })
  with_server(app, client => {
    let first = client.get("/download")
    let etag = first.headers.get(@http.CaseInsensitiveString("ETag")).unwrap()
    ignore(client.read_all())
    let second = client.get(
      "/download",
      extra_headers=Map([(@http.CaseInsensitiveString("If-None-Match"), etag)]),
    )
    assert_eq(second.code, 304)
    assert_eq(
      second.headers.get(@http.CaseInsensitiveString("Content-Disposition")),
      None,
    )
    ignore(client.read_all())
  })
  @fs.rmdir(dir, recursive=true)
}

///|
async test "static 416 responses drop stale content disposition" {
  let dir = @fs.tmpdir(prefix="feather-static-416-disposition")
  @fs.write_file(dir + "/asset.txt", "asset")
  let app = @feather.App::new().static_files_with("/assets", dir, [
    fn(next) {
      fn(ctx) {
        ctx.set_header("Content-Disposition", "attachment; filename=\"old.txt\"")
        next(ctx)
      }
    },
  ])
  with_server(app, client => {
    let response = client.get(
      "/assets/asset.txt",
      extra_headers=Map([(@http.CaseInsensitiveString("Range"), "bytes=99-")]),
    )
    assert_eq(response.code, 416)
    assert_eq(
      response.headers.get(@http.CaseInsensitiveString("Content-Disposition")),
      None,
    )
    ignore(client.read_all())
  })
  @fs.rmdir(dir, recursive=true)
}

///|
async test "queued file 416 responses drop stale content disposition" {
  let dir = @fs.tmpdir(prefix="feather-file-416-disposition")
  @fs.write_file(dir + "/asset.txt", "asset")
  let app = @feather.App::new().get("/download", fn(ctx) {
    ctx.file(200, dir + "/asset.txt")
    ctx.set_header("Content-Disposition", "attachment; filename=\"old.txt\"")
  })
  with_server(app, client => {
    let response = client.get(
      "/download",
      extra_headers=Map([(@http.CaseInsensitiveString("Range"), "bytes=99-")]),
    )
    assert_eq(response.code, 416)
    assert_eq(
      response.headers.get(@http.CaseInsensitiveString("Content-Disposition")),
      None,
    )
    ignore(client.read_all())
  })
  @fs.rmdir(dir, recursive=true)
}
