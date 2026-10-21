///|
test "route middleware runs between app middleware and handler" {
  let order : Array[String] = []
  let route_middleware : @feather.Middleware = fn(next) {
    fn(ctx) raise {
      order.push("route")
      next(ctx)
      order.push("route_end")
    }
  }
  let app = @feather.App::new()
    .use(fn(next) {
      fn(ctx) raise {
        order.push("app")
        next(ctx)
        order.push("app_end")
      }
    })
    .route_with("GET", "/wrapped", [route_middleware], fn(ctx) {
      order.push("handler")
      ctx.text(200, "wrapped")
    })
  let response = app.respond({
    method: "GET",
    path: "/wrapped",
    headers: Map([]),
    body: "",
  })
  assert_eq(response.status, 200)
  assert_eq(response.body, "wrapped")
  assert_eq(order.join(","), "app,route,handler,route_end,app_end")
}

///|
test "route middleware only guards its own route" {
  let auth_gate : @feather.Middleware = fn(next) {
    fn(ctx) raise {
      if ctx.header("X-Key") == "open" {
        next(ctx)
      } else {
        ctx.text(401, "denied")
      }
    }
  }
  let app = @feather.App::new()
    .route_with("GET", "/private", [auth_gate], fn(ctx) {
      ctx.text(200, "secret")
    })
    .get("/public", fn(ctx) { ctx.text(200, "public") })
  let denied = app.respond({
    method: "GET",
    path: "/private",
    headers: Map([]),
    body: "",
  })
  assert_eq(denied.status, 401)
  assert_eq(denied.body, "denied")
  let allowed = app.respond({
    method: "GET",
    path: "/private",
    headers: { "X-Key": "open" },
    body: "",
  })
  assert_eq(allowed.status, 200)
  assert_eq(allowed.body, "secret")
  let open = app.respond({
    method: "GET",
    path: "/public",
    headers: Map([]),
    body: "",
  })
  assert_eq(open.status, 200)
  assert_eq(open.body, "public")
}

///|
test "route middleware sees bound path parameters" {
  let seen : Array[String] = []
  let record : @feather.Middleware = fn(next) {
    fn(ctx) raise {
      seen.push(ctx.param("id"))
      next(ctx)
    }
  }
  let app = @feather.App::new().route_with("GET", "/users/:id", [record], fn(
    ctx,
  ) {
    ctx.text(200, ctx.param("id"))
  })
  let response = app.respond({
    method: "GET",
    path: "/users/42",
    headers: Map([]),
    body: "",
  })
  assert_eq(response.body, "42")
  assert_eq(seen.join(","), "42")
}

///|
test "group middleware wraps route middleware" {
  let order : Array[String] = []
  let app = @feather.App::new()
  let api = app.group("/api")
  ignore(
    api.use(fn(next) {
      fn(ctx) raise {
        order.push("group")
        next(ctx)
        order.push("group_end")
      }
    }),
  )
  ignore(
    api.route_with(
      "GET",
      "/items",
      [
        fn(next) {
          fn(ctx) raise {
            order.push("route")
            next(ctx)
            order.push("route_end")
          }
        },
      ],
      fn(ctx) {
        order.push("handler")
        ctx.text(200, "items")
      },
    ),
  )
  let response = app.respond({
    method: "GET",
    path: "/api/items",
    headers: Map([]),
    body: "",
  })
  assert_eq(response.status, 200)
  assert_eq(response.body, "items")
  assert_eq(order.join(","), "group,route,handler,route_end,group_end")
}

///|
test "route_with without middleware behaves like route" {
  let app = @feather.App::new().route_with("GET", "/ping", [], fn(ctx) {
    ctx.text(200, "pong")
  })
  let response = app.respond({
    method: "GET",
    path: "/ping",
    headers: Map([]),
    body: "",
  })
  assert_eq(response.status, 200)
  assert_eq(response.body, "pong")
}

///|
test "Feather facade route_with registers guarded routes" {
  let feather = @feather.create_feather({
    host: "127.0.0.1",
    port: 0,
    timeout: 0,
  })
  let auth_gate : @feather.Middleware = fn(next) {
    fn(ctx) raise {
      if ctx.header("Authorization") == "Bearer token" {
        next(ctx)
      } else {
        ctx.text(403, "forbidden")
      }
    }
  }
  ignore(
    feather.route_with("GET", "/admin", [auth_gate], fn(ctx) {
      ctx.text(200, "admin")
    }),
  )
  let denied = feather.handle({
    method: "GET",
    path: "/admin",
    headers: Map([]),
    body: "",
  })
  assert_eq(denied.status, 403)
  let allowed = feather.handle({
    method: "GET",
    path: "/admin",
    headers: { "Authorization": "Bearer token" },
    body: "",
  })
  assert_eq(allowed.status, 200)
  assert_eq(allowed.body, "admin")
}

///|
async test "sse route middleware can reject or decorate the stream" {
  let app = @feather.App::new()
    .use(fn(next) {
      fn(ctx) raise {
        ctx.set_header("X-App", "yes")
        next(ctx)
      }
    })
    .sse_with(
      "/events",
      [
        fn(next) {
          fn(ctx) raise {
            if ctx.header("X-Token") == "ok" {
              ctx.set_header("X-Route", "yes")
              next(ctx)
            } else {
              ctx.text(401, "unauthorized")
            }
          }
        },
      ],
      async fn(_ctx, sse) { sse.send("live") },
    )
  with_sse_server(app, client => {
    let rejected = client.get("/events")
    assert_eq(rejected.code, 401)
    assert_eq(client.read_all().text(), "unauthorized")
    let response = client.get(
      "/events",
      extra_headers=Map([(@http.CaseInsensitiveString("X-Token"), "ok")]),
    )
    assert_eq(response.code, 200)
    assert_eq(
      response.headers.get(@http.CaseInsensitiveString("X-Route")),
      Some("yes"),
    )
    assert_eq(
      response.headers.get(@http.CaseInsensitiveString("X-App")),
      Some("yes"),
    )
    assert_eq(client.read_all().text(), "data: live\n\n")
  })
}

///|
async test "websocket route middleware runs before the upgrade" {
  let app = @feather.App::new().websocket_with(
    "/ws/secure",
    [
      fn(next) {
        fn(ctx) raise {
          if ctx.header("X-Token") == "secret" {
            next(ctx)
          } else {
            ctx.text(401, "unauthorized")
          }
        }
      },
    ],
    fn(_ctx, ws) {
      ws.send_text("welcome")
      ws.send_close()
    },
  )
  with_server(app, client => {
    let response = client.get("/ws/secure")
    assert_eq(response.code, 401)
    assert_eq(client.read_all().text(), "unauthorized")
  })
  with_ws_server(app, base => {
    let ws = @websocket.connect(
      base + "/ws/secure",
      headers=Map([(@http.CaseInsensitiveString("X-Token"), "secret")]),
    )
    defer ws.close()
    let msg = ws.recv()
    assert_eq(msg.read_all().text(), "welcome")
    ws.send_close()
  })
}

///|
async test "stream route middleware can reject or tailor the stream" {
  let app = @feather.App::new().stream_with(
    "/feed",
    [
      fn(next) {
        fn(ctx) raise {
          if ctx.header("X-Token") == "ok" {
            ctx.status(201)
            next(ctx)
          } else {
            ctx.text(401, "unauthorized")
          }
        }
      },
    ],
    async fn(_ctx, stream) { stream.write("live") },
  )
  with_stream_server(app, client => {
    let rejected = client.get("/feed")
    assert_eq(rejected.code, 401)
    assert_eq(client.read_all().text(), "unauthorized")
    let response = client.get(
      "/feed",
      extra_headers=Map([(@http.CaseInsensitiveString("X-Token"), "ok")]),
    )
    assert_eq(response.code, 201)
    assert_eq(client.read_all().text(), "live")
  })
}
