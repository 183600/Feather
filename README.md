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
  rate limiting, basic auth, CSRF, secure headers, HTTPS redirect, method
  override, sessions, and a problem-details error handler.
- **Context** – path/query/form/multipart access, typed query and param
  helpers, JSON bodies, text/HTML/JSON/bytes responses, files and downloads,
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

Add the module to your project (or add it manually to `moon.mod`):

```bash
moon add 183600/feather
```

Import the package:

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
    let id = ctx.param_int("id")
    ctx.json(200, { "id": id })
  })
  .get("/files/*path", fn(ctx) {
    ctx.text(200, ctx.param("path"))
  })
  .group("/api", fn(group) {
    group.get("/health", fn(ctx) { ctx.json(200, { "ok": "true" }) })
  })
```

Route matching prefers static segments over parameters, and parameters over
wildcards. Named routes support URL generation:

```moonbit
app.route_named("user", "GET", "/users/:id", handler)
let path = app.url_for("user", { "id": "42" })
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

Sessions and CSRF are available as middleware plus `Context` helpers:

```moonbit
let store = @feather.SessionStore::new()
let app = @feather.App::new()
  .use(@feather.middleware_session(store))
  .use(@feather.middleware_csrf())

app.post("/login", fn(ctx) {
  ctx.session_set("user", "alice")
  ctx.redirect(303, "/")
})
```

## Responses and conditional requests

`Context` exposes convenience writers (`text`, `html`, `json`, `bytes`,
`file`, `attachment`, `inline`, `no_content`, `problem`), plus header and
cookie helpers:

```moonbit
app.get("/report", fn(ctx) {
  ctx.cache_public(60)
  ctx.file("reports/latest.pdf")
})

app.get("/api/items/:id", fn(ctx) {
  let etag = "\"v1\""
  if ctx.fresh(etag=etag) {
    ctx.not_modified()
  } else {
    ctx.set_header("ETag", etag)
    ctx.json(200, { "id": ctx.param("id") })
  }
})
```

`cache_public` and `cache_private` accept `immutable=true`; `no_store` and
`no_cache` cover the common non-storable and revalidate-first cases.

`app.compress(min_size=1024)` enables gzip compression for eligible responses.
`app.etag()` enables automatic ETag generation for responses that do not set
one.

## Static files

```moonbit
let app = @feather.App::new()
  .static_files("/assets", "public")
  .static_files_with(
    "/downloads",
    "files",
    cache_control="public, max-age=3600",
    index="index.html",
  )
```

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
app.serve_graceful_until(addr, stop=async fn { /* resolve on SIGTERM */ })
```

## Package layout

The project currently uses a single MoonBit package at the repository root.
Large features are split by file (`feather.mbt`, `server.mbt`, `sse.mbt`,
`stream.mbt`, `compress.mbt`, `session.mbt`, `csrf.mbt`, …) and tests live next
to the code as `*_test.mbt` / `*_wbtest.mbt`. See [PLAN.md](PLAN.md) for the
proposed multi-package layout.

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
