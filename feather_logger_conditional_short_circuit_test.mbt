///|
async test "logger records the final status of an async middleware short circuit" {
  let lines : Array[String] = []
  let app = @feather.App::new()
    .etag()
    .use(@feather.middleware_logger(
      log=fn(line) { lines.push(line) },
      format=fn(ctx, _millis) { ctx.response.status.to_string() },
    ))
    .use(fn(_next) {
      fn(ctx) raise {
        ctx.set_header("ETag", "\"short-circuit\"")
        ctx.text(200, "plain response")
      }
    })
    .sse("/events", async fn(_ctx, sse) { sse.send("unreachable") })
  with_sse_server(app, client => {
    let first = client.get("/events")
    assert_eq(first.code, 200)
    assert_eq(client.read_all().text(), "plain response")
    let second = client.get(
      "/events",
      extra_headers=Map([
        (
          @http.CaseInsensitiveString("If-None-Match"),
          "\"short-circuit\"",
        ),
      ]),
    )
    assert_eq(second.code, 304)
    assert_eq(client.read_all().text(), "")
    @async.sleep(20)
  })
  assert_eq(lines, ["200", "304"])
}
