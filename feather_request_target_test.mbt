///|
fn absolute_form_request(path : String) -> @feather.Request {
  {
    method: "GET",
    path,
    headers: Map([("Host", "example.com")]),
    body: "",
  }
}

///|
test "absolute-form request targets route to their path and query" {
  let app = @feather.App::new().get("/users/:id", fn(ctx) {
    ctx.text(200, ctx.get_path())
  })
  let response = app.respond(
    absolute_form_request("http://example.com/users/42?tab=profile"),
  )
  assert_eq(response.status, 200)
  assert_eq(response.body, "/users/42?tab=profile")
}

///|
test "absolute-form request targets expose params queries and full_url" {
  let app = @feather.App::new().get("/users/:id", fn(ctx) {
    ctx.json(200, {
      "id": ctx.param("id"),
      "tab": ctx.query("tab"),
      "url": ctx.full_url(),
    })
  })
  let response = app.respond(
    absolute_form_request("HTTPS://example.com/users/7?tab=posts"),
  )
  assert_eq(response.status, 200)
  let parsed = @json.parse(response.body) catch { _ => Json::null() }
  assert_eq(parsed, {
    "id": "7",
    "tab": "posts",
    "url": "http://example.com/users/7?tab=posts",
  })
}

///|
test "absolute URIs without a path become the root path" {
  let app = @feather.App::new().get("/", fn(ctx) {
    ctx.text(200, "root:" + ctx.query("q"))
  })
  let bare = app.respond(absolute_form_request("http://example.com"))
  assert_eq(bare.status, 200)
  assert_eq(bare.body, "root:")
  let with_query = app.respond(
    absolute_form_request("http://example.com?q=feather"),
  )
  assert_eq(with_query.status, 200)
  assert_eq(with_query.body, "root:feather")
}

///|
test "absolute-form normalization accepts ipv6 authorities" {
  let app = @feather.App::new().get("/health", fn(ctx) {
    ctx.text(200, "ok")
  })
  let response = app.respond(
    absolute_form_request("http://[::1]:8080/health"),
  )
  assert_eq(response.status, 200)
  assert_eq(response.body, "ok")
}

///|
test "values that only look like absolute URIs are left alone" {
  let app = @feather.App::new().get("/x", fn(ctx) { ctx.text(200, "x") })
  // A malformed scheme must not be stripped, otherwise routing could be
  // steered by a target that is not a valid absolute URI.
  let malformed = app.respond(absolute_form_request("1http://host/x"))
  assert_eq(malformed.status, 404)
  let no_authority = app.respond(absolute_form_request("http:///x"))
  assert_eq(no_authority.status, 404)
  // A scheme without the `//` authority delimiter is not absolute-form.
  let opaque = app.respond(absolute_form_request("mailto:user@example.com"))
  assert_eq(opaque.status, 404)
}

///|
test "OPTIONS asterisk-form describes the server methods" {
  let app = @feather.App::new()
    .get("/users", fn(ctx) { ctx.text(200, "users") })
    .post("/users", fn(ctx) { ctx.text(201, "created") })
  let response = app.respond({
    method: "OPTIONS",
    path: "*",
    headers: Map([]),
    body: "",
  })
  assert_eq(response.status, 204)
  assert_eq(response.body, "")
  let allow = response.headers.get("Allow").unwrap_or("")
  for method in ["GET", "HEAD", "POST", "OPTIONS"] {
    assert_true(allow.contains(method), msg=allow)
  }
  assert_eq(response.headers.get("Content-Type"), None)
}

///|
test "OPTIONS asterisk-form works without any registered routes" {
  let app = @feather.App::new()
  let response = app.respond({
    method: "OPTIONS",
    path: "*",
    headers: Map([]),
    body: "",
  })
  assert_eq(response.status, 204)
  let allow = response.headers.get("Allow").unwrap_or("")
  for method in [
    "CONNECT",
    "DELETE",
    "GET",
    "HEAD",
    "OPTIONS",
    "PATCH",
    "POST",
    "PUT",
    "TRACE",
  ] {
    assert_true(allow.contains(method), msg=allow)
  }
}

///|
test "other methods do not get a server-wide asterisk response" {
  let app = @feather.App::new()
  let response = app.respond({
    method: "GET",
    path: "*",
    headers: Map([]),
    body: "",
  })
  assert_eq(response.status, 404)
  assert_eq(response.headers.get("Allow"), None)
}

///|
async test "server answers OPTIONS asterisk-form" {
  let app = @feather.App::new().get("/hello", fn(ctx) { ctx.text(200, "hi") })
  with_raw_server(app, conn => {
    conn.write(
      @utf8.encode(
        "OPTIONS * HTTP/1.1\r\nHost: example.com\r\nConnection: close\r\n\r\n",
      ),
    )
    let head = @async.with_timeout(2000, () => read_http_head(conn)) catch {
      _ => ""
    }
    assert_true(head.has_prefix("HTTP/1.1 204"), msg=head)
    assert_true(head.to_lower().contains("allow: get, head, options"), msg=head)
  })
}

///|
async test "server routes an absolute-form request target" {
  let app = @feather.App::new().get("/hello", fn(ctx) {
    ctx.text(200, "hello " + ctx.query("name"))
  })
  with_raw_server(app, conn => {
    conn.write(
      @utf8.encode(
        "GET http://example.com/hello?name=feather HTTP/1.1\r\nHost: example.com\r\nConnection: close\r\n\r\n",
      ),
    )
    let head = @async.with_timeout(2000, () => read_http_head(conn)) catch {
      _ => ""
    }
    assert_true(head.has_prefix("HTTP/1.1 200"), msg=head)
  })
}

///|
async test "server serves a static file for an absolute-form request target" {
  let dir = @fs.tmpdir(prefix="feather-absolute-static")
  @fs.write_file(dir + "/asset.txt", "static-body")
  let app = @feather.App::new().static_files("/assets", dir)
  with_raw_server(app, conn => {
    conn.write(
      @utf8.encode(
        "GET http://example.com/assets/asset.txt HTTP/1.1\r\nHost: example.com\r\nConnection: close\r\n\r\n",
      ),
    )
    let head = @async.with_timeout(2000, () => read_http_head(conn)) catch {
      _ => ""
    }
    assert_true(head.has_prefix("HTTP/1.1 200"), msg=head)
  })
  @fs.rmdir(dir, recursive=true)
}
