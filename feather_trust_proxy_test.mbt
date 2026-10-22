///|
fn ip_app(hops : Int32) -> @feather.App {
  @feather.App::new()
    .trust_proxy(hops)
    .use(fn(next) {
      fn(ctx) {
        ctx.state.set("remote_addr", "10.0.0.9")
        next(ctx)
      }
    })
    .get("/ip", fn(ctx) { ctx.text(200, ctx.ip()) })
}

///|
fn ip_of(app : @feather.App, headers : Map[String, String]) -> String {
  let response = app.respond({
    method: "GET",
    path: "/ip",
    headers,
    body: "",
  })
  response.body
}

///|
test "context ip reports the peer address without trusted proxies" {
  let app = ip_app(0)
  assert_eq(ip_of(app, Map([])), "10.0.0.9")
  assert_eq(
    ip_of(app, Map([("X-Forwarded-For", "203.0.113.7")])),
    "10.0.0.9",
  )
  assert_eq(
    ip_of(app, Map([("Forwarded", "for=203.0.113.7")])),
    "10.0.0.9",
  )
}

///|
test "one trusted proxy reports the address it recorded" {
  let app = ip_app(1)
  assert_eq(ip_of(app, Map([("X-Forwarded-For", "203.0.113.7")])), "203.0.113.7")
  assert_eq(
    ip_of(app, Map([("X-Forwarded-For", "203.0.113.7, 198.51.100.4")])),
    "198.51.100.4",
  )
  assert_eq(ip_of(app, Map([("Forwarded", "for=203.0.113.7")])), "203.0.113.7")
}

///|
test "two trusted proxies report the original client" {
  let app = ip_app(2)
  assert_eq(
    ip_of(app, Map([("X-Forwarded-For", "203.0.113.7, 198.51.100.4")])),
    "203.0.113.7",
  )
  assert_eq(
    ip_of(
      app,
      Map([("Forwarded", "for=203.0.113.7, for=198.51.100.4")]),
    ),
    "203.0.113.7",
  )
}

///|
test "trusting the whole chain reports the left-most address" {
  let app = ip_app(-1)
  assert_eq(
    ip_of(app, Map([("X-Forwarded-For", "203.0.113.7, 198.51.100.4")])),
    "203.0.113.7",
  )
  assert_eq(
    ip_of(
      app,
      Map([("Forwarded", "for=203.0.113.7, for=198.51.100.4")]),
    ),
    "203.0.113.7",
  )
}

///|
test "the trusted chain is clamped to the addresses it has" {
  let app = ip_app(5)
  assert_eq(
    ip_of(app, Map([("X-Forwarded-For", "203.0.113.7, 198.51.100.4")])),
    "203.0.113.7",
  )
}

///|
test "the forwarded header wins over x-forwarded-for" {
  let app = ip_app(1)
  assert_eq(
    ip_of(
      app,
      Map([
        ("Forwarded", "for=203.0.113.7"),
        ("X-Forwarded-For", "198.51.100.4"),
      ]),
    ),
    "203.0.113.7",
  )
}

///|
test "forwarded nodes without an address keep their hop position" {
  let app = ip_app(1)
  assert_eq(
    ip_of(app, Map([("Forwarded", "for=_hidden, for=198.51.100.4")])),
    "198.51.100.4",
  )
  assert_eq(
    ip_of(app, Map([("Forwarded", "for=unknown, for=198.51.100.4")])),
    "198.51.100.4",
  )
  // The trusted proxy appended an address-less node, so the earlier value is
  // client-controlled and must not be trusted as the reported client.
  assert_eq(
    ip_of(app, Map([("Forwarded", "for=203.0.113.7, for=_hidden")])),
    "10.0.0.9",
  )
  let two = ip_app(2)
  assert_eq(
    ip_of(two, Map([("Forwarded", "for=_hidden, for=198.51.100.4")])),
    "10.0.0.9",
  )
}

///|
test "an address-less forwarded node suppresses the x-forwarded-for fallback" {
  let app = ip_app(1)
  assert_eq(
    ip_of(
      app,
      Map([
        ("Forwarded", "for=_hidden"),
        ("X-Forwarded-For", "203.0.113.7"),
      ]),
    ),
    "10.0.0.9",
  )
  // Without any `for=` parameter the RFC 7239 header is not a usable chain, so
  // the legacy header is still consulted.
  assert_eq(
    ip_of(
      app,
      Map([
        ("Forwarded", "proto=https"),
        ("X-Forwarded-For", "203.0.113.7"),
      ]),
    ),
    "203.0.113.7",
  )
  // An empty X-Forwarded-For entry is an unaddressed hop, not a reason to
  // shift to an earlier client-controlled value.
  assert_eq(
    ip_of(app, Map([("X-Forwarded-For", "203.0.113.7, ")])),
    "10.0.0.9",
  )
}

///|
test "a forwarded node without a port is reported as is" {
  let app = ip_app(1)
  assert_eq(
    ip_of(app, Map([("Forwarded", "for=\"[2001:db8::1]:4711\"")])),
    "[2001:db8::1]",
  )
}

///|
test "the peer address is reported when no proxy recorded an address" {
  let app = ip_app(1)
  assert_eq(ip_of(app, Map([("X-Forwarded-For", "")])), "10.0.0.9")
  assert_eq(ip_of(app, Map([("Forwarded", "proto=https")])), "10.0.0.9")
}

///|
test "trust proxy keeps the forwarded headers readable directly" {
  let app = @feather.App::new()
    .trust_proxy(1)
    .get("/ip", fn(ctx) {
      ctx.text(200, ctx.ip() + "|" + ctx.forwarded_ip())
    })
  let response = app.respond({
    method: "GET",
    path: "/ip",
    headers: Map([("X-Forwarded-For", "203.0.113.7, 198.51.100.4")]),
    body: "",
  })
  // The trusted proxy recorded `198.51.100.4`, while the header as a whole
  // still names `203.0.113.7` as the original client.
  assert_eq(response.body, "198.51.100.4|203.0.113.7")
}

///|
test "the rate limiter groups requests by the trusted client address" {
  let limiter = @feather.RateLimiter::new(max=1, window=60_000L)
  let app = @feather.App::new()
    .trust_proxy(1)
    .use(@feather.middleware_rate_limit(limiter))
    .use(fn(next) {
      fn(ctx) {
        ctx.state.set("remote_addr", "10.0.0.9")
        next(ctx)
      }
    })
    .get("/ip", fn(ctx) { ctx.text(200, "ok") })
  let first = app.respond({
    method: "GET",
    path: "/ip",
    headers: Map([("X-Forwarded-For", "203.0.113.7")]),
    body: "",
  })
  assert_eq(first.status, 200)
  let second = app.respond({
    method: "GET",
    path: "/ip",
    headers: Map([("X-Forwarded-For", "203.0.113.7")]),
    body: "",
  })
  assert_eq(second.status, 429)
  let other = app.respond({
    method: "GET",
    path: "/ip",
    headers: Map([("X-Forwarded-For", "203.0.113.8")]),
    body: "",
  })
  assert_eq(other.status, 200)
}
