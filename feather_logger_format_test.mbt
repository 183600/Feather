///|
test "logger custom format replaces the default line" {
  let lines : Array[String] = []
  let elapsed : Ref[Int64] = Ref(-1L)
  let app = @feather.App::new()
    .use(
      @feather.middleware_logger(
        log=fn(line) { lines.push(line) },
        format=fn(ctx, millis) {
          elapsed.val = millis
          "custom:\{ctx.get_method()}:\{ctx.pathname()}:\{ctx.response.status}"
        },
      ),
    )
    .get("/items", fn(ctx) { ctx.text(200, "items") })
  ignore(
    app.respond({
      method: "GET",
      path: "/items",
      headers: Map([]),
      body: "",
    }),
  )
  assert_eq(lines, ["custom:GET:/items:200"])
  assert_true(elapsed.val >= 0L)
}

///|
test "logger custom format records the status of a raised error" {
  let lines : Array[String] = []
  let app = @feather.App::new()
    .use(
      @feather.middleware_logger(
        log=fn(line) { lines.push(line) },
        format=fn(ctx, _millis) {
          "error:\{ctx.get_method()}:\{ctx.pathname()}:\{ctx.response.status}"
        },
      ),
    )
    .get("/boom", fn(_ctx) raise { raise @feather.HttpError(503, "down") })
  let response = app.respond({
    method: "GET",
    path: "/boom",
    headers: Map([]),
    body: "",
  })
  assert_eq(response.status, 503)
  assert_eq(lines, ["error:GET:/boom:503"])
}

///|
test "logger custom format composes with skip" {
  let lines : Array[String] = []
  let app = @feather.App::new()
    .use(
      @feather.middleware_logger(
        log=fn(line) { lines.push(line) },
        skip=fn(ctx) { ctx.pathname() == "/health" },
        format=fn(ctx, _millis) { ctx.pathname() },
      ),
    )
    .get("/health", fn(ctx) { ctx.text(200, "ok") })
    .get("/api", fn(ctx) { ctx.text(200, "api") })
  ignore(
    app.respond({
      method: "GET",
      path: "/health",
      headers: Map([]),
      body: "",
    }),
  )
  ignore(
    app.respond({
      method: "GET",
      path: "/api",
      headers: Map([]),
      body: "",
    }),
  )
  assert_eq(lines, ["/api"])
}

///|
async test "logger custom format waits for a static response status" {
  let dir = @fs.tmpdir(prefix="feather-logger-format-static")
  @fs.write_file(dir + "/asset.txt", "asset")
  let lines : Array[String] = []
  let app = @feather.App::new()
    .use(
      @feather.middleware_logger(
        log=fn(line) { lines.push(line) },
        format=fn(ctx, _millis) {
          "\{ctx.response.status} \{ctx.pathname()}"
        },
      ),
    )
    .static_files("/assets", dir)
  with_server(app, client => {
    let response = client.get("/assets/asset.txt")
    assert_eq(response.code, 200)
    assert_eq(client.read_all().text(), "asset")
  })
  assert_eq(lines, ["200 /assets/asset.txt"])
  @fs.rmdir(dir, recursive=true)
}
