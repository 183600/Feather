///|
fn logger_skip_request(path : String) -> @feather.Request {
  { method: "GET", path, headers: Map([]), body: "", }
}

///|
test "logger skip omits matching requests and still runs the handler" {
  let lines : Ref[Array[String]] = Ref([])
  let hits = Ref(0)
  let app = @feather.App::new()
    .use(
      @feather.middleware_logger(
        log=fn(line) { lines.val.push(line) },
        skip=fn(ctx) { ctx.pathname() == "/health" },
      ),
    )
    .get("/health", fn(ctx) {
      hits.val = hits.val + 1
      ctx.text(200, "ok")
    })
    .get("/items", fn(ctx) { ctx.text(200, "items") })
  assert_eq(app.respond(logger_skip_request("/health")).status, 200)
  assert_eq(hits.val, 1)
  assert_eq(lines.val.length(), 0)
  assert_eq(app.respond(logger_skip_request("/items")).status, 200)
  assert_eq(lines.val.length(), 1)
  assert_eq(lines.val[0], "[200] GET /items")
}

///|
test "logger skip sees state established by earlier middleware" {
  let lines : Ref[Array[String]] = Ref([])
  let app = @feather.App::new()
    .use(fn(next) {
      fn(ctx) raise {
        if ctx.pathname() == "/probe" {
          ctx.set("quiet", "1")
        }
        next(ctx)
      }
    })
    .use(
      @feather.middleware_logger(
        log=fn(line) { lines.val.push(line) },
        skip=fn(ctx) { ctx.get("quiet") == "1" },
      ),
    )
    .get("/probe", fn(ctx) { ctx.text(200, "probe") })
    .get("/other", fn(ctx) { ctx.text(200, "other") })
  ignore(app.respond(logger_skip_request("/probe")))
  ignore(app.respond(logger_skip_request("/other")))
  assert_eq(lines.val.length(), 1)
  assert_eq(lines.val[0], "[200] GET /other")
}

///|
test "logger duration and skip compose" {
  let lines : Ref[Array[String]] = Ref([])
  let app = @feather.App::new()
    .use(
      @feather.middleware_logger(
        log=fn(line) { lines.val.push(line) },
        with_duration=true,
        skip=fn(ctx) { ctx.pathname() == "/skip" },
      ),
    )
    .get("/timed", fn(ctx) { ctx.text(200, "timed") })
    .get("/skip", fn(ctx) { ctx.text(200, "skip") })
  ignore(app.respond(logger_skip_request("/timed")))
  ignore(app.respond(logger_skip_request("/skip")))
  assert_eq(lines.val.length(), 1)
  assert_true(lines.val[0].has_prefix("[200] GET /timed ("))
}

///|
async test "logger skip silences static asset requests" {
  let dir = @fs.tmpdir(prefix="feather-logger-skip-static")
  @fs.write_file(dir + "/asset.txt", "asset")
  let lines : Ref[Array[String]] = Ref([])
  let app = @feather.App::new()
    .use(
      @feather.middleware_logger(
        log=fn(line) { lines.val.push(line) },
        skip=fn(ctx) { ctx.pathname().has_prefix("/assets") },
      ),
    )
    .static_files("/assets", dir)
    .get("/api", fn(ctx) { ctx.text(200, "api") })
  with_server(app, client => {
    let asset = client.get("/assets/asset.txt")
    assert_eq(asset.code, 200)
    assert_eq(client.read_all().text(), "asset")
    let api = client.get("/api")
    assert_eq(api.code, 200)
    assert_eq(client.read_all().text(), "api")
  })
  assert_eq(lines.val.length(), 1)
  assert_eq(lines.val[0], "[200] GET /api")
  @fs.rmdir(dir, recursive=true)
}

