///|
fn count_response_header(
  headers : Map[String, String],
  name : String,
) -> Int32 {
  let mut count = 0
  for key, _ in headers {
    if key.view().equal_ignore_ascii_case(name.view()) {
      count = count + 1
    }
  }
  count
}

///|
test "not_modified replaces case-variant validators" {
  let app = @feather.App::new().get("/nm", fn(ctx) {
    ctx.set_header("etag", "\"old\"")
    ctx.set_header("last-modified", "old")
    ctx.not_modified(etag="\"new\"", last_modified="new")
  })
  let response = app.respond({
    method: "GET",
    path: "/nm",
    headers: Map([]),
    body: "",
  })
  assert_eq(response.status, 304)
  assert_eq(count_response_header(response.headers, "etag"), 1)
  assert_eq(count_response_header(response.headers, "last-modified"), 1)
  assert_eq(response.headers.get("ETag"), Some("\"new\""))
  assert_eq(response.headers.get("Last-Modified"), Some("new"))
}
