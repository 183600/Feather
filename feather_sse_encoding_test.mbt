///|
async test "sse writes lone surrogate text lossily" {
  let app = @feather.App::new().sse("/events", async fn(_ctx, sse) {
    sse.send("ok" + String::from_array([Char::from_int(0xD800)]))
    sse.comment("note" + String::from_array([Char::from_int(0xDC00)]))
  })
  with_sse_server(app, client => {
    ignore(client.get("/events"))
    assert_eq(
      client.read_all().text(),
      "data: ok\u{FFFD}\n\n: note\u{FFFD}\n",
    )
  })
}
