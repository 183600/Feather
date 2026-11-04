///|
/// An application that sees every request as coming from `address`.
fn ip_filter_app(
  address : String,
  middleware : @feather.Middleware,
) -> @feather.App {
  @feather.App::new()
    .use(fn(next) {
      fn(ctx) raise {
        ctx.state.set("remote_addr", address)
        next(ctx)
      }
    })
    .use(middleware)
    .get("/", fn(ctx) { ctx.text(200, "ok") })
}

///|
test "ip filter rejects a client outside the allowed block" {
  let app = ip_filter_app(
    "198.51.100.7",
    @feather.middleware_ip_filter(allow=["192.0.2.0/24"]),
  )
  let response = app.respond({
    method: "GET",
    path: "/",
    headers: Map([]),
    body: "",
  })
  assert_eq(response.status, 403)
  assert_eq(response.body, "403 Forbidden")
}

///|
test "ip filter accepts a client inside the allowed block" {
  let app = ip_filter_app(
    "192.0.2.7",
    @feather.middleware_ip_filter(allow=["192.0.2.0/24"]),
  )
  let response = app.respond({
    method: "GET",
    path: "/",
    headers: Map([]),
    body: "",
  })
  assert_eq(response.status, 200)
  assert_eq(response.body, "ok")
}

///|
test "ip filter accepts an exactly listed address" {
  let app = ip_filter_app(
    "192.0.2.7",
    @feather.middleware_ip_filter(allow=["192.0.2.7"]),
  )
  let response = app.respond({
    method: "GET",
    path: "/",
    headers: Map([]),
    body: "",
  })
  assert_eq(response.status, 200)
}

///|
test "ip filter accepts a client in a second allowed block" {
  let app = ip_filter_app(
    "203.0.113.9",
    @feather.middleware_ip_filter(allow=["192.0.2.0/24", "203.0.113.0/24"]),
  )
  let response = app.respond({
    method: "GET",
    path: "/",
    headers: Map([]),
    body: "",
  })
  assert_eq(response.status, 200)
}

///|
test "ip filter denies a listed address" {
  let app = ip_filter_app(
    "203.0.113.9",
    @feather.middleware_ip_filter(deny=["203.0.113.9"]),
  )
  let response = app.respond({
    method: "GET",
    path: "/",
    headers: Map([]),
    body: "",
  })
  assert_eq(response.status, 403)
}

///|
test "ip filter lets an address that is not denied through" {
  let app = ip_filter_app(
    "203.0.113.10",
    @feather.middleware_ip_filter(deny=["203.0.113.9"]),
  )
  let response = app.respond({
    method: "GET",
    path: "/",
    headers: Map([]),
    body: "",
  })
  assert_eq(response.status, 200)
}

///|
test "ip filter denies an address even when it is allowed as well" {
  let app = ip_filter_app(
    "203.0.113.9",
    @feather.middleware_ip_filter(
      allow=["203.0.113.0/24"],
      deny=["203.0.113.9"],
    ),
  )
  let response = app.respond({
    method: "GET",
    path: "/",
    headers: Map([]),
    body: "",
  })
  assert_eq(response.status, 403)
}

///|
test "ip filter rejects every request with an empty allowlist" {
  let app = ip_filter_app(
    "192.0.2.7",
    @feather.middleware_ip_filter(allow=[]),
  )
  let response = app.respond({
    method: "GET",
    path: "/",
    headers: Map([]),
    body: "",
  })
  assert_eq(response.status, 403)
}

///|
test "ip filter rejects every request when every allowlist entry is invalid" {
  let app = ip_filter_app(
    "192.0.2.7",
    @feather.middleware_ip_filter(allow=["not-an-address", "192.0.2.0/33"]),
  )
  let response = app.respond({
    method: "GET",
    path: "/",
    headers: Map([]),
    body: "",
  })
  assert_eq(response.status, 403)
}

///|
test "ip filter ignores an invalid denylist entry" {
  let app = ip_filter_app(
    "192.0.2.7",
    @feather.middleware_ip_filter(deny=["not-an-address"]),
  )
  let response = app.respond({
    method: "GET",
    path: "/",
    headers: Map([]),
    body: "",
  })
  assert_eq(response.status, 200)
}

///|
test "ip filter matches IPv6 addresses" {
  let app = ip_filter_app(
    "2001:db8::1",
    @feather.middleware_ip_filter(allow=["2001:db8::/32"]),
  )
  let response = app.respond({
    method: "GET",
    path: "/",
    headers: Map([]),
    body: "",
  })
  assert_eq(response.status, 200)
}

///|
test "ip filter rejects an IPv6 address outside the allowed block" {
  let app = ip_filter_app(
    "2001:db9::1",
    @feather.middleware_ip_filter(allow=["2001:db8::/32"]),
  )
  let response = app.respond({
    method: "GET",
    path: "/",
    headers: Map([]),
    body: "",
  })
  assert_eq(response.status, 403)
}

///|
test "ip filter matches a bracketed IPv6 peer address" {
  let app = ip_filter_app(
    "[2001:db8::1]",
    @feather.middleware_ip_filter(allow=["2001:db8::1"]),
  )
  let response = app.respond({
    method: "GET",
    path: "/",
    headers: Map([]),
    body: "",
  })
  assert_eq(response.status, 200)
}

///|
test "ip filter matches an IPv4-mapped IPv6 address" {
  let app = ip_filter_app(
    "::ffff:192.0.2.7",
    @feather.middleware_ip_filter(allow=["192.0.2.7"]),
  )
  let response = app.respond({
    method: "GET",
    path: "/",
    headers: Map([]),
    body: "",
  })
  assert_eq(response.status, 200)
}

///|
test "ip filter does not match an IPv4 client against an IPv6 rule" {
  let app = ip_filter_app(
    "192.0.2.7",
    @feather.middleware_ip_filter(allow=["2001:db8::/32"]),
  )
  let response = app.respond({
    method: "GET",
    path: "/",
    headers: Map([]),
    body: "",
  })
  assert_eq(response.status, 403)
}

///|
test "ip filter does not match an IPv6 client against an IPv4 rule" {
  let app = ip_filter_app(
    "2001:db8::1",
    @feather.middleware_ip_filter(allow=["192.0.2.0/24"]),
  )
  let response = app.respond({
    method: "GET",
    path: "/",
    headers: Map([]),
    body: "",
  })
  assert_eq(response.status, 403)
}

///|
test "ip filter ignores the forwarded headers of an untrusted client" {
  let app = ip_filter_app(
    "198.51.100.7",
    @feather.middleware_ip_filter(allow=["192.0.2.0/24"]),
  )
  let response = app.respond({
    method: "GET",
    path: "/",
    headers: Map([("X-Forwarded-For", "192.0.2.7")]),
    body: "",
  })
  assert_eq(response.status, 403)
}

///|
test "ip filter uses the forwarded address of a trusted proxy" {
  let app = ip_filter_app(
    "198.51.100.7",
    @feather.middleware_ip_filter(allow=["192.0.2.0/24"]),
  ).trust_proxy(1)
  let response = app.respond({
    method: "GET",
    path: "/",
    headers: Map([("X-Forwarded-For", "192.0.2.7")]),
    body: "",
  })
  assert_eq(response.status, 200)
}

///|
test "ip filter strips the port of an IPv4 peer address" {
  let app = ip_filter_app(
    "192.0.2.7:54321",
    @feather.middleware_ip_filter(allow=["192.0.2.0/24"]),
  )
  let response = app.respond({
    method: "GET",
    path: "/",
    headers: Map([]),
    body: "",
  })
  assert_eq(response.status, 200)
}

///|
test "ip filter rejects a client whose address cannot be parsed" {
  let app = ip_filter_app(
    "not-an-address",
    @feather.middleware_ip_filter(allow=["192.0.2.0/24"]),
  )
  let response = app.respond({
    method: "GET",
    path: "/",
    headers: Map([]),
    body: "",
  })
  assert_eq(response.status, 403)
}

///|
test "ip filter lets a client through when no rule is configured" {
  let app = ip_filter_app(
    "198.51.100.7",
    @feather.middleware_ip_filter(),
  )
  let response = app.respond({
    method: "GET",
    path: "/",
    headers: Map([]),
    body: "",
  })
  assert_eq(response.status, 200)
}

///|
test "ip filter matches a whole IPv4 network block" {
  let app = ip_filter_app(
    "192.0.2.7",
    @feather.middleware_ip_filter(allow=["192.0.2.0/24"]),
  )
  let response = app.respond({
    method: "GET",
    path: "/",
    headers: Map([]),
    body: "",
  })
  assert_eq(response.status, 200)
  let outside = ip_filter_app(
    "192.0.3.7",
    @feather.middleware_ip_filter(allow=["192.0.2.0/24"]),
  ).respond({
    method: "GET",
    path: "/",
    headers: Map([]),
    body: "",
  })
  assert_eq(outside.status, 403)
}

///|
test "ip filter matches the whole address space of a block" {
  let app = ip_filter_app(
    "192.0.2.7",
    @feather.middleware_ip_filter(allow=["0.0.0.0/0"]),
  )
  let response = app.respond({
    method: "GET",
    path: "/",
    headers: Map([]),
    body: "",
  })
  assert_eq(response.status, 200)
}

///|
test "ip filter matches an IPv4 /16 block" {
  let app = ip_filter_app(
    "192.0.2.7",
    @feather.middleware_ip_filter(allow=["192.0.0.0/16"]),
  )
  let response = app.respond({
    method: "GET",
    path: "/",
    headers: Map([]),
    body: "",
  })
  assert_eq(response.status, 200)
}

///|
test "ip filter matches an IPv4 /32 block" {
  let app = ip_filter_app(
    "192.0.2.7",
    @feather.middleware_ip_filter(allow=["192.0.2.7/32"]),
  )
  let response = app.respond({
    method: "GET",
    path: "/",
    headers: Map([]),
    body: "",
  })
  assert_eq(response.status, 200)
}

///|
test "ip filter matches an IPv6 /64 block" {
  let app = ip_filter_app(
    "2001:db8:1:2::1",
    @feather.middleware_ip_filter(allow=["2001:db8:1:2::/64"]),
  )
  let response = app.respond({
    method: "GET",
    path: "/",
    headers: Map([]),
    body: "",
  })
  assert_eq(response.status, 200)
}

///|
test "ip filter ignores whitespace around a rule" {
  let app = ip_filter_app(
    "192.0.2.7",
    @feather.middleware_ip_filter(allow=[" 192.0.2.0/24 "]),
  )
  let response = app.respond({
    method: "GET",
    path: "/",
    headers: Map([]),
    body: "",
  })
  assert_eq(response.status, 200)
}

///|
async test "ip filter rejects a client on the server" {
  let app = @feather.App::new()
    .use(@feather.middleware_ip_filter(allow=["192.0.2.0/24"]))
    .get("/", fn(ctx) { ctx.text(200, "ok") })
  with_server(app, client => {
    let response = client.get("/")
    assert_eq(response.code, 403)
    ignore(client.read_all())
  })
}
