///|
test "Context attachment quotes and escapes the file name" {
  let ctx = @feather.create_context()
  ctx.attachment("a\"b\\c.txt")
  assert_eq(
    ctx.response.headers.get("Content-Disposition"),
    Some("attachment; filename=\"a\\\"b\\\\c.txt\""),
  )
}

///|
test "Context attachment encodes non-ascii file names" {
  let ctx = @feather.create_context()
  ctx.attachment("报告.txt")
  assert_eq(
    ctx.response.headers.get("Content-Disposition"),
    Some(
      "attachment; filename=\"__.txt\"; filename*=UTF-8''%E6%8A%A5%E5%91%8A.txt",
    ),
  )
}

///|
test "Context attachment strips control characters from the name" {
  let ctx = @feather.create_context()
  ctx.attachment("evil\r\nX-Injected: yes.txt")
  assert_eq(
    ctx.response.headers.get("Content-Disposition"),
    Some("attachment; filename=\"evilX-Injected: yes.txt\""),
  )
}

///|
test "Context inline keeps the inline disposition" {
  let ctx = @feather.create_context()
  ctx.inline("photo.png")
  assert_eq(
    ctx.response.headers.get("Content-Disposition"),
    Some("inline; filename=\"photo.png\""),
  )
}

///|
test "Context inline encodes non-ascii file names too" {
  let ctx = @feather.create_context()
  ctx.inline("图片.png")
  assert_eq(
    ctx.response.headers.get("Content-Disposition"),
    Some("inline; filename=\"__.png\"; filename*=UTF-8''%E5%9B%BE%E7%89%87.png"),
  )
}

///|
test "Context attachment replaces the file download name" {
  let ctx = @feather.create_context()
  ctx.file(200, "/srv/a.txt", download_name="a.txt")
  ctx.attachment("b.txt")
  assert_eq(
    ctx.response.headers.get("Content-Disposition"),
    Some("attachment; filename=\"b.txt\""),
  )
  assert_eq(ctx.response.status, 200)
  match ctx.file_response() {
    Some(file) => assert_eq(file.path, "/srv/a.txt")
    None => fail("expected the file response to survive attachment")
  }
}

///|
test "attachment reaches the response of a served route" {
  let app = @feather.App::new().get("/export", fn(ctx) {
    ctx.attachment("report.csv")
    ctx.set_header("Content-Type", "text/csv")
    ctx.text(200, "a,b\n")
  })
  let response = app.respond({
    method: "GET",
    path: "/export",
    headers: Map([]),
    body: "",
  })
  assert_eq(response.status, 200)
  assert_eq(
    response.headers.get("Content-Disposition"),
    Some("attachment; filename=\"report.csv\""),
  )
  assert_eq(response.body, "a,b\n")
}

///|
test "attachment set before a file response survives" {
  let ctx = @feather.create_context()
  ctx.attachment("report.csv")
  ctx.file(200, "/srv/report.csv")
  assert_eq(
    ctx.response.headers.get("Content-Disposition"),
    Some("attachment; filename=\"report.csv\""),
  )
}
