///|
fn parse_int_simple(value : String) -> Int32? {
  let view = value.view()
  let length = view.length()
  if length == 0 {
    return None
  }
  let mut index = 0
  let mut negative = false
  if view.unsafe_get(0) == ('-' : UInt16) {
    negative = true
    index = 1
  }
  if index >= length {
    return None
  }
  let mut result = 0
  while index < length {
    let digit = view.unsafe_get(index).to_int() - 48
    if digit < 0 || digit > 9 {
      return None
    }
    result = result * 10 + digit
    index = index + 1
  }
  if negative { Some(-result) } else { Some(result) }
}

///|
test "middleware_response_time adds X-Response-Time header" {
  let app = @feather.App::new()
    .use(@feather.middleware_response_time())
    .get("/fast", fn(ctx) { ctx.text(200, "ok") })
  let response = app.respond({
    method: "GET",
    path: "/fast",
    headers: Map([]),
    body: "",
  })
  assert_eq(response.status, 200)
  match response.headers.get("X-Response-Time") {
    Some(value) => {
      let ms = match parse_int_simple(value) {
        Some(ms) => ms
        None => fail("expected integer milliseconds")
      }
      assert_true(ms >= 0, msg="elapsed should be non-negative")
    }
    None => fail("expected X-Response-Time header")
  }
}

///|
test "middleware_response_time works with custom header name" {
  let app = @feather.App::new()
    .use(@feather.middleware_response_time(header="X-Custom-Time"))
    .get("/test", fn(ctx) { ctx.text(200, "ok") })
  let response = app.respond({
    method: "GET",
    path: "/test",
    headers: Map([]),
    body: "",
  })
  assert_eq(response.status, 200)
  assert_true(response.headers.get("X-Custom-Time") is Some(_))
  assert_eq(response.headers.get("X-Response-Time"), None)
}

///|
test "middleware_response_time works with precision" {
  let app = @feather.App::new()
    .use(@feather.middleware_response_time(precision=3))
    .get("/test", fn(ctx) { ctx.text(200, "ok") })
  let response = app.respond({
    method: "GET",
    path: "/test",
    headers: Map([]),
    body: "",
  })
  assert_eq(response.status, 200)
  match response.headers.get("X-Response-Time") {
    Some(value) => {
      assert_true(value.contains("."), msg="expected decimal with precision=3")
      let parts : Array[String] = []
      for part in value.split(".") {
        parts.push(part.to_owned())
      }
      assert_eq(parts.length(), 2)
      assert_eq(parts[1].length(), 3)
    }
    None => fail("expected X-Response-Time header")
  }
}

///|
test "middleware_response_time adds header on error responses" {
  let app = @feather.App::new()
    .use(@feather.middleware_recover())
    .use(@feather.middleware_response_time())
    .get("/error", fn(ctx) raise { ctx.fail(400, "bad") })
  let response = app.respond({
    method: "GET",
    path: "/error",
    headers: Map([]),
    body: "",
  })
  assert_eq(response.status, 400)
  assert_true(response.headers.get("X-Response-Time") is Some(_))
}

///|
test "middleware_response_time adds header on 404 responses" {
  let app = @feather.App::new()
    .use(@feather.middleware_response_time())
    .get("/exists", fn(ctx) { ctx.text(200, "ok") })
  let response = app.respond({
    method: "GET",
    path: "/missing",
    headers: Map([]),
    body: "",
  })
  assert_eq(response.status, 404)
  assert_true(response.headers.get("X-Response-Time") is Some(_))
}

///|
test "middleware_response_time works with middleware_logger" {
  let lines : Array[String] = []
  let app = @feather.App::new()
    .use(@feather.middleware_logger(log=line => lines.push(line), with_duration=true))
    .use(@feather.middleware_response_time())
    .get("/test", fn(ctx) { ctx.text(200, "ok") })
  let response = app.respond({
    method: "GET",
    path: "/test",
    headers: Map([]),
    body: "",
  })
  assert_eq(response.status, 200)
  assert_true(response.headers.get("X-Response-Time") is Some(_))
  assert_eq(lines.length(), 1)
  assert_true(lines[0].contains("200"))
}

///|
async test "middleware_response_time works on server" {
  let app = @feather.App::new()
    .use(@feather.middleware_response_time())
    .get("/fast", fn(ctx) { ctx.text(200, "ok") })
  with_server(app, client => {
    let response = client.get("/fast")
    assert_eq(response.code, 200)
    match response.headers.get(@http.CaseInsensitiveString("X-Response-Time")) {
      Some(value) => {
        let ms = match parse_int_simple(value) {
          Some(ms) => ms
          None => fail("expected integer milliseconds")
        }
        assert_true(ms >= 0)
      }
      None => fail("expected X-Response-Time header")
    }
  })
}

///|
test "middleware_response_time header value is integer by default" {
  let app = @feather.App::new()
    .use(@feather.middleware_response_time())
    .get("/test", fn(ctx) { ctx.text(200, "ok") })
  let response = app.respond({
    method: "GET",
    path: "/test",
    headers: Map([]),
    body: "",
  })
  match response.headers.get("X-Response-Time") {
    Some(value) => {
      assert_false(value.contains("."), msg="default precision should be 0")
      match parse_int_simple(value) {
        Some(_) => ()
        None => fail("expected integer value")
      }
    }
    None => fail("expected header")
  }
}

///|
test "middleware_response_time precision zero gives integer" {
  let app = @feather.App::new()
    .use(@feather.middleware_response_time(precision=0))
    .get("/test", fn(ctx) { ctx.text(200, "ok") })
  let response = app.respond({
    method: "GET",
    path: "/test",
    headers: Map([]),
    body: "",
  })
  match response.headers.get("X-Response-Time") {
    Some(value) => assert_false(value.contains("."))
    None => fail("expected header")
  }
}

///|
test "middleware_response_time precision negative clamps to zero" {
  let app = @feather.App::new()
    .use(@feather.middleware_response_time(precision=-1))
    .get("/test", fn(ctx) { ctx.text(200, "ok") })
  let response = app.respond({
    method: "GET",
    path: "/test",
    headers: Map([]),
    body: "",
  })
  match response.headers.get("X-Response-Time") {
    Some(value) => assert_false(value.contains("."))
    None => fail("expected header")
  }
}

///|
async test "middleware_response_time adds header for static files on server" {
  let dir = @fs.tmpdir(prefix="feather-response-time-static-server")
  @fs.write_file(dir + "/test.txt", "hello")
  let app = @feather.App::new()
    .use(@feather.middleware_response_time())
    .static_files("/assets", dir)
  with_server(app, client => {
    let response = client.get("/assets/test.txt")
    assert_eq(response.code, 200)
    match response.headers.get(@http.CaseInsensitiveString("X-Response-Time")) {
      Some(value) => {
        let ms = match parse_int_simple(value) {
          Some(ms) => ms
          None => fail("expected integer milliseconds")
        }
        assert_true(ms >= 0)
      }
      None => fail("expected X-Response-Time header")
    }
  })
  @fs.rmdir(dir, recursive=true)
}

///|
test "middleware_response_time works with method not allowed" {
  let app = @feather.App::new()
    .use(@feather.middleware_response_time())
    .get("/items", fn(ctx) { ctx.text(200, "ok") })
  let response = app.respond({
    method: "POST",
    path: "/items",
    headers: Map([]),
    body: "",
  })
  assert_eq(response.status, 405)
  assert_true(response.headers.get("X-Response-Time") is Some(_))
}

///|
test "middleware_response_time works with OPTIONS *" {
  let app = @feather.App::new()
    .use(@feather.middleware_response_time())
  let response = app.respond({
    method: "OPTIONS",
    path: "*",
    headers: Map([]),
    body: "",
  })
  assert_eq(response.status, 204)
  assert_true(response.headers.get("X-Response-Time") is Some(_))
}

///|
test "middleware_response_time works with fallback handler" {
  let app = @feather.App::new()
    .use(@feather.middleware_response_time())
    .get("/exists", fn(ctx) { ctx.text(200, "ok") })
    .fallback(fn(ctx) { ctx.text(404, "fallback") })
  let response = app.respond({
    method: "GET",
    path: "/missing",
    headers: Map([]),
    body: "",
  })
  assert_eq(response.status, 404)
  assert_eq(response.body, "fallback")
  assert_true(response.headers.get("X-Response-Time") is Some(_))
}