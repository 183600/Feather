///|
async test "server json_body rejects malformed UTF-8 instead of replacing it" {
  let app = @feather.App::new().post("/json", fn(ctx) {
    let data = ctx.json_body() catch {
      @feather.HttpError(status, _) => {
        ctx.text(status, "invalid")
        return
      }
      _ => {
        ctx.text(500, "unexpected")
        return
      }
    }
    ctx.text(200, data.stringify())
  })
  with_server(app, client => {
    let malformed = client.post(
      "/json",
      b"{\"x\":\"\xff\"}",
      extra_headers=Map([
        (
          @http.CaseInsensitiveString("Content-Type"),
          "application/json",
        ),
      ]),
    )
    assert_eq(malformed.code, 400)
    assert_eq(client.read_all().text(), "invalid")
    let valid = client.post(
      "/json",
      b"{\"x\":\"ok\"}",
      extra_headers=Map([
        (
          @http.CaseInsensitiveString("Content-Type"),
          "application/json",
        ),
      ]),
    )
    assert_eq(valid.code, 200)
    assert_eq(client.read_all().text(), "{\"x\":\"ok\"}")
  })
}

///|
test "offline json_body still accepts a text body with a BOM" {
  let ctx = @feather.Context::new({
    method: "POST",
    path: "/json",
    headers: Map([("Content-Type", "application/json")]),
    body: "\u{FEFF}{\"ok\":true}",
  })
  let data = ctx.json_body() catch {
    _ => fail("valid JSON with a BOM must parse")
  }
  assert_eq(data.stringify(), "{\"ok\":true}")
}
