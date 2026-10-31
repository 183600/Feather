///|
test "middleware_recover_with renders typed errors through its callback" {
  let app = @feather.App::new()
    .use(@feather.middleware_recover_with(handler=fn(ctx, err) {
      match err {
        @feather.HttpError(status, message) =>
          ctx.text(status, "custom:" + message)
        @feather.HttpErrorPayload(_, message, _) =>
          ctx.text(409, "payload:" + message)
        @feather.HttpProblem(status, _, title, _, _) =>
          ctx.text(status, "problem:" + title)
        _ => ctx.text(500, "custom:internal")
      }
    }))
    .get("/teapot", fn(_ctx) raise {
      raise @feather.HttpError(418, "short and stout")
    })
    .get("/payload", fn(_ctx) raise {
      raise @feather.HttpErrorPayload(409, "conflict", Json::null())
    })
    .get("/problem", fn(_ctx) raise {
      raise @feather.HttpProblem(422, "", "bad input", "", "")
    })

  let teapot = app.respond({
    method: "GET",
    path: "/teapot",
    headers: Map([]),
    body: "",
  })
  assert_eq(teapot.status, 418)
  assert_eq(teapot.body, "custom:short and stout")

  let payload = app.respond({
    method: "GET",
    path: "/payload",
    headers: Map([]),
    body: "",
  })
  assert_eq(payload.status, 409)
  assert_eq(payload.body, "payload:conflict")

  let problem = app.respond({
    method: "GET",
    path: "/problem",
    headers: Map([]),
    body: "",
  })
  assert_eq(problem.status, 422)
  assert_eq(problem.body, "problem:bad input")
}

///|
test "middleware_recover_with handles non-HTTP errors" {
  let app = @feather.App::new()
    .use(@feather.middleware_recover_with(handler=fn(ctx, err) {
      let detail = match err {
        Failure(message) => message
        _ => "other"
      }
      ctx.text(@feather.error_status(err), "handled:" + detail)
    }))
    .get("/boom", fn(_ctx) raise { raise Failure("kaboom") })

  let response = app.respond({
    method: "GET",
    path: "/boom",
    headers: Map([]),
    body: "",
  })
  assert_eq(response.status, 500)
  assert_eq(response.body, "handled:kaboom")
}

///|
test "middleware_recover_with leaves errors raised by the callback visible" {
  let app = @feather.App::new()
    .use(@feather.middleware_recover_with(handler=fn(_ctx, _err) raise {
      raise Failure("render failed")
    }))
    .get("/boom", fn(_ctx) raise { raise @feather.HttpError(503, "down") })

  let response = app.respond({
    method: "GET",
    path: "/boom",
    headers: Map([]),
    body: "",
  })
  assert_eq(response.status, 500)
  assert_eq(response.body, "Internal Server Error")
}

///|
test "error_status reports framework statuses and defaults to 500" {
  assert_eq(@feather.error_status(@feather.HttpError(429, "slow")), 429)
  assert_eq(
    @feather.error_status(@feather.HttpErrorPayload(409, "conflict", Json::null())),
    409,
  )
  assert_eq(
    @feather.error_status(@feather.HttpProblem(422, "", "bad", "", "")),
    422,
  )
  assert_eq(@feather.error_status(Failure("boom")), 500)
}

///|
test "middleware_recover_with still runs request cleanups" {
  let cleaned : Array[String] = []
  let app = @feather.App::new()
    .use(@feather.middleware_recover_with(handler=fn(ctx, err) {
      ctx.text(@feather.error_status(err), "recovered")
    }))
    .get("/boom", fn(ctx) raise {
      ctx.defer_cleanup(fn() { cleaned.push("done") })
      raise @feather.HttpError(500, "boom")
    })

  let response = app.respond({
    method: "GET",
    path: "/boom",
    headers: Map([]),
    body: "",
  })
  assert_eq(response.status, 500)
  assert_eq(response.body, "recovered")
  assert_eq(cleaned, ["done"])
}
