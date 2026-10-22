///|
fn multipart_isolation_context(body : String) -> @feather.Context {
  @feather.Context::new({
    method: "POST",
    path: "/upload",
    headers: Map([
      ("Content-Type", "multipart/form-data; boundary=IsolationBoundary"),
    ]),
    body,
  })
}

///|
test "mutating multipart results cannot corrupt the parse cache" {
  let body = "--IsolationBoundary\r\n" +
    "Content-Disposition: form-data; name=\"title\"\r\n" +
    "\r\n" +
    "first\r\n" +
    "--IsolationBoundary--\r\n"
  let first = multipart_isolation_context(body)
  let parts = first.multipart()
  assert_eq(parts.length(), 1)
  assert_eq(parts[0].name, "title")
  parts[0].headers.set("X-Mutated", "yes")
  parts.push(parts[0])

  let second = multipart_isolation_context(body)
  let fresh = second.multipart()
  assert_eq(fresh.length(), 1)
  assert_eq(fresh[0].headers.get("X-Mutated"), None)
  assert_eq(second.multipart_value("title"), "first")
}
