///|
test "no-store responses still evaluate If-Match" {
  let app = @feather.App::new().post("/item", fn(ctx) {
    ctx.set_header("ETag", "\"v1\"")
    ctx.no_store()
    ctx.text(200, "saved")
  })
  let stale = app.respond({
    method: "POST",
    path: "/item",
    headers: Map([("If-Match", "\"v0\"")]),
    body: "",
  })
  assert_eq(stale.status, 412)
  assert_eq(stale.body, "412 Precondition Failed")
  let current = app.respond({
    method: "POST",
    path: "/item",
    headers: Map([("If-Match", "\"v1\"")]),
    body: "",
  })
  assert_eq(current.status, 200)
  assert_eq(current.body, "saved")
}

///|
test "no-store responses still answer a matching If-None-Match with 304" {
  let app = @feather.App::new().get("/item", fn(ctx) {
    ctx.set_header("ETag", "\"v1\"")
    ctx.no_store()
    ctx.text(200, "value")
  })
  let response = app.respond({
    method: "GET",
    path: "/item",
    headers: Map([("If-None-Match", "\"v1\"")]),
    body: "",
  })
  assert_eq(response.status, 304)
  assert_eq(response.body, "")
  assert_eq(response.headers.get("ETag"), Some("\"v1\""))
  assert_eq(response.headers.get("Cache-Control"), Some("no-store"))
}

///|
test "no-store responses still enforce If-Unmodified-Since" {
  let app = @feather.App::new().put("/item", fn(ctx) {
    ctx.set_header("Last-Modified", "Wed, 21 Oct 2015 07:28:00 GMT")
    ctx.no_store()
    ctx.text(200, "saved")
  })
  let stale = app.respond({
    method: "PUT",
    path: "/item",
    headers: Map([("If-Unmodified-Since", "Tue, 20 Oct 2015 07:28:00 GMT")]),
    body: "",
  })
  assert_eq(stale.status, 412)
  let current = app.respond({
    method: "PUT",
    path: "/item",
    headers: Map([("If-Unmodified-Since", "Thu, 22 Oct 2015 07:28:00 GMT")]),
    body: "",
  })
  assert_eq(current.status, 200)
}
