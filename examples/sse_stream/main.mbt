///|
/// A runnable demo combining server-sent events, a per-client rate limit and
/// static files. Start it with:
///
///   moon run examples/sse_stream --target native
///
/// then open http://127.0.0.1:8000/.
async fn main {
  let limiter = @feather.RateLimiter::new(max=10, window=60_000L)
  let app = @feather.App::new()
    .use(@feather.middleware_recover())
    .use(@feather.middleware_logger())
    .use_prefix("/events", @feather.middleware_rate_limit(limiter))
    .get("/", fn(ctx) { ctx.redirect(302, "/static/") })
    .sse("/events", async fn(_ctx, sse) {
      sse.comment("feather sse demo")
      for i = 0; i < 30; i = i + 1 {
        sse.send("tick \{i}", event="tick", id=i.to_string())
        @async.sleep(1000)
      }
      sse.close()
    })
    .static_files(
      "/static",
      "examples/sse_stream/public",
      cache_control="no-cache",
    )
  let addr = @socket.Addr::parse("127.0.0.1:8000")
  println("Feather SSE demo listening on http://127.0.0.1:8000")
  app.serve(addr)
}
