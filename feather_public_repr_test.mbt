///|
/// The endpoint list is meant for startup logging and generated API
/// documentation, so an endpoint and its kind must be printable.
test "endpoints can be rendered for startup logging" {
  let app = @feather.App::new()
  ignore(app.get("/plain", fn(ctx) { ctx.text(200, "ok") }))
  ignore(app.websocket("/ws", async fn(_ctx, _ws) { @async.pause() }))
  ignore(app.sse("/events", async fn(_ctx, _sse) { @async.pause() }))
  ignore(app.stream("/stream", async fn(_ctx, _out) { @async.pause() }))
  ignore(app.static_files("/assets", "/tmp/feather-endpoint-repr"))
  let endpoints = app.endpoints()
  assert_eq(endpoints.length(), 5)
  for endpoint in endpoints {
    let rendered = endpoint.to_string()
    assert_true(
      rendered.has_prefix("@feather.Endpoint("),
      msg=rendered,
    )
    assert_true(rendered.contains(endpoint.method), msg=rendered)
    assert_true(rendered.contains(endpoint.path), msg=rendered)
    assert_true(
      rendered.contains(endpoint.kind.to_string()),
      msg=rendered,
    )
    let debug = Repr::to_string(endpoint.to_repr())
    assert_true(debug.contains("method"), msg=debug)
    assert_true(debug.contains("kind"), msg=debug)
  }
}

///|
test "endpoint kinds have stable names" {
  assert_eq(@feather.EndpointKind::EndpointRoute.to_string(), "EndpointRoute")
  assert_eq(
    @feather.EndpointKind::EndpointWebSocket.to_string(),
    "EndpointWebSocket",
  )
  assert_eq(@feather.EndpointKind::EndpointSse.to_string(), "EndpointSse")
  assert_eq(@feather.EndpointKind::EndpointStream.to_string(), "EndpointStream")
  assert_eq(@feather.EndpointKind::EndpointStatic.to_string(), "EndpointStatic")
}

///|
test "requests and responses can be rendered for debugging" {
  let request : @feather.Request = {
    method: "GET",
    path: "/items",
    headers: Map([("X-Test", "1")]),
    body: "",
  }
  let rendered_request = request.to_string()
  assert_true(rendered_request.has_prefix("@feather.Request("), msg=rendered_request)
  assert_true(rendered_request.contains("GET"), msg=rendered_request)
  assert_true(rendered_request.contains("/items"), msg=rendered_request)
  assert_true(rendered_request.contains("X-Test"), msg=rendered_request)
  let debug_request = Repr::to_string(request.to_repr())
  assert_true(debug_request.contains("method"), msg=debug_request)
  assert_true(debug_request.contains("path"), msg=debug_request)

  let response = @feather.App::new()
    .get("/items", fn(ctx) { ctx.text(200, "items") })
    .respond(request)
  let rendered_response = response.to_string()
  assert_true(
    rendered_response.has_prefix("@feather.Response("),
    msg=rendered_response,
  )
  assert_true(rendered_response.contains("200"), msg=rendered_response)
  let debug_response = Repr::to_string(response.to_repr())
  assert_true(debug_response.contains("status"), msg=debug_response)
  assert_true(debug_response.contains("headers"), msg=debug_response)
}

///|
test "byte ranges can be rendered for debugging" {
  assert_eq(@feather.ByteRange::ByteRangeFull.to_string(), "ByteRangeFull")
  assert_eq(
    @feather.ByteRange::ByteRangeInvalid.to_string(),
    "ByteRangeInvalid",
  )
  let spec = @feather.ByteRange::ByteRangeSpec(2L, 5L)
  assert_true(spec.to_string().contains("2"), msg=spec.to_string())
  assert_true(spec.to_string().contains("5"), msg=spec.to_string())
}

///|
test "the framework configuration can be rendered for debugging" {
  let config : @feather.Config = {
    host: "127.0.0.1",
    port: 8080,
    timeout: 1000,
  }
  assert_true(
    config.to_string().has_prefix("@feather.Config("),
    msg=config.to_string(),
  )
  assert_true(config.to_string().contains("8080"), msg=config.to_string())
}
