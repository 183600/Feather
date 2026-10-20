///|
async test "response header values cannot inject additional headers" {
  let app = @feather.App::new().get("/inject", fn(ctx) {
    ctx.set_header("X-Probe", "ok\r\nInjected: yes")
    ctx.text(200, "ok")
  })
  with_server(app, client => {
    let response = client.get("/inject")
    assert_eq(
      response.headers.get(@http.CaseInsensitiveString("Injected")),
      None,
    )
  })
}
