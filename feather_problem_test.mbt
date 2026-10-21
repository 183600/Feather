///|
fn problem_ctx(headers : Map[String, String]) -> @feather.Context {
  @feather.Context::new({ method: "GET", path: "/", headers, body: "", })
}

///|
fn response_header(response : @feather.Response, name : String) -> String {
  for key, value in response.headers {
    if key.view().equal_ignore_ascii_case(name.view()) {
      return value
    }
  }
  ""
}

///|
fn json_field(body : String, field : String) -> Json? {
  let parsed : Json = @json.parse(body) catch { _ => Json::null() }
  match parsed {
    Json::Object(map) => map.get(field)
    _ => None
  }
}

///|
fn problem_request(
  path : String,
  verb : String,
  problem : Bool,
) -> @feather.Request {
  let headers : Map[String, String] = if problem {
    Map([("Accept", "application/problem+json")])
  } else {
    Map([])
  }
  { method: verb, path, headers, body: "", }
}

///|
test "wants_problem_details needs an explicit problem preference" {
  assert_true(
    problem_ctx(Map([("Accept", "application/problem+json")])).wants_problem_details(),
  )
  assert_true(
    problem_ctx(Map([("Accept", "text/html, application/problem+json")])).wants_problem_details(),
  )
  assert_true(
    problem_ctx(
      Map([("Accept", "application/problem+json, application/json;q=0.9")]),
    ).wants_problem_details(),
  )
  assert_true(
    problem_ctx(Map([("Accept", "application/problem+json;q=0.8, */*;q=0.5")])).wants_problem_details(),
  )
}

///|
test "wants_problem_details stays false for generic or lesser preferences" {
  assert_false(problem_ctx(Map([])).wants_problem_details())
  assert_false(problem_ctx(Map([("Accept", "")])).wants_problem_details())
  assert_false(problem_ctx(Map([("Accept", "*/*")])).wants_problem_details())
  assert_false(
    problem_ctx(Map([("Accept", "application/json")])).wants_problem_details(),
  )
  assert_false(
    problem_ctx(Map([("Accept", "text/html")])).wants_problem_details(),
  )
  assert_false(
    problem_ctx(Map([("Accept", "application/problem+json;q=0")])).wants_problem_details(),
  )
  assert_false(
    problem_ctx(Map([("Accept", "text/html, application/problem+json;q=0.5")])).wants_problem_details(),
  )
  assert_false(
    problem_ctx(
      Map([("Accept", "application/json, application/problem+json;q=0.9")]),
    ).wants_problem_details(),
  )
  assert_false(
    problem_ctx(Map([("Accept", "application/problem+json;q=0.8, */*")])).wants_problem_details(),
  )
  assert_false(
    problem_ctx(Map([("Accept", "application/problem+json;q=0.8, text/plain")])).wants_problem_details(),
  )
  assert_false(
    problem_ctx(
      Map([("Accept", " application/problem+json ; q=0.2 , application/xml ")]),
    ).wants_problem_details(),
  )
}

///|
test "missing routes answer problem details for problem clients" {
  let app = @feather.App::new().get("/known", fn(ctx) { ctx.text(200, "ok") })
  let response = app.respond(problem_request("/missing", "GET", true))
  assert_eq(response.status, 404)
  assert_eq(
    response_header(response, "Content-Type"),
    "application/problem+json; charset=utf-8",
  )
  assert_eq(
    json_field(response.body, "type"),
    Some(Json::string("about:blank")),
  )
  assert_eq(json_field(response.body, "title"), Some(Json::string("Not Found")))
  assert_eq(json_field(response.body, "status"), Some(Json::number(404.0)))
  assert_eq(json_field(response.body, "detail"), None)
}

///|
test "missing routes keep the plain body without a problem preference" {
  let app = @feather.App::new().get("/known", fn(ctx) { ctx.text(200, "ok") })
  let plain = app.respond(problem_request("/missing", "GET", false))
  assert_eq(plain.status, 404)
  assert_eq(response_header(plain, "Content-Type"), "text/plain; charset=utf-8")
  assert_eq(plain.body, "404 Not Found")
  let any_client = app.respond({
    method: "GET",
    path: "/missing",
    headers: Map([("Accept", "*/*")]),
    body: "",
  })
  assert_eq(any_client.status, 404)
  assert_eq(
    response_header(any_client, "Content-Type"),
    "text/plain; charset=utf-8",
  )
  assert_eq(any_client.body, "404 Not Found")
  let json_client = app.respond({
    method: "GET",
    path: "/missing",
    headers: Map([("Accept", "application/json")]),
    body: "",
  })
  assert_eq(json_client.status, 404)
  assert_eq(
    response_header(json_client, "Content-Type"),
    "text/plain; charset=utf-8",
  )
  assert_eq(json_client.body, "404 Not Found")
}

///|
test "method not allowed carries Allow and negotiated problem details" {
  let app = @feather.App::new().get("/only-get", fn(ctx) { ctx.text(200, "ok") })
  let plain = app.respond(problem_request("/only-get", "POST", false))
  assert_eq(plain.status, 405)
  assert_eq(response_header(plain, "Allow"), "GET, HEAD")
  assert_eq(plain.body, "405 Method Not Allowed")
  let problem = app.respond(problem_request("/only-get", "POST", true))
  assert_eq(problem.status, 405)
  assert_eq(response_header(problem, "Allow"), "GET, HEAD")
  assert_eq(
    response_header(problem, "Content-Type"),
    "application/problem+json; charset=utf-8",
  )
  assert_eq(
    json_field(problem.body, "title"),
    Some(Json::string("Method Not Allowed")),
  )
  assert_eq(json_field(problem.body, "status"), Some(Json::number(405.0)))
}

///|
test "fail renders problem details when the client prefers them" {
  let app = @feather.App::new().get("/bad", fn(ctx) raise {
    ctx.fail(422, "invalid input")
  })
  let response = app.respond(problem_request("/bad", "GET", true))
  assert_eq(response.status, 422)
  assert_eq(
    response_header(response, "Content-Type"),
    "application/problem+json; charset=utf-8",
  )
  assert_eq(
    json_field(response.body, "title"),
    Some(Json::string("Unprocessable Entity")),
  )
  assert_eq(
    json_field(response.body, "detail"),
    Some(Json::string("invalid input")),
  )
  assert_eq(json_field(response.body, "status"), Some(Json::number(422.0)))
}

///|
test "fail keeps the plain json body for other clients" {
  let app = @feather.App::new().get("/bad", fn(ctx) raise {
    ctx.fail(422, "invalid input")
  })
  let response = app.respond(problem_request("/bad", "GET", false))
  assert_eq(response.status, 422)
  assert_eq(
    response_header(response, "Content-Type"),
    "application/json; charset=utf-8",
  )
  assert_eq(
    json_field(response.body, "error"),
    Some(Json::string("invalid input")),
  )
  assert_eq(json_field(response.body, "detail"), None)
}

///|
test "fail_with extends the problem document with payload members" {
  let app = @feather.App::new().get("/dupe", fn(ctx) raise {
    ctx.fail_with(
      409,
      "resource exists",
      Json::object(Map([("code", Json::string("duplicate"))])),
    )
  })
  let response = app.respond(problem_request("/dupe", "GET", true))
  assert_eq(response.status, 409)
  assert_eq(
    response_header(response, "Content-Type"),
    "application/problem+json; charset=utf-8",
  )
  assert_eq(json_field(response.body, "title"), Some(Json::string("Conflict")))
  assert_eq(
    json_field(response.body, "detail"),
    Some(Json::string("resource exists")),
  )
  assert_eq(json_field(response.body, "code"), Some(Json::string("duplicate")))
  let plain = app.respond(problem_request("/dupe", "GET", false))
  assert_eq(
    json_field(plain.body, "error"),
    Some(Json::string("resource exists")),
  )
  assert_eq(json_field(plain.body, "code"), Some(Json::string("duplicate")))
}

///|
test "problem writes problem details directly from a handler" {
  let app = @feather.App::new().get("/gone", fn(ctx) {
    ctx.problem(
      410,
      "the account was deleted",
      title="Deleted",
      type_name="https://feather.dev/errors/deleted",
      instance="/accounts/9",
    )
  })
  let response = app.respond(problem_request("/gone", "GET", false))
  assert_eq(response.status, 410)
  assert_eq(
    response_header(response, "Content-Type"),
    "application/problem+json; charset=utf-8",
  )
  assert_eq(
    json_field(response.body, "type"),
    Some(Json::string("https://feather.dev/errors/deleted")),
  )
  assert_eq(json_field(response.body, "title"), Some(Json::string("Deleted")))
  assert_eq(
    json_field(response.body, "detail"),
    Some(Json::string("the account was deleted")),
  )
  assert_eq(
    json_field(response.body, "instance"),
    Some(Json::string("/accounts/9")),
  )
  assert_eq(json_field(response.body, "status"), Some(Json::number(410.0)))
}

///|
test "fail_problem renders problem details for every client" {
  let app = @feather.App::new().get("/down", fn(ctx) raise {
    ctx.fail_problem(503, "database offline", title="Maintenance")
  })
  let response = app.respond(problem_request("/down", "GET", false))
  assert_eq(response.status, 503)
  assert_eq(
    response_header(response, "Content-Type"),
    "application/problem+json; charset=utf-8",
  )
  assert_eq(
    json_field(response.body, "title"),
    Some(Json::string("Maintenance")),
  )
  assert_eq(
    json_field(response.body, "detail"),
    Some(Json::string("database offline")),
  )
  assert_eq(
    json_field(response.body, "type"),
    Some(Json::string("about:blank")),
  )
}

///|
test "recover middleware turns a raised problem into its response" {
  let recover = @feather.middleware_recover()
  let chain : @feather.Handler = recover(fn(ctx) raise {
    ctx.fail_problem(418, "short and stout")
  })
  let ctx = problem_ctx(Map([]))
  chain(ctx) catch {
    _ => ()
  }
  assert_eq(ctx.response.status, 418)
  assert_eq(
    response_header(ctx.response, "Content-Type"),
    "application/problem+json; charset=utf-8",
  )
  assert_eq(
    json_field(ctx.response.body, "detail"),
    Some(Json::string("short and stout")),
  )
}

///|
test "error handler middleware turns a raised problem into its response" {
  let handler = @feather.middleware_error_handler()
  let chain : @feather.Handler = handler(fn(ctx) raise {
    ctx.fail_problem(502, "upstream misbehaved")
  })
  let ctx = problem_ctx(Map([]))
  chain(ctx) catch {
    _ => ()
  }
  assert_eq(ctx.response.status, 502)
  assert_eq(json_field(ctx.response.body, "status"), Some(Json::number(502.0)))
  assert_eq(
    json_field(ctx.response.body, "detail"),
    Some(Json::string("upstream misbehaved")),
  )
}

///|
test "logger middleware records and re-raises problem errors" {
  let logs : Array[String] = []
  let logger = @feather.middleware_logger(log=fn(line) { logs.push(line) })
  let chain : @feather.Handler = logger(fn(ctx) raise {
    ctx.fail_problem(507, "insufficient storage")
  })
  let ctx = problem_ctx(Map([]))
  let mut propagated = false
  chain(ctx) catch {
    _ => propagated = true
  }
  assert_true(propagated)
  assert_eq(logs.length(), 1)
  assert_true(logs[0].contains("[507]"))
  assert_true(logs[0].contains("GET /"))
}

///|
test "problem errors survive an outer logger and inner recover" {
  let logs : Array[String] = []
  let logger = @feather.middleware_logger(log=fn(line) { logs.push(line) })
  let recover = @feather.middleware_recover()
  let chain : @feather.Handler = logger(
    recover(fn(ctx) raise { ctx.fail_problem(429, "slow down") }),
  )
  let ctx = problem_ctx(Map([]))
  chain(ctx) catch {
    _ => ()
  }
  assert_eq(ctx.response.status, 429)
  assert_eq(logs.length(), 1)
  assert_true(logs[0].contains("[429]"))
}

///|
test "internal errors stay silent in problem rendering" {
  let recover = @feather.middleware_recover()
  let chain : @feather.Handler = recover(fn(_ctx) raise {
    raise Failure("secret key is abc123")
  })
  let ctx = problem_ctx(Map([("Accept", "application/problem+json")]))
  chain(ctx) catch {
    _ => ()
  }
  assert_eq(ctx.response.status, 500)
  assert_eq(
    response_header(ctx.response, "Content-Type"),
    "application/problem+json; charset=utf-8",
  )
  assert_eq(
    json_field(ctx.response.body, "title"),
    Some(Json::string("Internal Server Error")),
  )
  assert_false(ctx.response.body.contains("abc123"))
}

///|
test "problem details never leak into state-free plain rendering" {
  let recover = @feather.middleware_recover()
  let chain : @feather.Handler = recover(fn(_ctx) raise {
    raise Failure("secret key is abc123")
  })
  let ctx = problem_ctx(Map([]))
  chain(ctx) catch {
    _ => ()
  }
  assert_eq(ctx.response.status, 500)
  assert_eq(ctx.response.body, "Internal Server Error")
  assert_false(ctx.response.body.contains("abc123"))
}

///|
async test "server answers problem details over the wire" {
  let app = @feather.App::new().get("/known", fn(ctx) { ctx.text(200, "ok") })
  with_server(app, client => {
    let response = client.get(
      "/missing",
      extra_headers=Map([
        (@http.CaseInsensitiveString("Accept"), "application/problem+json"),
      ]),
    )
    assert_eq(response.code, 404)
    assert_eq(
      response.headers.get(@http.CaseInsensitiveString("Content-Type")),
      Some("application/problem+json; charset=utf-8"),
    )
    let body = client.read_all().text()
    assert_eq(json_field(body, "status"), Some(Json::number(404.0)))
    assert_eq(json_field(body, "title"), Some(Json::string("Not Found")))
    let plain = client.get("/missing")
    assert_eq(plain.code, 404)
    assert_eq(client.read_all().text(), "404 Not Found")
  })
}

///|
async test "server renders raised problem details over the wire" {
  let app = @feather.App::new()
    .use(@feather.middleware_recover())
    .get("/down", fn(ctx) raise { ctx.fail_problem(503, "database offline") })
    .get("/known", fn(ctx) { ctx.text(200, "ok") })
  with_server(app, client => {
    let response = client.get("/down")
    assert_eq(response.code, 503)
    assert_eq(
      response.headers.get(@http.CaseInsensitiveString("Content-Type")),
      Some("application/problem+json; charset=utf-8"),
    )
    let body = client.read_all().text()
    assert_eq(
      json_field(body, "detail"),
      Some(Json::string("database offline")),
    )
    assert_eq(json_field(body, "status"), Some(Json::number(503.0)))
  })
}

///|
async test "static middleware failures answer with problem details" {
  let dir = @fs.tmpdir(prefix="feather-problem-static")
  @fs.write_file(dir + "/hello.txt", "static body")
  let app = @feather.App::new()
    .static_files("/static", dir)
    .use(fn(next) {
      fn(ctx) raise {
        if ctx.get_path().has_prefix("/static") {
          ctx.fail_problem(503, "static assets unavailable")
        } else {
          next(ctx)
        }
      }
    })
  with_server(app, client => {
    let response = client.get(
      "/static/hello.txt",
      extra_headers=Map([
        (@http.CaseInsensitiveString("Accept"), "application/problem+json"),
      ]),
    )
    assert_eq(response.code, 503)
    let body = client.read_all().text()
    assert_eq(
      json_field(body, "detail"),
      Some(Json::string("static assets unavailable")),
    )
    let plain = client.get("/static/hello.txt")
    assert_eq(plain.code, 503)
    assert_eq(
      plain.headers.get(@http.CaseInsensitiveString("Content-Type")),
      Some("application/problem+json; charset=utf-8"),
    )
    assert_eq(
      json_field(client.read_all().text(), "detail"),
      Some(Json::string("static assets unavailable")),
    )
  })
  @fs.rmdir(dir, recursive=true)
}
