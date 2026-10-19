///|
/// A small, runnable Feather application showing routing, parameters,
/// middleware, JSON, errors, static files and the async endpoint types
/// (WebSocket, server-sent events and streams). Start it with:
///
///   moon run examples/hello --target native
///
/// then open http://127.0.0.1:8000/.
async fn main {
  let app = @feather.App::new()
    .use(@feather.middleware_recover())
    .use(@feather.middleware_logger())
    .use(@feather.middleware_cors())
    .get("/", fn(ctx) { ctx.text(200, "Hello, Feather!") })
    .get("/hello/:name", fn(ctx) {
      ctx.text(200, "Hello, \{ctx.param("name")}!")
    })
    .get("/api/ping", fn(ctx) { ctx.json(200, { "ok": "true" }) })
    .post("/api/echo", fn(ctx) { ctx.text(200, ctx.request.body) })
    .get("/api/fail", fn(ctx) raise { ctx.fail(400, "bad request") })
    .websocket("/ws/echo", async fn(_ctx, ws) {
      let msg = ws.recv()
      let text = msg.read_all().text()
      ws..start_message(msg.kind)..write(text).end_message()
    })
    .sse("/events", async fn(_ctx, sse) {
      for i = 0; i < 3; i = i + 1 {
        sse.send("tick \{i}")
        @async.sleep(200)
      }
      sse.close()
    })
    .stream("/stream", async fn(_ctx, out) {
      for i = 0; i < 5; i = i + 1 {
        out.write("chunk \{i}\n")
        @async.sleep(200)
      }
    })
    .static_files("/static", "examples/hello/public")
  let addr = @socket.Addr::parse("127.0.0.1:8000")
  println("Feather listening on http://127.0.0.1:8000")
  app.serve(addr)
}
