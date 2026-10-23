///|
async test "bodyless redirects ignore a handler supplied content coding" {
  let app = @feather.App::new().get("/go", fn(ctx) {
    ctx.redirect(302, "/target")
    ctx.set_header("Content-Encoding", "gzip")
  })
  let request : @feather.Request = {
    method: "GET",
    path: "/go",
    headers: Map([("Accept-Encoding", "identity")]),
    body: "",
  }
  let sync = app.respond(request)
  assert_eq(sync.status, 302)
  assert_eq(sync.headers.get("Location"), Some("/target"))
  assert_eq(sync.headers.get("Content-Encoding"), None)
  let asynchronous = app.respond_async(request)
  assert_eq(asynchronous.status, 302)
  assert_eq(asynchronous.headers.get("Location"), Some("/target"))
  assert_eq(asynchronous.headers.get("Content-Encoding"), None)
}

///|
async test "a 304 keeps the content coding of the selected representation" {
  let app = @feather.App::new().get("/cached", fn(ctx) {
    ctx.not_modified()
    ctx.set_header("Content-Encoding", "gzip")
  })
  let request : @feather.Request = {
    method: "GET",
    path: "/cached",
    headers: Map([("Accept-Encoding", "identity")]),
    body: "",
  }
  let sync = app.respond(request)
  assert_eq(sync.status, 304)
  assert_eq(sync.headers.get("Content-Encoding"), Some("gzip"))
  let asynchronous = app.respond_async(request)
  assert_eq(asynchronous.status, 304)
  assert_eq(asynchronous.headers.get("Content-Encoding"), Some("gzip"))
}
