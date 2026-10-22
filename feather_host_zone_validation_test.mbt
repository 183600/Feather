///|
fn host_zone_ctx(value : String) -> @feather.Context {
  @feather.Context::new({
    method: "GET",
    path: "/",
    headers: Map([("Host", value)]),
    body: "",
  })
}

///|
test "ipv6 zone identifiers keep valid escapes and unreserved characters" {
  for value in [
    "[fe80::1%25eth0]",
    "[fe80::1%eth0]",
    "[fe80::1%25eth~0]",
    "[::1%25%32%35]",
  ] {
    assert_eq(host_zone_ctx(value).host(), value, msg=value)
  }
}

///|
test "ipv6 zone identifiers reject incomplete or stray escapes" {
  for value in [
    "[::1%%]",
    "[::1%25%]",
    "[::1%25%2]",
    "[::1%25eth0:1]",
    "[::1%25eth 0]",
  ] {
    assert_eq(host_zone_ctx(value).host(), "", msg=value)
  }
}
