///|
async test "bodyless redirects survive an identity refusal" {
  let app = @feather.App::new().get("/go", fn(ctx) {
    ctx.redirect(302, "/next")
  })
  for compress in [false, true] {
    let response = if compress {
      let compressed = @feather.App::new()
        .compress(min_size=0)
        .get("/go", fn(ctx) { ctx.redirect(302, "/next") })
      compressed.respond_async({
        method: "GET",
        path: "/go",
        headers: Map([("Accept-Encoding", "identity;q=0")]),
        body: "",
      })
    } else {
      app.respond_async({
        method: "GET",
        path: "/go",
        headers: Map([("Accept-Encoding", "identity;q=0")]),
        body: "",
      })
    }
    assert_eq(response.status, 302)
    assert_eq(response.headers.get("Location"), Some("/next"))
    assert_eq(response.headers.get("Content-Encoding"), None)
    assert_eq(response.body, "")
    assert_eq(response.data, None)
  }
}
