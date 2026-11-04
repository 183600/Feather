///|
test "middleware_metrics records requests per route pattern and status" {
  let metrics = @feather.Metrics::new()
  let app = @feather.App::new()
    .use(@feather.middleware_metrics(metrics))
    .get("/users/:id", fn(ctx) { ctx.text(200, ctx.param("id")) })
    .get("/health", fn(ctx) { ctx.text(200, "ok") })
  ignore(app.respond({
    method: "GET",
    path: "/users/1",
    headers: Map([]),
    body: "",
  }))
  ignore(app.respond({
    method: "GET",
    path: "/users/2",
    headers: Map([]),
    body: "",
  }))
  ignore(app.respond({
    method: "GET",
    path: "/health",
    headers: Map([]),
    body: "",
  }))
  assert_eq(metrics.count("GET", "/users/:id", 200), 2L)
  assert_eq(metrics.count("GET", "/health", 200), 1L)
  assert_eq(metrics.total(), 3L)
  assert_eq(metrics.series_count(), 2)
}

///|
test "middleware_metrics groups requests that did not match a route" {
  let metrics = @feather.Metrics::new()
  let app = @feather.App::new()
    .use(@feather.middleware_metrics(metrics))
    .get("/known", fn(ctx) { ctx.text(200, "known") })
  ignore(app.respond({
    method: "GET",
    path: "/missing",
    headers: Map([]),
    body: "",
  }))
  ignore(app.respond({
    method: "POST",
    path: "/known",
    headers: Map([]),
    body: "",
  }))
  assert_eq(metrics.count("GET", @feather.METRICS_UNMATCHED_ROUTE, 404), 1L)
  assert_eq(metrics.count("POST", @feather.METRICS_UNMATCHED_ROUTE, 405), 1L)
  assert_eq(metrics.count("GET", "/known", 200), 0L)
}

///|
test "middleware_metrics records the status of an error response" {
  let metrics = @feather.Metrics::new()
  let app = @feather.App::new()
    .use(@feather.middleware_recover())
    .use(@feather.middleware_metrics(metrics))
    .get("/boom", fn(ctx) raise { ctx.fail(400, "bad") })
  let response = app.respond({
    method: "GET",
    path: "/boom",
    headers: Map([]),
    body: "",
  })
  assert_eq(response.status, 400)
  assert_eq(metrics.count("GET", "/boom", 400), 1L)
}

///|
test "middleware_metrics records the request method" {
  let metrics = @feather.Metrics::new()
  let app = @feather.App::new()
    .use(@feather.middleware_metrics(metrics))
    .get("/report", fn(ctx) { ctx.text(200, "report") })
  ignore(app.respond({
    method: "HEAD",
    path: "/report",
    headers: Map([]),
    body: "",
  }))
  assert_eq(metrics.count("HEAD", "/report", 200), 1L)
  assert_eq(metrics.count("GET", "/report", 200), 0L)
}

///|
test "metrics render the prometheus text exposition format" {
  let metrics = @feather.Metrics::new()
  let app = @feather.App::new()
    .use(@feather.middleware_metrics(metrics))
    .get("/items/:id", fn(ctx) { ctx.text(200, "item") })
  ignore(app.respond({
    method: "GET",
    path: "/items/7",
    headers: Map([]),
    body: "",
  }))
  let text = metrics.render()
  assert_true(
    text.contains(
      "# TYPE feather_http_requests_total counter",
    ),
    msg="expected the counter type line",
  )
  assert_true(
    text.contains(
      "feather_http_requests_total{method=\"GET\",route=\"/items/:id\",status=\"200\"} 1",
    ),
    msg="expected the request counter series",
  )
  assert_true(
    text.contains(
      "feather_http_request_duration_milliseconds_count{method=\"GET\",route=\"/items/:id\",status=\"200\"} 1",
    ),
    msg="expected the duration count series",
  )
  assert_true(
    text.contains(
      "# TYPE feather_http_request_duration_milliseconds summary",
    ),
    msg="expected the summary type line",
  )
}

///|
test "metrics render an empty exposition with the metric families" {
  let metrics = @feather.Metrics::new()
  let text = metrics.render()
  assert_true(text.contains("feather_http_requests_total"), msg="expected counter")
  assert_true(
    text.contains("feather_http_request_duration_milliseconds"),
    msg="expected duration summary",
  )
  assert_eq(metrics.total(), 0L)
}

///|
test "metrics escape the label values of the exposition" {
  let metrics = @feather.Metrics::new()
  metrics.record("GET", "/a\"b\\c", 200, 3L)
  let text = metrics.render()
  assert_true(
    text.contains("route=\"/a\\\"b\\\\c\""),
    msg="expected the escaped route label",
  )
}

///|
test "metrics write the exposition as a response" {
  let metrics = @feather.Metrics::new()
  metrics.record("GET", "/", 200, 1L)
  let app = @feather.App::new().get("/metrics", fn(ctx) { metrics.write(ctx) })
  let response = app.respond({
    method: "GET",
    path: "/metrics",
    headers: Map([]),
    body: "",
  })
  assert_eq(response.status, 200)
  assert_eq(
    response.headers.get("Content-Type"),
    Some(@feather.METRICS_CONTENT_TYPE),
  )
  assert_true(
    response.body.contains("feather_http_requests_total"),
    msg="expected the exposition body",
  )
}

///|
test "metrics accumulate the recorded duration" {
  let metrics = @feather.Metrics::new()
  metrics.record("GET", "/", 200, 10L)
  metrics.record("GET", "/", 200, 5L)
  assert_eq(metrics.count("GET", "/", 200), 2L)
  assert_eq(metrics.duration_sum("GET", "/", 200), 15L)
  assert_eq(metrics.duration_sum("GET", "/other", 200), 0L)
}

///|
test "metrics series are rendered in a stable order" {
  let metrics = @feather.Metrics::new()
  metrics.record("POST", "/b", 500, 1L)
  metrics.record("GET", "/b", 200, 1L)
  metrics.record("GET", "/a", 404, 1L)
  let text = metrics.render()
  let first = text.find("route=\"/a\"")
  let second = text.find("route=\"/b\"")
  match (first, second) {
    (Some(first), Some(second)) => assert_true(first < second, msg="expected sorted routes")
    _ => fail("expected both routes in the exposition")
  }
}

///|
async test "middleware_metrics records requests served by the server" {
  let metrics = @feather.Metrics::new()
  let app = @feather.App::new()
    .use(@feather.middleware_metrics(metrics))
    .get("/hello", fn(ctx) { ctx.text(200, "hello") })
  with_server(app, client => {
    let response = client.get("/hello")
    assert_eq(response.code, 200)
    ignore(client.read_all())
  })
  assert_eq(metrics.count("GET", "/hello", 200), 1L)
}
