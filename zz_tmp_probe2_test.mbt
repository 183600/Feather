///|
test "zz allow probe" {
  let app = @feather.App::new()
    .get("/r", fn(ctx) { ctx.text(200, "g") })
    .put("/r", fn(ctx) { ctx.text(200, "p") })
  let response = app.respond({
    method: "DELETE",
    path: "/r",
    headers: Map([]),
    body: "",
  })
  println(response.headers.get("Allow").to_string())
}
