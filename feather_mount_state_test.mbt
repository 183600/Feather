///|
test "mounted child state is available to handlers and child middleware" {
  let child = @feather.App::new()
    .set_state("config", "child-config")
    .set_json_state("limits", Json::object({ "rps": 10 }))
    .use(fn(next) {
      fn(ctx) raise {
        ctx.set_header("X-Child-Config", ctx.get("config"))
        next(ctx)
      }
    })
    .get("/ping", fn(ctx) {
      let limits = ctx.get_json("limits").unwrap_or(Json::null()).stringify()
      ctx.text(200, ctx.get("config") + "|" + limits)
    })
  let parent = @feather.App::new().mount("/api", child)
  let mounted = parent.respond({
    method: "GET",
    path: "/api/ping",
    headers: Map([]),
    body: "",
  })
  assert_eq(mounted.status, 200)
  assert_eq(mounted.body, "child-config|{\"rps\":10}")
  assert_eq(mounted.headers.get("X-Child-Config"), Some("child-config"))
}

///|
test "mounted applications keep their state scoped" {
  let one = @feather.App::new()
    .set_state("name", "one")
    .get("/", fn(ctx) { ctx.text(200, ctx.get("name")) })
  let two = @feather.App::new()
    .set_state("name", "two")
    .get("/", fn(ctx) { ctx.text(200, ctx.get("name")) })
  let parent = @feather.App::new().mount("/one", one).mount("/two", two)
  let first = parent.respond({
    method: "GET",
    path: "/one",
    headers: Map([]),
    body: "",
  })
  let second = parent.respond({
    method: "GET",
    path: "/two",
    headers: Map([]),
    body: "",
  })
  assert_eq(first.body, "one")
  assert_eq(second.body, "two")
}
