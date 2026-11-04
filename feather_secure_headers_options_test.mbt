///|
fn secure_headers_app(middleware : @feather.Middleware) -> @feather.App {
  @feather.App::new()
    .use(middleware)
    .get("/", fn(ctx) { ctx.text(200, "ok") })
}

///|
fn secure_headers_response(app : @feather.App) -> @feather.Response {
  app.respond({
    method: "GET",
    path: "/",
    headers: Map([]),
    body: "",
  })
}

///|
test "secure headers emit modern policy headers when configured" {
  let app = secure_headers_app(
    @feather.middleware_secure_headers(
      content_security_policy="default-src 'self'",
      content_security_policy_report_only="script-src 'self' 'report-sample'",
      permissions_policy="geolocation=(), camera=()",
      cross_origin_opener_policy="same-origin",
      cross_origin_embedder_policy="require-corp",
      cross_origin_resource_policy="same-site",
    ),
  )
  let response = secure_headers_response(app)
  assert_eq(
    response.headers.get("Content-Security-Policy"),
    Some("default-src 'self'"),
  )
  assert_eq(
    response.headers.get("Content-Security-Policy-Report-Only"),
    Some("script-src 'self' 'report-sample'"),
  )
  assert_eq(
    response.headers.get("Permissions-Policy"),
    Some("geolocation=(), camera=()"),
  )
  assert_eq(
    response.headers.get("Cross-Origin-Opener-Policy"),
    Some("same-origin"),
  )
  assert_eq(
    response.headers.get("Cross-Origin-Embedder-Policy"),
    Some("require-corp"),
  )
  assert_eq(
    response.headers.get("Cross-Origin-Resource-Policy"),
    Some("same-site"),
  )
}

///|
test "secure headers leave optional modern policy headers unset" {
  let response = secure_headers_response(
    secure_headers_app(@feather.middleware_secure_headers()),
  )
  assert_eq(
    response.headers.get("Content-Security-Policy-Report-Only"),
    None,
  )
  assert_eq(response.headers.get("Permissions-Policy"), None)
  assert_eq(response.headers.get("Cross-Origin-Opener-Policy"), None)
  assert_eq(response.headers.get("Cross-Origin-Embedder-Policy"), None)
  assert_eq(response.headers.get("Cross-Origin-Resource-Policy"), None)
}

///|
test "secure headers replace case-variant modern policy headers" {
  let app = @feather.App::new()
    .use(fn(next) {
      fn(ctx) raise {
        ctx.set_header("permissions-policy", "camera=*")
        ctx.set_header("cross-origin-opener-policy", "unsafe-none")
        next(ctx)
      }
    })
    .use(
      @feather.middleware_secure_headers(
        permissions_policy="camera=()",
        cross_origin_opener_policy="same-origin",
      ),
    )
    .get("/", fn(ctx) { ctx.text(200, "ok") })
  let response = secure_headers_response(app)
  let mut permissions = 0
  let mut opener = 0
  for key, _ in response.headers {
    if key.view().equal_ignore_ascii_case("permissions-policy".view()) {
      permissions = permissions + 1
    }
    if key.view().equal_ignore_ascii_case("cross-origin-opener-policy".view()) {
      opener = opener + 1
    }
  }
  assert_eq(permissions, 1)
  assert_eq(opener, 1)
  assert_eq(response.headers.get("Permissions-Policy"), Some("camera=()"))
  assert_eq(
    response.headers.get("Cross-Origin-Opener-Policy"),
    Some("same-origin"),
  )
}

///|
test "secure headers emit the remaining hardening headers when configured" {
  let app = secure_headers_app(
    @feather.middleware_secure_headers(
      dns_prefetch_control="off",
      download_options="noopen",
      permitted_cross_domain_policies="none",
      origin_agent_cluster="?1",
      xss_protection="0",
    ),
  )
  let response = secure_headers_response(app)
  assert_eq(response.headers.get("X-DNS-Prefetch-Control"), Some("off"))
  assert_eq(response.headers.get("X-Download-Options"), Some("noopen"))
  assert_eq(
    response.headers.get("X-Permitted-Cross-Domain-Policies"),
    Some("none"),
  )
  assert_eq(response.headers.get("Origin-Agent-Cluster"), Some("?1"))
  assert_eq(response.headers.get("X-XSS-Protection"), Some("0"))
}

///|
test "secure headers leave the remaining hardening headers unset" {
  let response = secure_headers_response(
    secure_headers_app(@feather.middleware_secure_headers()),
  )
  assert_eq(response.headers.get("X-DNS-Prefetch-Control"), None)
  assert_eq(response.headers.get("X-Download-Options"), None)
  assert_eq(response.headers.get("X-Permitted-Cross-Domain-Policies"), None)
  assert_eq(response.headers.get("Origin-Agent-Cluster"), None)
  assert_eq(response.headers.get("X-XSS-Protection"), None)
}

///|
test "secure headers replace case-variant hardening headers" {
  let app = @feather.App::new()
    .use(fn(next) {
      fn(ctx) raise {
        ctx.set_header("x-dns-prefetch-control", "on")
        ctx.set_header("origin-agent-cluster", "?0")
        next(ctx)
      }
    })
    .use(
      @feather.middleware_secure_headers(
        dns_prefetch_control="off",
        origin_agent_cluster="?1",
      ),
    )
    .get("/", fn(ctx) { ctx.text(200, "ok") })
  let response = secure_headers_response(app)
  let mut prefetch = 0
  let mut cluster = 0
  for key, _ in response.headers {
    if key.view().equal_ignore_ascii_case("x-dns-prefetch-control".view()) {
      prefetch = prefetch + 1
    }
    if key.view().equal_ignore_ascii_case("origin-agent-cluster".view()) {
      cluster = cluster + 1
    }
  }
  assert_eq(prefetch, 1)
  assert_eq(cluster, 1)
  assert_eq(response.headers.get("X-DNS-Prefetch-Control"), Some("off"))
  assert_eq(response.headers.get("Origin-Agent-Cluster"), Some("?1"))
}

///|
test "secure headers stay on responses produced by an inner recovery" {
  let app = @feather.App::new()
    .use(@feather.middleware_secure_headers(cross_origin_resource_policy="same-origin"))
    .use(@feather.middleware_recover())
    .get("/", fn(_ctx) { raise @feather.HttpError(500, "boom") })
  let response = secure_headers_response(app)
  assert_eq(response.status, 500)
  assert_eq(
    response.headers.get("Cross-Origin-Resource-Policy"),
    Some("same-origin"),
  )
  assert_eq(response.headers.get("X-Content-Type-Options"), Some("nosniff"))
}

///|
async test "secure headers apply to static file responses" {
  let dir = @fs.tmpdir(prefix="feather-secure-headers-static")
  @fs.write_file(dir + "/asset.txt", "asset")
  let app = @feather.App::new()
    .use(
      @feather.middleware_secure_headers(
        cross_origin_resource_policy="same-origin",
      ),
    )
    .static_files("/assets", dir)
  with_server(app, client => {
    let response = client.get("/assets/asset.txt")
    assert_eq(response.code, 200)
    assert_eq(
      response.headers.get(
        @http.CaseInsensitiveString("Cross-Origin-Resource-Policy"),
      ),
      Some("same-origin"),
    )
    assert_eq(
      response.headers.get(@http.CaseInsensitiveString("X-Frame-Options")),
      Some("DENY"),
    )
    assert_eq(client.read_all().text(), "asset")
  })
  @fs.rmdir(dir, recursive=true)
}

