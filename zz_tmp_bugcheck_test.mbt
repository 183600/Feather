///|
test "tmp precondition cache sees changed map value" {
  let app = @feather.App::new()
    .etag()
    .get("/x", fn(ctx) { ctx.text(200, "hello") })
  let headers : Map[String, String] = Map([("If-None-Match", "\"nope\"")])
  let request : @feather.Request = {
    method: "GET",
    path: "/x",
    headers,
    body: "",
  }
  let first = app.respond(request)
  assert_eq(first.status, 200)
  let etag = first.headers.get("ETag").unwrap()
  headers.set("If-None-Match", etag)
  let second = app.respond(request)
  assert_eq(second.status, 304)
}

///|
test "tmp json text order matches json_object stringify" {
  let data : Map[String, String] = Map([
    ("alpha", "1"),
    ("beta", "2"),
    ("gamma", "3"),
    ("delta", "4"),
  ])
  let ctx = @feather.Context::new({
    method: "GET",
    path: "/",
    headers: Map([]),
    body: "",
  })
  ctx.json(200, data)
  assert_eq(ctx.response.body, @feather.json_object(data).stringify())
}
