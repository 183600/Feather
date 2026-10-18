///|
fn probe_precondition_app() -> App {
  App::new()
  .etag()
  .get("/r", fn(ctx) {
    ctx.response.headers.set("ETag", "\"v1\"")
    ctx.response.headers.set("Last-Modified", "Mon, 01 Jan 2024 00:00:00 GMT")
    ctx.text(200, "hello")
  })
  .post("/r", fn(ctx) {
    ctx.response.headers.set("ETag", "\"v1\"")
    ctx.response.headers.set("Last-Modified", "Mon, 01 Jan 2024 00:00:00 GMT")
    ctx.text(200, "hello")
  })
}

///|
fn probe_respond(
  app : App,
  meth : String,
  headers : Map[String, String],
) -> Response {
  app.respond({ method: meth, path: "/r", headers, body: "" })
}

///|
test "probe if-match semantics" {
  let app = probe_precondition_app()
  let ok = probe_respond(app, "GET", Map([("If-Match", "\"v1\"")]))
  assert_eq(ok.status, 200)
  assert_eq(ok.body, "hello")
  let star = probe_respond(app, "GET", Map([("If-Match", "*")]))
  assert_eq(star.status, 200)
  let fail = probe_respond(app, "GET", Map([("If-Match", "\"other\"")]))
  assert_eq(fail.status, 412)
  assert_eq(fail.body, "412 Precondition Failed")
  let fail_star_list = probe_respond(
    app,
    "GET",
    Map([("If-Match", "\"other\", *")]),
  )
  assert_eq(fail_star_list.status, 200)
  let weak = probe_respond(app, "GET", Map([("If-Match", "W/\"v1\"")]))
  assert_eq(weak.status, 412)
}

///|
test "probe if-unmodified-since semantics" {
  let app = probe_precondition_app()
  let old = probe_respond(
    app,
    "GET",
    Map([("If-Unmodified-Since", "Sun, 01 Jan 2023 00:00:00 GMT")]),
  )
  assert_eq(old.status, 412)
  let same = probe_respond(
    app,
    "GET",
    Map([("If-Unmodified-Since", "Mon, 01 Jan 2024 00:00:00 GMT")]),
  )
  assert_eq(same.status, 200)
  let newer = probe_respond(
    app,
    "GET",
    Map([("If-Unmodified-Since", "Fri, 01 Jan 2027 00:00:00 GMT")]),
  )
  assert_eq(newer.status, 200)
  let bad = probe_respond(
    app,
    "GET",
    Map([("If-Unmodified-Since", "not a date")]),
  )
  assert_eq(bad.status, 200)
  let overridden = probe_respond(
    app,
    "GET",
    Map([
      ("If-Match", "\"v1\""),
      ("If-Unmodified-Since", "Sun, 01 Jan 2023 00:00:00 GMT"),
    ]),
  )
  assert_eq(overridden.status, 200)
}

///|
test "probe if-none-match and if-modified-since semantics" {
  let app = probe_precondition_app()
  let match_get = probe_respond(app, "GET", Map([("If-None-Match", "\"v1\"")]))
  assert_eq(match_get.status, 304)
  assert_eq(match_get.body, "")
  assert_eq(match_get.headers.get("ETag"), Some("\"v1\""))
  assert_eq(
    match_get.headers.get("Last-Modified"),
    Some("Mon, 01 Jan 2024 00:00:00 GMT"),
  )
  assert_eq(match_get.headers.get("Content-Type"), None)
  let match_head = probe_respond(app, "HEAD", Map([("If-None-Match", "\"v1\"")]))
  assert_eq(match_head.status, 304)
  let match_post = probe_respond(app, "POST", Map([("If-None-Match", "\"v1\"")]))
  assert_eq(match_post.status, 412)
  let weak_match = probe_respond(
    app,
    "GET",
    Map([("If-None-Match", "W/\"v1\"")]),
  )
  assert_eq(weak_match.status, 304)
  let list_match = probe_respond(
    app,
    "GET",
    Map([("If-None-Match", "\"a\", \"v1\", \"b\"")]),
  )
  assert_eq(list_match.status, 304)
  let star_match = probe_respond(app, "GET", Map([("If-None-Match", "*")]))
  assert_eq(star_match.status, 304)
  let ims_equal = probe_respond(
    app,
    "GET",
    Map([("If-Modified-Since", "Mon, 01 Jan 2024 00:00:00 GMT")]),
  )
  assert_eq(ims_equal.status, 304)
  let ims_older = probe_respond(
    app,
    "GET",
    Map([("If-Modified-Since", "Sun, 01 Jan 2023 00:00:00 GMT")]),
  )
  assert_eq(ims_older.status, 200)
  let ims_newer = probe_respond(
    app,
    "GET",
    Map([("If-Modified-Since", "Fri, 01 Jan 2027 00:00:00 GMT")]),
  )
  assert_eq(ims_newer.status, 304)
  let ims_post = probe_respond(
    app,
    "POST",
    Map([("If-Modified-Since", "Fri, 01 Jan 2027 00:00:00 GMT")]),
  )
  assert_eq(ims_post.status, 200)
  let inm_overrides_ims = probe_respond(
    app,
    "GET",
    Map([
      ("If-None-Match", "\"other\""),
      ("If-Modified-Since", "Fri, 01 Jan 2027 00:00:00 GMT"),
    ]),
  )
  assert_eq(inm_overrides_ims.status, 200)
}
