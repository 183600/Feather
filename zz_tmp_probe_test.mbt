///|
test "tmp probe allow" {
  let app = @feather.App::new().get("/r", fn(ctx) { ctx.text(200, "g") }).put("/r", fn(ctx) { ctx.text(200, "p") })
  let response = app.respond({ method: "DELETE", path: "/r", headers: Map([]), body: "" })
  println("headers Allow=\{response.headers.get("Allow")}")
}
