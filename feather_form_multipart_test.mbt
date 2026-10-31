///|
fn multipart_form_context() -> @feather.Context {
  @feather.Context::new({
    method: "POST",
    path: "/upload",
    headers: Map([("Content-Type", "multipart/form-data; boundary=sep")]),
    body: "--sep\r\nContent-Disposition: form-data; name=\"name\"\r\n\r\nfeather\r\n--sep\r\nContent-Disposition: form-data; name=\"tag\"\r\n\r\none\r\n--sep\r\nContent-Disposition: form-data; name=\"tag\"\r\n\r\ntwo\r\n--sep\r\nContent-Disposition: form-data; name=\"empty\"\r\n\r\n\r\n--sep\r\nContent-Disposition: form-data; name=\"count\"\r\n\r\n3\r\n--sep\r\nContent-Disposition: form-data; name=\"enabled\"\r\n\r\ntrue\r\n--sep\r\nContent-Disposition: form-data; name=\"ratio\"\r\n\r\n1.25\r\n--sep\r\nContent-Disposition: form-data; name=\"upload\"; filename=\"a.txt\"\r\nContent-Type: text/plain\r\n\r\nfile data\r\n--sep--\r\n",
  })
}

///|
test "form helpers read multipart text fields" {
  let ctx = multipart_form_context()
  assert_eq(ctx.form("name"), "feather")
  assert_eq(ctx.form("tag"), "two")
  assert_eq(ctx.form("empty"), "")
  assert_eq(ctx.form("upload"), "")
  assert_eq(ctx.form("missing"), "")
  assert_eq(ctx.form_default("name", "anon"), "feather")
  assert_eq(ctx.form_default("empty", "-"), "")
  assert_eq(ctx.form_default("missing", "-"), "-")
  assert_eq(ctx.form_values("tag").join("|"), "one|two")
  assert_eq(ctx.form_values("upload").length(), 0)
  assert_eq(ctx.form_values("missing").length(), 0)
  assert_true(ctx.has_form("empty"))
  assert_true(ctx.has_form("tag"))
  assert_false(ctx.has_form("upload"))
  assert_false(ctx.has_form("missing"))
  assert_false(ctx.has_form(""))
}

///|
test "form collection helpers include multipart fields and skip files" {
  let ctx = multipart_form_context()
  let form = ctx.form_map()
  assert_eq(form.get("name"), Some("feather"))
  assert_eq(form.get("tag"), Some("two"))
  assert_eq(form.get("empty"), Some(""))
  assert_false(form.contains("upload"))
  let all = ctx.form_all()
  assert_eq(all.get("tag").unwrap().join("|"), "one|two")
  assert_eq(all.get("name").unwrap().join("|"), "feather")
  assert_false(all.contains("upload"))
  let first = ctx.form_all()
  first.get("tag").unwrap().push("mutated")
  assert_eq(ctx.form_values("tag").join("|"), "one|two")
}

///|
test "form typed accessors parse multipart fields" {
  let ctx = multipart_form_context()
  assert_eq(ctx.form_int("count"), Some(3))
  assert_eq(ctx.form_int64("count"), Some(3L))
  assert_eq(ctx.form_bool("enabled"), Some(true))
  assert_eq(ctx.form_float("ratio"), Some(1.25))
  assert_eq(ctx.form_int("ratio"), None)
  assert_eq(ctx.form_int("missing"), None)
}

///|
test "method override reads the field from a multipart form" {
  let app = @feather.App::new()
    .use(@feather.middleware_method_override())
    .patch("/items/1", fn(ctx) { ctx.text(200, "patched") })
  let response = app.respond({
    method: "POST",
    path: "/items/1",
    headers: Map([
      ("Content-Type", "multipart/form-data; boundary=method"),
    ]),
    body: "--method\r\nContent-Disposition: form-data; name=\"_method\"\r\n\r\nPATCH\r\n--method--\r\n",
  })
  assert_eq(response.status, 200)
  assert_eq(response.body, "patched")
}
