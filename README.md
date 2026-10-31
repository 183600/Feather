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
  `options`/`connect`/`trace`/`all`), `:param` and `*wildcard` segments, route
  groups, named routes and `url_for`, per-route middleware, and a fallback
  handler. `all` covers every standard HTTP method, including `CONNECT` and
  `TRACE`.
- **Middleware** – CORS, request logging, panic recovery, request IDs,
  rate limiting, basic, bearer and HS256 JWT auth, CSRF, secure headers, HTTPS
  redirect, method override, sessions, path- or predicate-scoped installation,
  and a problem-details error handler whose negotiated bodies vary on `Accept`.
- **Context** – path/query/form/multipart access, multi-value `query_all` /
  `form_all` maps and `has_query` / `has_form` / `has_param` presence checks,
  raw `pathname` / `query_string` request-target accessors, typed
  query/param/form helpers (including 32- and 64-bit integers, booleans, and
  finite floats), JSON bodies,
  text bodies decoded with the request's declared charset (UTF-8, Latin-1,
  Windows-1252, ASCII, and UTF-16 LE/BE),
  matched-route identity (`route_pattern` / `route_method` / `route_name`) for
  logging and metrics,
  text/HTML/JSON/bytes responses, files and downloads,
  cookies (including signed cookies), flash messages, content negotiation,
  conditional requests (ETag / `If-None-Match` / `If-Modified-Since`), range
  requests for files and buffered handler responses (`Range` / `If-Range`,
  `206` / `416`), gzip response compression, cache-control helpers, and safe
  `redirect_back` handling.
- **Async endpoints** – server-sent events (`sse`), streaming responses
  (`stream`), and WebSocket handlers (`websocket`).
- **Server** – keep-alive HTTP/1.1 connections, per-route and application-wide
  request timeouts and body-size limits, trusted-proxy handling, graceful
  shutdown/drain, configurable
  connection limits, absolute-form request-target normalization, server-wide
  `OPTIONS *` responses, `HEAD` framing that drops the body while keeping the
  `Content-Length` the matching `GET` would send, `Expect: 100-continue`
  (unsupported expectations are rejected with `417`), and request-body decoding
  for a single `gzip` coding (unsupported or repeated codings are rejected with
  `415`).
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

Clone the repository beside your application, then create or extend a
workspace from the directory that contains both modules:

```bash
git clone https://github.com/183600/Feather.git
moon work init                # creates moon.work; skip if it already exists
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

## Requests and context

Query, form and route values are available through both single-value and
multi-value helpers. `query_values` / `form_values` collect every occurrence of
one name, while `query_all` / `form_all` return the whole collection at once:

```moonbit
ignore(app.get("/search", fn(ctx) {
  // /search?tag=a&tag=b&tag=c
  let tags = ctx.query_all().get("tag").unwrap_or([])
  ctx.text(200, tags.join(", "))
}))
```

`has_query`, `has_form` and `has_param` tell an absent value apart from one
that is present but empty, which matters for flags such as `?preview` or a
wildcard route that captures the empty remainder. `has_param` includes wildcard
captures, and all three keep the same raw/percent-decoded matching as their
lookup counterparts. The multi-value maps and arrays are fresh copies, so a
handler can mutate them without disturbing a later request that carries the
same query or body.

The form helpers (`form`, `form_default`, `form_values`, `form_map`,
`form_all`, `has_form`, and the typed `form_*` accessors) read both
`application/x-www-form-urlencoded` and `multipart/form-data` bodies. Multipart
file parts are skipped, so a field and an upload can share a name without the
upload leaking into the text accessors; use `multipart_file` / `multipart_files`
for the file itself.

`Context::content_type()` returns the request's lowercased media type without
parameters, and `is_json` / `is_form` / `is_multipart` classify common body
types. `Context::content_type_parameter("charset")` reads one parameter,
unquoting values such as multipart boundaries and matching parameter names
case-insensitively.

Request headers can be parsed with `Context::header_int`, `header_int64`,
`header_bool` and `header_float`, which use the same strict parsers as the
query/param/form helpers and ignore surrounding whitespace.

`Context::set_content_type("text/plain", parameters=[("charset", "utf-8")])`
sets a response media type and appends parameters in order, quoting values that
are not bare tokens. It only sets the header, so call it after a body helper
when a custom representation type is wanted.

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

A group can install per-route defaults before registering routes. `timeout`
and `body_limit` apply to every ordinary route added afterwards under the
group prefix, nested groups inherit them, and `route_timeout` /
`route_body_limit` still override an individual route:

```moonbit
let uploads = app.group("/api/uploads").timeout(5_000).body_limit(4_096)
ignore(uploads.post("/image", handler))
```

Route matching prefers static segments over parameters, and parameters over
wildcards. Named routes support URL generation; `url_for` returns `String?`,
or `None` when the name or a required parameter is missing:

```moonbit
ignore(app.route_named("user", "GET", "/users/:id", handler))
let path = app.url_for("user", params={ "id": "42" })
```

`Context::route_name()` reports that registered name from a handler or
middleware, so logs and metrics can group requests by named route.

`app.routes()` lists ordinary `(method, path)` routes, including routes
contributed by mounted applications. `app.endpoints()` returns those routes
plus WebSocket, SSE, streaming and static registrations, each tagged with an
`EndpointKind`, for startup logging or generated API documentation.

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

`middleware_logger` writes one line when the response is known; pass
`with_duration=true` to include elapsed milliseconds, or `skip` with a
predicate to omit health checks and other noisy requests (the handler still
runs). Pass `format` to replace the default line with structured output; its
callback receives the context and elapsed milliseconds, so it can include the
final status, route name, request id, or fields from request state.

`middleware_recover()` converts errors into the framework's default responses.
Use `middleware_recover_with(handler=...)` instead when the application needs
custom rendering, domain-error translation, or extra telemetry: the callback
receives the original error (so it can match `HttpError`,
`HttpErrorPayload`, `HttpProblem`, or its own error type) and owns the
response. `error_status(err)` returns the status carried by framework errors
and `500` otherwise. Request cleanups still run after a custom recovery.

CORS can be limited to a fixed set of origins with
`middleware_cors_allowlist`, or decided per request with
`middleware_cors_with`. Both echo the accepted `Origin` and add `Vary: Origin`,
and they still answer preflight requests from rejected origins with `204`
without CORS headers. When credentials are enabled the preflight's
`Access-Control-Request-Headers` is echoed instead of the literal `*`, which
browsers reject in credentialed requests. Pass `allow_private_network=true` to
answer a browser's Private Network Access preflight with
`Access-Control-Allow-Private-Network: true`; the grant is only sent for an
accepted origin and when the request asks for it.

Authentication middleware is available for basic credentials
(`middleware_basic_auth` / `middleware_basic_auth_with`) and bearer tokens
(`middleware_bearer_auth` / `middleware_bearer_auth_with`).

`middleware_jwt_hs256(secret)` verifies an `Authorization: Bearer` token as a
compact HS256 JWT and stores its claims on the request. It accepts only
`"alg": "HS256"` (so `none` and asymmetric algorithms are rejected), compares
the HMAC in constant time, requires `exp` by default, honors `nbf`, and
supports a `leeway` in seconds for clock skew. Pass `issuer` and/or `audience`
to require the registered claims, with `aud` accepting either a string or an
array of strings. Invalid, expired, not-yet-valid or wrongly scoped tokens
receive a `401` with a `WWW-Authenticate: Bearer realm="..."` challenge
before the handler runs. Handlers read the verified claims with
`Context::jwt_claims`, `Context::jwt_claim`, or `Context::jwt_subject`; the
protected header (for example its `kid`) is available through
`Context::jwt_header` and `Context::jwt_header_parameter`, while outer logging
middleware can read the stable failure category from `Context::jwt_error`
after the middleware returns:

```moonbit
let app = @feather.App::new()
  .use(@feather.middleware_jwt_hs256(secret, realm="Example API"))
  .get("/me", fn(ctx) {
    ctx.json_of(200, { "subject": ctx.jwt_subject() })
  })
```

Use `@feather.verify_jwt_hs256` directly when a handler needs the full
`Jwt` value without middleware. The verifier accepts a `now=` override for
tests and `require_exp=false` for issuers that use another expiry mechanism.
The secret is UTF-8 encoded as-is; use a high-entropy value and keep it out of
source control.

`middleware_secure_headers` installs `nosniff`, frame and referrer policies by
default. It also accepts `hsts`, `content_security_policy`,
`content_security_policy_report_only`, `permissions_policy`, and
`cross_origin_opener_policy` / `cross_origin_embedder_policy` /
`cross_origin_resource_policy`; optional headers are only emitted when
configured, and their names are matched case-insensitively against values
already on the response.

`middleware_request_id` reuses a validated incoming id or mints a
`feather-<n>` value, stores it for `Context::request_id`, and echoes it in the
response. Pass `generate` for UUID/ULID or tracing ids and `max_length` to bound
untrusted input; an empty or over-long generated id falls back to the built-in
counter. `trust_incoming=false` ignores a client-supplied id entirely, which is
the safer choice on a public endpoint where the header is spoofable.

`middleware_allowed_hosts(["example.com", "*.example.com"])` rejects requests
whose `Host` header is not accepted with `400` before the handler runs. Ports
and a trailing root dot are ignored, `*.example.com` accepts subdomains (but
not the apex), and `"*"` accepts any well-formed authority. The check reads
`Host` directly, never forwarded-host headers; pass `allow_missing=true` for
HTTP/1.0 clients that omit it.

`middleware_body_limit` rejects oversized request bodies with `413` before the
handler runs, which is useful for allowing only small payloads on a specific
route while `App::max_body_size` keeps the server-wide bound.

`middleware_allowed_content_types` rejects a non-empty request body whose
media type is not on the allowlist with `415` before the handler runs. Matching
ignores parameters and case, accepts `type/*`, `*/*` and structured suffixes
such as `application/*+json`, and leaves bodyless requests alone. Set
`allow_missing=true` when a non-empty body without `Content-Type` should still
be accepted.

On a server that is exposed directly rather than behind a trusted reverse
proxy, `middleware_strip_forwarded_headers()` removes `Forwarded`,
`X-Forwarded-*` and `X-Real-IP` from the request, so a client cannot spoof
`Context::protocol`, `Context::full_url`, `Context::forwarded_ip` or
`Context::is_secure`. Do not install it behind a proxy whose forwarded values
you need.

`App::use_prefix("/api", middleware)` installs middleware only for a path
segment and everything below it, so authentication, CORS or cache policy can
apply to part of an application without creating a `RouteGroup`. Matching is
segment-aware (`/api` covers `/api` and `/api/users`, not `/apiary`), ignores
the query string, and keeps the installation position relative to `App::use`.
An empty prefix or `"/"` applies application-wide. When a child application is
mounted, its scoped prefixes stay relative to the child, so mounting the same
child at a different parent prefix does not require rewriting its middleware.
`App::use_when(predicate, middleware)` is the general form when the decision
depends on request state or another header rather than the path.

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

`middleware_csrf` exempts `GET`, `HEAD`, `OPTIONS` and `TRACE` by default.
Pass `safe_methods` to replace that list: use `safe_methods=[]` to protect
every method, or list the default methods together with any additional verb to
exempt.

`middleware_csrf_cookie(secret)` provides the same protection without a
session store, using a signed double-submit cookie. Safe requests receive a
random token in a cookie whose value is HMAC-signed with `secret`, and unsafe
requests must echo the token in `X-CSRF-Token`, a URL-encoded form field, or a
multipart field. Handlers read the token with
`Context::csrf_cookie_token()` when rendering a form. Because the cookie is
signed, a sibling subdomain or another cookie-injection path cannot forge a
valid token without the secret. The cookie name, field, header, path,
`same_site`, `secure`, `partitioned`, `max_age`, and `safe_methods` are all
configurable, and `http_only` defaults to `false` so browser scripts can read
the cookie for JSON requests (leave it `true` when only forms need the token).

`middleware_session` also accepts `cookie`, `path`, `domain`, `same_site`,
`http_only`, `secure`, `partitioned`, and `rolling` options; `domain` scopes a
shared session across subdomains. Sessions have a fixed lifetime by default;
`rolling=true` refreshes the server-side deadline and cookie on every request,
and `Context::session_touch()` performs the same refresh from a handler. If a
session's deadline passes while a request is running, that request's write is
discarded and the response expires the cookie instead of handing out a
cookie for a session the store has already dropped. An incoming cookie that
names no live session (unknown or already expired) is expired on the response
as well, even when the handler never touches the session, so clients stop
sending an id the store has dropped.

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

Handlers that serve several representations can let the client choose with
`Context::format`. Offers use the same `Accept` scoring as
`Context::preferred_type`, and their order is the server's preference when
quality values tie:

```moonbit
ignore(app.get("/items/:id", fn(ctx) {
  ctx.format([
    ("text/html", fn(ctx) { ctx.html(200, render_page(ctx.param("id"))) }),
    ("application/json", fn(ctx) { ctx.json(200, { "id": ctx.param("id") }) }),
  ])
}))
```

Format responses carry `Vary: Accept`. A request that rejects every offer gets
`406 Not Acceptable`; pass `fallback=` to render something else instead.

`Context::redirect_back()` returns the browser to the request's `Referer` with
`303 See Other` by default. It never redirects off-site: a same-host absolute
referer contributes only its local path and query, while another host, a
non-HTTP scheme, control characters, or a protocol-relative `//host` target
fall back to `/` (or the `fallback=` value). Pass `status=` to use a different
redirect status after a form submission.

`Context::fresh` also accepts `last_modified=` (an HTTP-date), so handlers that
only track a modification time can answer `If-Modified-Since` with `304`:
`ctx.fresh("", last_modified=stamp)`. As required by RFC 9110, a present
`If-None-Match` takes precedence over the date condition, and date validation
only applies to `GET` and `HEAD`.

A successful `GET` whose body is already buffered (text, JSON, bytes, or a
response produced by middleware) also honors a single `Range` header, just like
file responses: a satisfiable range becomes `206 Partial Content` with
`Content-Range` and the sliced bytes, an unsatisfiable one becomes
`416 Range Not Satisfiable`, and `If-Range` is checked against the response's
`ETag` or `Last-Modified`. Malformed and multi-range requests are answered with
the full representation, which RFC 9110 permits. `HEAD` and non-`GET` requests
ignore `Range`.

`cache_public` and `cache_private` accept `immutable=true`; `no_store` and
`no_cache` cover the common non-storable and revalidate-first cases, while
`Context::cache_control("public, max-age=60, s-maxage=300")` installs an
arbitrary policy (an empty value removes the field). The corresponding
middleware (`middleware_cache_control`, `middleware_no_store`,
`middleware_no_cache`, `middleware_cache_public`, `middleware_cache_private`)
applies a policy after the handler returns and keeps a handler-supplied value
unless `overwrite=true`; combine it with `App::use_prefix` to cache only one
part of an application. Header
helpers (`has_header`, `response_header`, `has_response_header`,
`remove_response_header`, `append_header`, `set_header_if_absent`) match names
case-insensitively; the response helpers are useful in middleware that
inspects or rewrites headers after calling through. Response writer helpers
accept only token header names and strip control characters from values, so a
handler that forwards client input cannot inject an extra response header.
`append_header` joins list-valued fields such as `Vary` and `Link` with a
comma, while `set_header_if_absent` installs a default without clobbering a
handler's value. Cookie helpers accept `max_age` and an absolute `expires`
timestamp in Unix seconds.

`app.compress(min_size=1024)` enables gzip compression for eligible responses,
including static files and `Context::file` downloads with a compressible media
type. Handlers can override this per response with `ctx.compress(min_size=0)` to
opt in even when application-wide compression is off, or `ctx.no_compress()` to
opt out. `app.etag()` enables automatic ETag generation for responses that do not
set one; `ctx.etag()` / `ctx.no_etag()` make the same decision for a single
response, so route middleware can cache just an API subset. The
`middleware_etag()` and `middleware_compress(min_size=0)` wrappers expose the
same decisions as middleware, which pairs naturally with
`App::use_prefix` or `route_with` to cache or compress only one route group.

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
a 404) instead of redirecting them. When an index is configured, a request for
the mount root (`/assets`) or a subdirectory (`/assets/guide`) redirects to its
canonical trailing-slash URL after the file exists, so relative links resolve
correctly; query strings and fragments are preserved.

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

Streaming handlers can set status and headers before the first write, and
`Stream::add_cookie` / `Stream::clear_cookie` add or expire cookies at the same
point; calls made after the response header has been sent are ignored.

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

`request_timeout` is application-wide; `route_timeout("POST", "/slow", 5_000)`
overrides it for one registered route (dynamic patterns such as `/items/:id`
work too, and `0` restores the application default). Route timeouts cover body
reads and ordinary handler responses; SSE, streaming and WebSocket endpoints
remain exempt.

Likewise, `max_body_size` is application-wide and
`route_body_limit("POST", "/upload", 4_096)` overrides it for one registered
route. The override also bounds the decoded representation of a gzip-coded
body, and `0` restores the application default. Asynchronous endpoints keep
using the application-wide limit.

The default body-size limit is deliberately tiny (`DEFAULT_MAX_BODY_SIZE` is
1000 bytes; larger bodies are rejected with `413`), so real applications
should raise it with `max_body_size` as shown above. A request body declaring
one `gzip` (or `x-gzip`) content coding is decoded before that limit is
applied, so a small compressed payload cannot expand past it. Unknown, repeated
or otherwise undecodable content codings are rejected with
`415 Unsupported Media Type` instead of being handed to handlers as if they
were the representation.

## Package layout

The project currently uses a single MoonBit package at the repository root.
Large features are split by responsibility across same-package files (routing,
context, middleware, static files, server connection handling, …) and tests
live next to the code as `*_test.mbt` / `*_wbtest.mbt`. [PLAN.md](PLAN.md) is
the original design note; the implementation has since grown well beyond it.

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

CI (`.github/workflows/ci.yml`) runs `./moon check` and
`./moon check --target native`, the default and native test suites, and a
repository-hygiene check on every push to `main` and every pull request.

`moon.mod` is the single source of truth for module metadata; the old
`moon.mod.json` duplicate has been removed.

## Contributing

- Do not commit throwaway `zz_*`, `tmp_*`, `_scratch_*`, or `dbg_*` test
  files; put temporary probes in `/tmp`.
- Add a regression test for every bug fix and keep existing tests intact.
- Run `./moon check` and `./moon test` before committing.

## License

MIT
