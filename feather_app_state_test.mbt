///|
fn app_state_request(path : String) -> @feather.Request {
  { method: "GET", path, headers: Map([]), body: "", }
}

///|
test "app state is visible to middleware and handlers" {
  let app = @feather.App::new()
    .set_state("greeting", "hello")
    .use(fn(next) {
      fn(ctx) raise {
        ctx.set("seen", ctx.get("greeting"))
        next(ctx)
      }
    })
    .get("/", fn(ctx) { ctx.text(200, ctx.get("seen")) })
  let response = app.respond(app_state_request("/"))
  assert_eq(response.status, 200)
  assert_eq(response.body, "hello")
}

///|
test "handler writes do not mutate app state" {
  let app = @feather.App::new()
    .set_state("mode", "prod")
    .get("/", fn(ctx) {
      ctx.text(200, ctx.get("mode"))
      ctx.set("mode", "request")
    })
  let first = app.respond(app_state_request("/"))
  assert_eq(first.body, "prod")
  assert_eq(app.get_state("mode"), "prod")
  let second = app.respond(app_state_request("/"))
  assert_eq(second.body, "prod")
}

///|
test "request state overrides app state for one request" {
  let app = @feather.App::new()
    .set_state("tenant", "default")
    .get("/", fn(ctx) { ctx.text(200, ctx.get("tenant")) })
  let ctx = @feather.Context::new(app_state_request("/"))
  ctx.set("tenant", "acme")
  app.handle(ctx)
  assert_eq(ctx.response.body, "acme")
  let response = app.respond(app_state_request("/"))
  assert_eq(response.body, "default")
}

///|
test "app json state can be read through the context" {
  let app = @feather.App::new()
    .set_json_state("limits", Json::object({ "rps": 10 }))
    .get("/", fn(ctx) {
      let value = ctx.get_json("limits").unwrap_or(Json::null())
      ctx.text(200, value.stringify())
    })
  let response = app.respond(app_state_request("/"))
  assert_eq(response.body, "{\"rps\":10}")
}

///|
test "removing app state stops seeding new requests" {
  let app = @feather.App::new()
    .set_state("flag", "on")
    .set_json_state("box", Json::string("x"))
    .remove_state("flag")
    .remove_json_state("box")
    .get("/", fn(ctx) {
      let json_seen = ctx.get_json("box") is Some(_)
      ctx.text(200, ctx.get("flag") + ":" + json_seen.to_string())
    })
  assert_eq(app.get_state("flag"), "")
  assert_true(app.get_json_state("box") is None)
  let response = app.respond(app_state_request("/"))
  assert_eq(response.body, ":false")
}

///|
test "feather facade forwards app state helpers" {
  let feather = @feather.create_feather({
      host: "127.0.0.1",
      port: 0,
      timeout: 0,
    })
    .set_state("name", "feather")
    .set_json_state("version", Json::number(1))
  assert_eq(feather.get_state("name"), "feather")
  assert_true(feather.get_json_state("version") is Some(_))
  ignore(feather.remove_state("name"))
  ignore(feather.remove_json_state("version"))
  assert_eq(feather.get_state("name"), "")
  assert_true(feather.get_json_state("version") is None)
}
