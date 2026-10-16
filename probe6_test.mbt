///|
test "url_for percent-encodes wildcard path segments" {
  let router = @feather.create_router()
  router.add_named_route("file", "GET", "/files/*path", fn(ctx) {
    ctx.text(200, "f")
  })
  assert_eq(
    router.url_for("file", params={ "path": "a/b.txt" }),
    Some("/files/a/b.txt"),
  )
  assert_eq(
    router.url_for("file", params={ "path": "a b/c#d" }),
    Some("/files/a%20b/c%23d"),
  )
  assert_eq(
    router.url_for("file", params={ "path": "中/文" }),
    Some("/files/%E4%B8%AD/%E6%96%87"),
  )
  assert_eq(router.url_for("file", params={ "path": "" }), Some("/files/"))
}

///|
test "url_for wildcard encoding matches route matching round trip" {
  let router = @feather.create_router()
  router.add_named_route("file", "GET", "/files/*path", fn(ctx) {
    ctx.text(200, "f")
  })
  let with_space = router.url_for("file", params={ "path": "a b/c.txt" })
  assert_eq(with_space, Some("/files/a%20b/c.txt"))
  match with_space {
    Some(url) =>
      match router.route("GET", url) {
        RouteFound(route) => assert_eq(route.params.get("path"), Some("a%20b/c.txt"))
        _ => fail("expected generated url to match the wildcard route")
      }
    None => fail("expected a generated url")
  }
}

///|
async test "static mounts only serve GET and HEAD requests" {
  let dir = @fs.tmpdir(prefix="feather-static-methods")
  @fs.write_file(dir + "/data.txt", "static-body")
  let app = @feather.App::new()
    .static_files("/assets", dir)
    .post("/assets/data.txt", fn(ctx) { ctx.text(200, "post-body") })
  with_server(app, client => {
    let get_response = client.get("/assets/data.txt")
    assert_eq(get_response.code, 200)
    assert_eq(client.read_all().text(), "static-body")
    let post_response = client.post("/assets/data.txt", "")
    assert_eq(post_response.code, 200)
    assert_eq(client.read_all().text(), "post-body")
    client.request(@http.RequestMethod::Delete, "/assets/data.txt")
    let delete_response = client.end_request()
    assert_eq(delete_response.code, 405)
    match delete_response.headers.get(@http.CaseInsensitiveString("Allow")) {
      Some(allow) => assert_true(allow.contains("POST"))
      None => fail("missing Allow header")
    }
    ignore(client.read_all())
  })
  @fs.rmdir(dir, recursive=true)
}

///|
async test "static mounts still answer HEAD without a body" {
  let dir = @fs.tmpdir(prefix="feather-static-head")
  @fs.write_file(dir + "/data.txt", "static-body")
  let app = @feather.App::new().static_files("/assets", dir)
  with_server(app, client => {
    client.request(@http.RequestMethod::Head, "/assets/data.txt")
    let response = client.end_request()
    assert_eq(response.code, 200)
    assert_eq(client.read_all().text(), "")
  })
  @fs.rmdir(dir, recursive=true)
}
