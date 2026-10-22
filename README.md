# Feather

Feather is a Gin/Express-style web framework for MoonBit, built on
`moonbitlang/async/http`. It provides routing, middleware, a rich request
context, static files, caching, sessions, SSE, streaming, and WebSocket
endpoints.

The core and HTTP server are implemented and covered by the test suite. The
long-term design notes are in [PLAN.md](PLAN.md).

- Module: `183600/feather`
- Repository: <https://github.com/183600/Feather>
- License: MIT
- Target: the HTTP server requires the **native** target; the library itself
  compiles for the default MoonBit target as well.

## Features

- **Routing** – method routes (`get`/`post`/`put`/`patch`/`delete`/`head`/
  `options`/`all`), `:param` and `*wildcard` segments, route groups, named
  routes and `url_for`, per-route middleware, and a fallback handler.
- **Middleware** – CORS, request logging, panic recovery, request IDs,
  rate limiting, basic and bearer auth, CSRF, secure headers, HTTPS redirect,
  method override, sessions, and a problem-details error handler.
- **Context** – path/query/form/multipart access, typed query/param/form
  helpers (including integers, booleans, and finite floats), JSON bodies, text/HTML/JSON/bytes responses, files and downloads,
  cookies (including signed cookies), flash messages, content negotiation,
  conditional requests (ETag / `If-None-Match` / `If-Modified-Since`), range
  requests, gzip response compression, and cache-control helpers.
- **Async endpoints** – server-sent events (`sse`), streaming responses
  (`stream`), and WebSocket handlers (`websocket`).
- **Server** – keep-alive HTTP/1.1 connections, request timeouts, body-size
  limits, trusted-proxy handling, graceful shutdown/drain, and configurable
  connection limits.
- **Static files** – directory mounts with index files, cache control, range
  requests, and path-traversal protection.

## Install

The module is not yet published to the mooncakes registry, so `moon add
183600/feather` does not work at the moment. Until it is published, consume
the module from a git checkout through a MoonBit workspace.

Declare the dependency in your application's `moon.mod` (version must match
the module's `moon.mod`):

```toml
import {
  "183600/feather@0.1.0",
  "moonbitlang/async@0.22.5",
}
```

Clone the repository next to your project and register both modules as
workspace members:

```bash
git clone https://github.com/183600/Feather.git
moon work init                # creates moon.work, skip if it exists
moon work use ./Feather
moon work use ./path/to/your-app
```

The workspace member satisfies the versioned import locally, so no registry
copy is needed. Then import the package:

```moonbit
import {
  "183600/feather",
  "moonbitlang/async/socket",
}
```

## Quick start

```moonbit
///|
async fn main {
  let app = @feather.App::new()
    .use(@feather.middleware_recover())
    .use(@feather.middleware_logger())
    .get("/", fn(ctx) { ctx.text(200, "Hello, Feather!") })
    .get("/hello/:name", fn(ctx) {
      ctx.json(200, { "hello": ctx.param("name") })
    })

  let addr = @socket.Addr::parse("127.0.0.1:8000")
  app.serve(addr)
}
```

A complete runnable example with routing, middleware, JSON, static files,
WebSocket, SSE, and streaming lives in
[examples/hello](examples/hello):

```bash
./moon run examples/hello --target native
```

## Routing

```moonbit
let app = @feather.App::new()
  .get("/users/:id", fn(ctx) {
    let id = ctx.param_int("id").unwrap_or(-1)
    ctx.json(200, { "id": id.to_string() })
  })
  .get("/files/*path", fn(ctx) {
    ctx.text(200, ctx.param("path"))
  })

// `group` returns a `RouteGroup` (it does not chain back to `App`):
let api = app.group("/api")
ignore(api.get("/health", fn(ctx) { ctx.json(200, { "ok": "true" }) }))
```

Route matching prefers static segments over parameters, and parameters over
wildcards. Named routes support URL generation:

```moonbit
ignore(app.route_named("user", "GET", "/users/:id", handler))
let path = app.url_for("user", params={ "id": "42" })
```

## Middleware

Middleware has the shape `(Handler) -> Handler` and can be installed globally
or on a route/group:

```moonbit
let app = @feather.App::new()
  .use(@feather.middleware_recover())
  .use(@feather.middleware_request_id())
  .use(@feather.middleware_cors(allow_origin="https://example.com"))
  .use(@feather.middleware_secure_headers())
```

CORS can be limited to a fixed set of origins with
`middleware_cors_allowlist`, or decided per request with
`middleware_cors_with`. Both echo the accepted `Origin` and add `Vary: Origin`,
and they still answer preflight requests from rejected origins with `204`
without CORS headers.

Authentication middleware is available for basic credentials
(`middleware_basic_auth` / `middleware_basic_auth_with`) and bearer tokens
(`middleware_bearer_auth` / `middleware_bearer_auth_with`).

Sessions and CSRF are available as middleware plus `Context` helpers
(`session_get`, `session_set`, `session_has`, `session_keys`, `session_remove`,
`session_clear`, `session_destroy`, and JSON/flash variants):

```moonbit
let store = @feather.SessionStore::new()
let app = @feather.App::new()
  .use(@feather.middleware_session(store))
  .use(@feather.middleware_csrf())

ignore(app.post("/login", fn(ctx) {
  ignore(ctx.session_set("user", "alice"))
  ctx.redirect(303, "/")
}))
```

## Responses and conditional requests

`Context` exposes convenience writers (`text`, `html`, `json`, `bytes`,
`file`, `attachment`, `inline`, `no_content`, `problem`), plus header and
cookie helpers:

```moonbit
ignore(app.get("/report", fn(ctx) {
  ctx.cache_public(60)
  ctx.file(200, "reports/latest.pdf")
}))

ignore(app.get("/api/items/:id", fn(ctx) {
  let etag = "\"v1\""
  if ctx.fresh(etag) {
    ctx.not_modified()
  } else {
    ctx.set_header("ETag", etag)
    ctx.json(200, { "id": ctx.param("id") })
  }
}))
```

`cache_public` and `cache_private` accept `immutable=true`; `no_store` and
`no_cache` cover the common non-storable and revalidate-first cases. Cookie
helpers accept `max_age` and an absolute `expires` timestamp in Unix seconds.

`app.compress(min_size=1024)` enables gzip compression for eligible responses.
Handlers can override this per response with `ctx.compress(min_size=0)` to opt
in even when application-wide compression is off, or `ctx.no_compress()` to opt
out. `app.etag()` enables automatic ETag generation for responses that do not
set one.

## Static files

```moonbit
let app = @feather.App::new()
  .static_files("/assets", "public")
  .static_files(
    "/downloads",
    "files",
    cache_control="public, max-age=3600, immutable",
    index="index.html",
  )
```

`static_files_with` additionally takes the route middlewares as its fourth
positional argument (`[]` for none); both accept the same optional `index` /
`max_age` / `precompressed` / `cache_control` flags. Passing `index=""`
disables directory indexes, leaving directory requests to the router (usually
a 404) instead of redirecting them.

Directory traversal outside the mounted root is rejected.

## SSE, streaming, and WebSocket

```moonbit
let app = @feather.App::new()
  .sse("/events", async fn(_ctx, sse) {
    sse.send("tick")
    sse.close()
  })
  .stream("/stream", async fn(_ctx, out) {
    out.write("chunk\n")
  })
  .websocket("/ws/echo", async fn(_ctx, ws) {
    let msg = ws.recv()
    let text = msg.read_all().text()
    ws..start_message(msg.kind)..write(text).end_message()
  })
```

The WebSocket handshake is performed by `moonbitlang/async`; middleware that
needs to add handshake headers (for example a cookie) cannot do so through the
current public API. Use query parameters or a separate authenticated HTTP
endpoint when that is required.

## Server lifecycle

```moonbit
let app = @feather.App::new()
  .max_body_size(8 * 1024 * 1024)
  .request_timeout(30_000)
  .trust_proxy(1)

// Run until the process is stopped.
app.serve(@socket.Addr::parse("0.0.0.0:8080"))

// Or stop accepting new requests and drain:
app.serve_graceful_until(addr, stop=() => { /* resolve on SIGTERM */ })
```

The default body-size limit is deliberately tiny (`DEFAULT_MAX_BODY_SIZE` is
1000 bytes; larger bodies are rejected with `413`), so real applications
should raise it with `max_body_size` as shown above.

## Package layout

The project currently uses a single MoonBit package at the repository root.
Large features are split by file (`feather.mbt`, `server.mbt`, `sse.mbt`,
`stream.mbt`, `compress.mbt`, `session.mbt`, `csrf.mbt`, …) and tests live next
to the code as `*_test.mbt` / `*_wbtest.mbt`. [PLAN.md](PLAN.md) is the
original design note; the implementation has since grown well beyond it.

## Development

Requires the MoonBit toolchain (`~/.moon/bin/moon`, or set `MOON_BIN`). The
repository's `./moon` wrapper never fakes a successful test run; if the
toolchain is missing it exits non-zero.

```bash
./moon check
./moon test                     # default target
./moon check --target native
./moon test --target native     # native-only server/WebSocket paths
./moon run examples/hello --target native
```

CI (`.github/workflows/ci.yml`) runs `./moon check`, the default test suite,
the native test suite, and a repository-hygiene check on every push and pull
request.

`moon.mod` is the single source of truth for module metadata; the old
`moon.mod.json` duplicate has been removed.

## Contributing

- Do not commit throwaway `zz_*`, `tmp_*`, `_scratch_*`, or `dbg_*` test
  files; put temporary probes in `/tmp`.
- Add a regression test for every bug fix and keep existing tests intact.
- Run `./moon check` and `./moon test` before committing.

## License

MIT
