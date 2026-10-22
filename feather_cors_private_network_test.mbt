///|
fn private_network_preflight(
  headers : Map[String, String],
) -> @feather.Request {
  {
    method: "OPTIONS",
    path: "/me",
    headers,
    body: "",
  }
}

///|
fn private_network_headers(
  origin : String,
  requested : String,
) -> Map[String, String] {
  Map([
    ("Origin", origin),
    ("Access-Control-Request-Method", "POST"),
    ("Access-Control-Request-Private-Network", requested),
  ])
}

///|
test "cors private network grant is opt-in and conditional on the request" {
  let app = @feather.App::new()
    .use(
      @feather.middleware_cors(
        allow_origin="https://app.example",
        allow_private_network=true,
      ),
    )
    .get("/me", fn(ctx) { ctx.text(200, "ok") })
  let granted = app.respond(
    private_network_preflight(
      private_network_headers("https://app.example", "true"),
    ),
  )
  assert_eq(granted.status, 204)
  assert_eq(
    granted.headers.get("Access-Control-Allow-Origin"),
    Some("https://app.example"),
  )
  assert_eq(
    granted.headers.get("Access-Control-Allow-Private-Network"),
    Some("true"),
  )
  let vary = granted.headers.get("Vary").unwrap_or("")
  assert_true(
    vary.contains("Access-Control-Request-Private-Network"),
    msg=vary,
  )

  let absent_headers = private_network_headers("https://app.example", "true")
  ignore(absent_headers.remove("Access-Control-Request-Private-Network"))
  let absent = app.respond(private_network_preflight(absent_headers))
  assert_eq(absent.status, 204)
  assert_eq(
    absent.headers.get("Access-Control-Allow-Private-Network"),
    None,
  )

  let declined = app.respond(
    private_network_preflight(
      private_network_headers("https://app.example", "false"),
    ),
  )
  assert_eq(declined.status, 204)
  assert_eq(
    declined.headers.get("Access-Control-Allow-Private-Network"),
    None,
  )
}

///|
test "cors private network grant is disabled by default" {
  let app = @feather.App::new()
    .use(@feather.middleware_cors(allow_origin="https://app.example"))
    .get("/me", fn(ctx) { ctx.text(200, "ok") })
  let response = app.respond(
    private_network_preflight(
      private_network_headers("https://app.example", "true"),
    ),
  )
  assert_eq(response.status, 204)
  assert_eq(
    response.headers.get("Access-Control-Allow-Private-Network"),
    None,
  )
  let vary = response.headers.get("Vary").unwrap_or("")
  assert_false(
    vary.contains("Access-Control-Request-Private-Network"),
    msg=vary,
  )
}

///|
test "cors private network grant is withheld from rejected origins" {
  let app = @feather.App::new()
    .use(
      @feather.middleware_cors_allowlist(
        ["https://good.example"],
        allow_private_network=true,
      ),
    )
    .get("/me", fn(ctx) { ctx.text(200, "ok") })
  let response = app.respond(
    private_network_preflight(
      private_network_headers("https://evil.example", "true"),
    ),
  )
  assert_eq(response.status, 204)
  assert_eq(response.headers.get("Access-Control-Allow-Origin"), None)
  assert_eq(
    response.headers.get("Access-Control-Allow-Private-Network"),
    None,
  )
  let vary = response.headers.get("Vary").unwrap_or("")
  assert_true(
    vary.contains("Access-Control-Request-Private-Network"),
    msg=vary,
  )
}

///|
test "cors private network grant is not emitted for ordinary requests" {
  let app = @feather.App::new()
    .use(
      @feather.middleware_cors(
        allow_origin="https://app.example",
        allow_private_network=true,
      ),
    )
    .get("/me", fn(ctx) { ctx.text(200, "ok") })
  let response = app.respond({
    method: "GET",
    path: "/me",
    headers: Map([
      ("Origin", "https://app.example"),
      ("Access-Control-Request-Private-Network", "true"),
    ]),
    body: "",
  })
  assert_eq(response.status, 200)
  assert_eq(
    response.headers.get("Access-Control-Allow-Private-Network"),
    None,
  )
}
