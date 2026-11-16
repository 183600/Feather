///|
test "last_event_id reads the reconnect header" {
  let app = @feather.App::new().get("/events", fn(ctx) {
    ctx.text(200, ctx.last_event_id().unwrap_or("none"))
  })
  let response = app.respond({
    method: "GET",
    path: "/events",
    headers: Map([("Last-Event-ID", "evt-42")]),
    body: "",
  })
  assert_eq(response.body, "evt-42")
}

///|
test "last_event_id trims whitespace and ignores empty values" {
  let app = @feather.App::new().get("/events", fn(ctx) {
    match ctx.last_event_id() {
      Some(id) => ctx.text(200, "[\{id}]")
      None => ctx.text(200, "none")
    }
  })
  let padded = app.respond({
    method: "GET",
    path: "/events",
    headers: Map([("Last-Event-ID", "  evt-7 ")]),
    body: "",
  })
  assert_eq(padded.body, "[evt-7]")
  let empty = app.respond({
    method: "GET",
    path: "/events",
    headers: Map([("Last-Event-ID", "   ")]),
    body: "",
  })
  assert_eq(empty.body, "none")
  let absent = app.respond({
    method: "GET",
    path: "/events",
    headers: Map([]),
    body: "",
  })
  assert_eq(absent.body, "none")
}
