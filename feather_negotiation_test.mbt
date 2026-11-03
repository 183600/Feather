///|
fn accept_ctx(accept : String) -> @feather.Context {
  @feather.Context::new({
    method: "GET",
    path: "/",
    headers: if accept == "" {
      Map([])
    } else {
      Map([("Accept", accept)])
    },
    body: "",
  })
}

///|
test "accepts treats a missing accept header as accepting everything" {
  assert_true(accept_ctx("").accepts("application/json"))
  assert_true(accept_ctx("").accepts("text/html"))
}

///|
test "accepts matches exact media types case insensitively" {
  assert_true(accept_ctx("application/json").accepts("application/json"))
  assert_true(accept_ctx("Application/JSON").accepts("application/json"))
  assert_false(accept_ctx("application/json").accepts("text/html"))
}

///|
test "accepts understands wildcard media ranges" {
  assert_true(accept_ctx("*/*").accepts("application/json"))
  assert_true(accept_ctx("text/*").accepts("text/html"))
  assert_false(accept_ctx("text/*").accepts("application/json"))
  assert_true(accept_ctx("text/html, */*;q=0.1").accepts("application/xml"))
}

///|
test "accepts honors quality values" {
  assert_false(accept_ctx("application/json;q=0").accepts("application/json"))
  assert_true(
    accept_ctx("application/json;q=0.001").accepts("application/json"),
  )
  assert_false(accept_ctx("*/*;q=0").accepts("text/html"))
}

///|
test "accepts prefers the most specific matching range" {
  let header = "application/json;q=0, */*;q=0.9"
  assert_false(accept_ctx(header).accepts("application/json"))
  assert_true(accept_ctx(header).accepts("text/html"))
  let wildcard_off = "text/html, */*;q=0"
  assert_true(accept_ctx(wildcard_off).accepts("text/html"))
  assert_false(accept_ctx(wildcard_off).accepts("application/json"))
}

///|
test "accepts ignores media type parameters on the offer" {
  assert_true(accept_ctx("text/html").accepts("text/html; charset=utf-8"))
  assert_true(accept_ctx("application/json").accepts("application/json"))
}

///|
test "accepts tolerates malformed headers" {
  assert_true(accept_ctx("garbage").accepts("text/html"))
  assert_true(accept_ctx(",,,").accepts("text/html"))
}

///|
test "accepts understands wildcards in the offered media type" {
  assert_true(accept_ctx("text/html").accepts("*/*"))
  assert_true(accept_ctx("text/html").accepts("text/*"))
  assert_true(accept_ctx("Text/HTML").accepts("text/*"))
  assert_false(accept_ctx("application/json").accepts("text/*"))
  assert_true(accept_ctx("application/json").accepts("application/*"))
  assert_false(accept_ctx("text/html;q=0").accepts("text/*"))
  assert_true(accept_ctx("text/html;q=0, text/*;q=0.5").accepts("text/*"))
  assert_false(accept_ctx("*/*;q=0").accepts("*/*"))
  assert_true(accept_ctx("*/*;q=0.2").accepts("application/*"))
  assert_true(accept_ctx("application/json, text/html").accepts("*/*"))
  assert_true(accept_ctx("").accepts("text/*"))
}

///|
test "preferred_type treats wildcard offers as patterns" {
  let ctx = accept_ctx("application/json;q=0.8, text/html;q=0.9")
  assert_eq(ctx.preferred_type(["application/*", "text/*"]), Some("text/*"))
  assert_eq(ctx.preferred_type(["image/*", "audio/*"]), None)
  let json_ctx = accept_ctx("application/json")
  assert_eq(json_ctx.preferred_type(["application/*"]), Some("application/*"))
}

///|
test "preferred_type picks the best matching offer" {
  let ctx = accept_ctx("text/html;q=0.9, application/json;q=0.8")
  assert_eq(
    ctx.preferred_type(["application/json", "text/html"]),
    Some("text/html"),
  )
  assert_eq(ctx.preferred_type(["text/plain", "application/xml"]), None)
}

///|
test "preferred_type keeps server order on quality ties" {
  let ctx = accept_ctx("*/*")
  assert_eq(
    ctx.preferred_type(["application/json", "text/html"]),
    Some("application/json"),
  )
  let specific = accept_ctx("text/html, application/json")
  assert_eq(
    specific.preferred_type(["application/json", "text/html"]),
    Some("application/json"),
  )
}

///|
test "preferred_type skips rejected offers" {
  let ctx = accept_ctx("application/json;q=0, text/*")
  assert_eq(
    ctx.preferred_type(["application/json", "text/html"]),
    Some("text/html"),
  )
  assert_eq(ctx.preferred_type(["application/json", "image/png"]), None)
  assert_eq(accept_ctx("").preferred_type([]), None)
}

///|
test "format runs the handler for the most preferred media type" {
  let ctx = accept_ctx("text/html;q=0.9, application/json;q=0.8")
  ctx.format([
    ("application/json", fn(ctx) { ctx.text(200, "json") }),
    ("text/html", fn(ctx) { ctx.html(200, "html") }),
  ])
  assert_eq(ctx.response.status, 200)
  assert_eq(ctx.response.body, "html")
  assert_eq(ctx.response_header("Content-Type"), "text/html; charset=utf-8")
  assert_eq(ctx.response_header("Vary"), "Accept")
}

///|
test "format uses the first offer when the request states no preference" {
  let ctx = accept_ctx("")
  ctx.format([
    ("application/json", fn(ctx) { ctx.text(200, "json") }),
    ("text/html", fn(ctx) { ctx.text(200, "html") }),
  ])
  assert_eq(ctx.response.body, "json")
}

///|
test "format skips rejected offers and answers 406 when none remain" {
  let rejected = accept_ctx("application/json;q=0, text/html;q=0")
  rejected.format([
    ("application/json", fn(ctx) { ctx.text(200, "json") }),
    ("text/html", fn(ctx) { ctx.text(200, "html") }),
  ])
  assert_eq(rejected.response.status, 406)
  assert_true(rejected.response.body.contains("Not Acceptable"))
  assert_eq(rejected.response_header("Vary"), "Accept")

  let unsupported = accept_ctx("application/xml")
  unsupported.format([("application/json", fn(ctx) { ctx.text(200, "json") })])
  assert_eq(unsupported.response.status, 406)
}

///|
test "format runs the fallback handler when no offer is acceptable" {
  let ctx = accept_ctx("application/xml")
  ctx.format([("application/json", fn(ctx) { ctx.text(200, "json") })], fallback=fn(
    ctx,
  ) {
    ctx.text(200, "fallback")
  })
  assert_eq(ctx.response.status, 200)
  assert_eq(ctx.response.body, "fallback")
  assert_eq(ctx.response_header("Vary"), "Accept")
}

///|
test "format runs the fallback handler when no offer is acceptable" {
  let ctx = accept_ctx("application/xml")
  ctx.format([("application/json", fn(ctx) { ctx.text(200, "json") })], fallback=fn(
    ctx,
  ) {
    ctx.text(200, "fallback")
  })
  assert_eq(ctx.response.status, 200)
  assert_eq(ctx.response.body, "fallback")
  assert_eq(ctx.response_header("Vary"), "Accept")
}

///|
test "format fallback can return a problem details response" {
  let ctx = accept_ctx("application/xml")
  ctx.format(
    [("application/json", fn(ctx) { ctx.text(200, "json") })],
    fallback=fn(ctx) {
      ctx.problem(406, "No acceptable representation", type_name="about:blank")
    },
  )
  assert_eq(ctx.response.status, 406)
  assert_true(ctx.response.body.contains("No acceptable representation"))
  assert_eq(
    ctx.response_header("Content-Type"),
    "application/problem+json; charset=utf-8",
  )
  assert_eq(ctx.response_header("Vary"), "Accept")
}

///|
test "format fallback can set custom status and headers" {
  let ctx = accept_ctx("application/xml")
  ctx.format(
    [("application/json", fn(ctx) { ctx.text(200, "json") })],
    fallback=fn(ctx) {
      ctx.set_header("X-Custom", "fallback-value")
      ctx.text(400, "custom fallback")
    },
  )
  assert_eq(ctx.response.status, 400)
  assert_eq(ctx.response.body, "custom fallback")
  assert_eq(ctx.response_header("X-Custom"), "fallback-value")
  assert_eq(ctx.response_header("Vary"), "Accept")
}

///|
test "format fallback can set cookies" {
  let ctx = accept_ctx("application/xml")
  ctx.format(
    [("application/json", fn(ctx) { ctx.text(200, "json") })],
    fallback=fn(ctx) {
      ctx.set_cookie("fallback", "yes", path="/", http_only=true)
      ctx.text(200, "fallback with cookie")
    },
  )
  assert_eq(ctx.response.status, 200)
  assert_eq(ctx.response.body, "fallback with cookie")
  assert_eq(ctx.response_header("Vary"), "Accept")
  let cookie = ctx.response_header("Set-Cookie")
  assert_true(cookie != "")
  assert_true(cookie.contains("fallback=yes"))
  assert_true(cookie.contains("HttpOnly"))
}

///|
test "format handler cookies are included when handler runs" {
  let ctx = accept_ctx("text/html")
  ctx.format(
    [
      ("text/html", fn(ctx) {
        ctx.set_cookie("handler", "html", path="/")
        ctx.html(200, "<html></html>")
      }),
    ],
    fallback=fn(ctx) {
      ctx.set_cookie("fallback", "yes", path="/")
      ctx.text(200, "fallback")
    },
  )
  assert_eq(ctx.response.status, 200)
  assert_eq(ctx.response.body, "<html></html>")
  let cookie = ctx.response_header("Set-Cookie")
  assert_true(cookie != "")
  assert_true(cookie.contains("handler=html"))
  assert_false(cookie.contains("fallback=yes"))
}

///|
test "format fallback cookies are included when fallback runs" {
  let ctx = accept_ctx("application/xml")
  ctx.format(
    [
      ("text/html", fn(ctx) {
        ctx.set_cookie("handler", "html", path="/")
        ctx.html(200, "<html></html>")
      }),
    ],
    fallback=fn(ctx) {
      ctx.set_cookie("fallback", "yes", path="/")
      ctx.text(200, "fallback")
    },
  )
  assert_eq(ctx.response.status, 200)
  assert_eq(ctx.response.body, "fallback")
  let cookie = ctx.response_header("Set-Cookie")
  assert_true(cookie != "")
  assert_true(cookie.contains("fallback=yes"))
  assert_false(cookie.contains("handler=html"))
}

///|
test "format does not duplicate an Accept entry in Vary" {
  let ctx = accept_ctx("application/json")
  ctx.format([
    (
      "application/json",
      fn(ctx) {
        ctx.vary("Accept")
        ctx.text(200, "json")
      },
    ),
  ])
  assert_eq(ctx.response_header("Vary"), "Accept")
}

///|
fn encoding_ctx(accept_encoding : String) -> @feather.Context {
  @feather.Context::new({
    method: "GET",
    path: "/",
    headers: if accept_encoding == "" {
      Map([])
    } else {
      Map([("Accept-Encoding", accept_encoding)])
    },
    body: "",
  })
}

///|
test "accepts_encoding treats a missing header as accepting everything" {
  assert_true(encoding_ctx("").accepts_encoding("gzip"))
  assert_true(encoding_ctx("").accepts_encoding("br"))
  assert_true(encoding_ctx("gzip, identity").accepts_encoding("gzip"))
  assert_true(encoding_ctx("gzip, identity").accepts_encoding("identity"))
}

///|
test "an explicitly empty accept-encoding rejects every coding" {
  let ctx = @feather.Context::new({
    method: "GET",
    path: "/",
    headers: Map([("Accept-Encoding", "")]),
    body: "",
  })
  assert_false(ctx.accepts_encoding("gzip"))
  assert_false(ctx.accepts_encoding("br"))
  assert_true(ctx.accepts_encoding("identity"))
  assert_eq(
    ctx.preferred_encoding(["gzip", "br", "identity"]),
    Some("identity"),
  )
  assert_eq(ctx.preferred_encoding(["gzip"]), None)
}

///|
test "accepts_encoding rejects codings that are not listed" {
  assert_false(encoding_ctx("identity").accepts_encoding("gzip"))
  assert_false(encoding_ctx("gzip;q=0").accepts_encoding("gzip"))
  assert_true(encoding_ctx("gzip;q=0.5").accepts_encoding("gzip"))
  assert_true(encoding_ctx("*").accepts_encoding("br"))
  assert_false(encoding_ctx("*;q=0").accepts_encoding("br"))
  assert_true(encoding_ctx("*;q=0, br;q=0.5").accepts_encoding("br"))
  assert_true(encoding_ctx("GZIP").accepts_encoding("gzip"))
}

///|
test "accepts_encoding treats x-gzip as the gzip coding" {
  assert_true(encoding_ctx("x-gzip").accepts_encoding("gzip"))
  assert_true(encoding_ctx("gzip").accepts_encoding("x-gzip"))
  assert_false(encoding_ctx("x-gzip;q=0").accepts_encoding("gzip"))
  assert_eq(
    encoding_ctx("x-gzip;q=0.9").preferred_encoding(["gzip"]),
    Some("gzip"),
  )
}

///|
test "accepts_encoding treats identity as acceptable by default" {
  assert_true(encoding_ctx("gzip").accepts_encoding("identity"))
  assert_true(encoding_ctx("gzip, br").accepts_encoding("identity"))
  assert_true(encoding_ctx("").accepts_encoding("identity"))
  assert_false(encoding_ctx("gzip, identity;q=0").accepts_encoding("identity"))
  assert_false(encoding_ctx("*;q=0").accepts_encoding("identity"))
  assert_true(encoding_ctx("gzip, *;q=0.5").accepts_encoding("identity"))
  assert_false(
    encoding_ctx("identity;q=0, *;q=0.8").accepts_encoding("identity"),
  )
}

///|
test "preferred_encoding picks the best coding and honors server order" {
  let ctx = encoding_ctx("br;q=0.9, gzip;q=0.8")
  assert_eq(ctx.preferred_encoding(["gzip", "br"]), Some("br"))
  assert_eq(ctx.preferred_encoding(["deflate"]), None)
  let tied = encoding_ctx("gzip, br")
  assert_eq(tied.preferred_encoding(["gzip", "br"]), Some("gzip"))
  assert_eq(encoding_ctx("").preferred_encoding([]), None)
  assert_eq(
    encoding_ctx("gzip;q=0, *;q=0.5").preferred_encoding(["gzip", "deflate"]),
    Some("deflate"),
  )
}

///|
/// App-level content negotiation: `Context::format` runs through the full
/// request cycle and the `Accept` header picks the offered representation.
fn negotiate_app() -> @feather.App {
  @feather.App::new().get(
    "/item",
    fn(ctx) {
      ctx.format([
        ("application/json", fn(ctx) { ctx.json(200, { "kind": "json" }) }),
        ("text/html", fn(ctx) { ctx.html(200, "<p>html</p>") }),
      ])
    },
  )
}

test "app format serves json when the client accepts it best" {
  let app = negotiate_app()
  let response = app.respond({
    method: "GET",
    path: "/item",
    headers: Map([
      ("Accept", "text/html;q=0.5, application/json;q=0.9"),
    ]),
    body: "",
  })
  assert_eq(response.status, 200)
  assert_eq(response.headers.get("Content-Type"), Some("application/json; charset=utf-8"))
  assert_eq(response.headers.get("Vary"), Some("Accept"))
  assert_true(response.body.contains("\"kind\""))
}

test "app format serves html when the client accepts it best" {
  let app = negotiate_app()
  let response = app.respond({
    method: "GET",
    path: "/item",
    headers: Map([("Accept", "text/html")]),
    body: "",
  })
  assert_eq(response.status, 200)
  assert_eq(response.headers.get("Content-Type"), Some("text/html; charset=utf-8"))
  assert_eq(response.body, "<p>html</p>")
}

test "app format answers 406 when the client rejects every offer" {
  let app = negotiate_app()
  let response = app.respond({
    method: "GET",
    path: "/item",
    headers: Map([("Accept", "application/xml;q=0")]),
    body: "",
  })
  assert_eq(response.status, 406)
  assert_eq(response.headers.get("Vary"), Some("Accept"))
}

test "app format serves the first offer when no Accept header is present" {
  let app = negotiate_app()
  let response = app.respond({
    method: "GET",
    path: "/item",
    headers: Map([]),
    body: "",
  })
  assert_eq(response.status, 200)
  assert_eq(response.headers.get("Content-Type"), Some("application/json; charset=utf-8"))
}

///|
fn negotiate_fallback_app() -> @feather.App {
  @feather.App::new().get(
    "/item",
    fn(ctx) {
      ctx.format(
        [("application/json", fn(ctx) { ctx.json(200, { "kind": "json" }) })],
        fallback=fn(ctx) { ctx.text(200, "plain fallback") },
      )
    },
  )
}

test "app format runs the fallback when no offer is acceptable" {
  let app = negotiate_fallback_app()
  let response = app.respond({
    method: "GET",
    path: "/item",
    headers: Map([("Accept", "text/plain")]),
    body: "",
  })
  assert_eq(response.status, 200)
  assert_eq(response.body, "plain fallback")
  assert_eq(response.headers.get("Vary"), Some("Accept"))
}

test "app format wildcard accept picks the server preference" {
  let app = negotiate_app()
  let response = app.respond({
    method: "GET",
    path: "/item",
    headers: Map([("Accept", "*/*")]),
    body: "",
  })
  assert_eq(response.status, 200)
  // First offer wins on a wildcard accept, which is JSON here.
  assert_eq(response.headers.get("Content-Type"), Some("application/json; charset=utf-8"))
}
