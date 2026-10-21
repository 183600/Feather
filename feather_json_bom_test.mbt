///|
test "json_body ignores a leading UTF-8 BOM" {
  let app = @feather.App::new().post("/echo", fn(ctx) {
    let data = ctx.json_body() catch {
      _ => {
        ctx.text(400, "bad")
        return
      }
    }
    ctx.text(200, data.stringify())
  })
  let response = app.respond({
    method: "POST",
    path: "/echo",
    headers: Map([]),
    body: "\u{FEFF}{\"name\":\"feather\"}",
  })
  assert_eq(response.status, 200)
  assert_eq(response.body, "{\"name\":\"feather\"}")
}

///|
async test "server json_body ignores a leading UTF-8 BOM" {
  let app = @feather.App::new().post("/echo", fn(ctx) {
    let data = ctx.json_body() catch {
      _ => {
        ctx.text(400, "bad")
        return
      }
    }
    ctx.text(200, data.stringify())
  })
  with_server(app, client => {
    let response = client.post("/echo", b"\xef\xbb\xbf{\"ok\":true}")
    assert_eq(response.code, 200)
    assert_eq(client.read_all().text(), "{\"ok\":true}")
  })
}
