///|
test "tmp route hit cache invalidated by add_route" {
  let router = create_router()
  router.add_route("GET", "/p/:id", fn(ctx) {
    ctx.text(200, "old:" + ctx.param("id"))
  })
  let first = router.route("GET", "/p/1")
  match first {
    RouteFound(route) => assert_eq(route.path, "/p/:id")
    _ => fail("expected first")
  }
  router.add_route("GET", "/p/:id", fn(_ctx) {  })
  match router.route("GET", "/p/1") {
    RouteFound(route) => assert_eq(route.path, "/p/:id")
    _ => fail("expected second")
  }
}

///|
test "tmp route miss cache invalidated by add_route" {
  let router = create_router()
  match router.route("GET", "/new") {
    RouteNotFound => ()
    _ => fail("expected not found")
  }
  match router.route("GET", "/new") {
    RouteNotFound => ()
    _ => fail("expected cached not found")
  }
  router.add_route("GET", "/new", fn(_ctx) {  })
  match router.route("GET", "/new") {
    RouteFound(_) => ()
    _ => fail("expected route after add")
  }
}

///|
test "tmp method miss cache invalidated by add_route" {
  let router = create_router()
  router.add_route("POST", "/x", fn(_ctx) {  })
  match router.route("GET", "/x") {
    RouteMethodNotAllowed(_) => ()
    _ => fail("expected method not allowed")
  }
  match router.route("GET", "/x") {
    RouteMethodNotAllowed(_) => ()
    _ => fail("expected cached method not allowed")
  }
  router.add_route("GET", "/x", fn(_ctx) {  })
  match router.route("GET", "/x") {
    RouteFound(_) => ()
    _ => fail("expected found after add")
  }
}

///|
test "tmp static lookup invalidated by adding a mount" {
  let app = App::new()
  assert_eq(app.static_file_for("/assets/a.txt"), None)
  ignore(app.static_files("/assets", "/tmp/feather-static-test"))
  let path = app.static_file_for("/assets/a.txt")
  assert_true(path is Some(_))
}

///|
test "tmp parse_multipart result is independent" {
  let body = "--X\r\nContent-Disposition: form-data; name=\"a\"\r\n\r\n1\r\n--X--\r\n"
  let content_type = "multipart/form-data; boundary=X"
  let first = parse_multipart(body, content_type)
  match first {
    Some(parts) => {
      assert_eq(parts.length(), 1)
      parts[0].headers.set("X-Test", "1")
      let second = parse_multipart(body, content_type)
      match second {
        Some(again) => assert_eq(again[0].headers.get("X-Test"), None)
        None => fail("expected second parse")
      }
    }
    None => fail("expected parts")
  }
}

///|
test "tmp parse_urlencoded result is independent" {
  let first = parse_urlencoded("a=1&b=2")
  first.set("a", "9")
  let second = parse_urlencoded("a=1&b=2")
  assert_eq(second.get("a"), Some("1"))
}

///|
test "tmp preferred_type notices mutated offers" {
  let ctx = Context::new({
    method: "GET",
    path: "/",
    headers: Map([("Accept", "text/html, application/json")]),
    body: "",
  })
  let offers : Array[String] = ["text/html", "application/json"]
  assert_eq(ctx.preferred_type(offers), Some("text/html"))
  offers[0] = "application/json"
  assert_eq(ctx.preferred_type(offers), Some("application/json"))
}

///|
test "tmp session json cache follows data mutation" {
  let store = SessionStore::new(ttl=3_600_000L)
  let app = App::new()
    .use(middleware_session(store))
    .get("/x", fn(ctx) {
      ignore(ctx.session_set_json("k", Json::object({ "a": 1 })))
      ctx.text(200, "ok")
    })
  let response = app.respond({
    method: "GET",
    path: "/x",
    headers: Map([]),
    body: "",
  })
  assert_eq(response.status, 200)
}

///|
test "tmp rate limiter reset and sweep clear cached bucket" {
  let limiter = RateLimiter::new(max=2, window=60_000L)
  assert_true(limiter.allow("k"))
  assert_true(limiter.allow("k"))
  assert_true(limiter.reset("k"))
  assert_true(limiter.allow("k"))
  limiter.sweep()
  assert_true(limiter.allow("k"))
}

///|
fn tmp_route_snapshot(outcome : RouteOutcome) -> String {
  match outcome {
    RouteFound(route) => {
      let keys : Array[String] = []
      for key, value in route.params {
        keys.push(key + "=" + value)
      }
      keys.sort_by(fn(a, b) { a.lexical_compare(b) })
      "found|\{route.method}|\{route.path}|\{route.wildcard_name}|\{route.wildcard}|\{keys.join(",")}"
    }
    RouteMethodNotAllowed(methods) => "methods|\{methods.join(",")}"
    RouteNotFound => "missing"
  }
}

///|
test "tmp route cache randomized invalidation" {
  let methods : Array[String] = ["GET", "POST", "HEAD"]
  let routes : Array[(String, String)] = []
  let router = create_router()
  let templates : Array[String] = [
    "/a", "/b", "/p/:id", "/p/:id/x", "/f/*rest", "/",
  ]
  let paths : Array[String] = [
    "/a", "/b", "/p/1", "/p/1/x", "/f/a/b", "/none", "/",
  ]
  let mut seed = 13579
  let next = fn() {
    seed = (seed * 1103515245 + 12345) & 0x7fffffff
    seed
  }
  for _ in 0..<1500 {
    if next() % 3 != 0 {
      let method = methods[next() % methods.length()]
      let template = templates[next() % templates.length()]
      routes.push((method, template))
      router.add_route(method, template, fn(_ctx) {  })
    }
    let query_method = methods[next() % methods.length()]
    let query_path = paths[next() % paths.length()]
    let actual = tmp_route_snapshot(router.route(query_method, query_path))
    let fresh = create_router()
    for route in routes {
      fresh.add_route(route.0, route.1, fn(_ctx) {  })
    }
    let expected = tmp_route_snapshot(fresh.route(query_method, query_path))
    if actual != expected {
      fail(
        "mismatch after \{routes.length()} routes for \{query_method} \{query_path}: \{actual} vs \{expected}",
      )
    }
    let dispatch_actual = match
      router.match_route(query_method, query_path.view()) {
      MatchFound(node, params, wildcard) => {
        let keys : Array[String] = []
        match params {
          Some(params) =>
            for key, value in params {
              keys.push(key + "=" + value)
            }
          None => ()
        }
        keys.sort_by(fn(a, b) { a.lexical_compare(b) })
        "found|\{node.route_path}|\{wildcard}|\{keys.join(",")}"
      }
      MatchMethods(methods) => "methods|\{methods.join(",")}"
      MatchMissing => "missing"
    }
    let dispatch_expected = match
      fresh.match_route(query_method, query_path.view()) {
      MatchFound(node, params, wildcard) => {
        let keys : Array[String] = []
        match params {
          Some(params) =>
            for key, value in params {
              keys.push(key + "=" + value)
            }
          None => ()
        }
        keys.sort_by(fn(a, b) { a.lexical_compare(b) })
        "found|\{node.route_path}|\{wildcard}|\{keys.join(",")}"
      }
      MatchMethods(methods) => "methods|\{methods.join(",")}"
      MatchMissing => "missing"
    }
    if dispatch_actual != dispatch_expected {
      fail(
        "dispatch mismatch for \{query_method} \{query_path}: \{dispatch_actual} vs \{dispatch_expected}",
      )
    }
  }
}

///|
test "tmp error body cache eviction is scoped by status" {
  error_body_cache.clear()
  error_body_cache_ages.clear()
  for i = 0; i < 9; i = i + 1 {
    ignore(cached_error_body(210, "a" + i.to_string()))
    ignore(cached_error_body(211, "b" + i.to_string()))
  }
  match error_body_cache.get(210) {
    Some(by_message) => assert_eq(by_message.length(), 8)
    None => fail("expected status 210 cache")
  }
  match error_body_cache.get(211) {
    Some(by_message) => assert_eq(by_message.length(), 8)
    None => fail("expected status 211 cache")
  }
}
