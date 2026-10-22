///|
test "signed cookie helpers sign and verify the stored cookie name" {
  let setter = @feather.create_context()
  setter.set_signed_cookie("user id", "alice", "s3cret", path="/")
  let set_cookie = setter.response.headers.get("Set-Cookie").unwrap()
  assert_true(set_cookie.has_prefix("userid="), msg=set_cookie)
  let token = signed_test_cookie_value(set_cookie, "userid")
  let reader = @feather.Context::new({
    method: "GET",
    path: "/",
    headers: Map([("Cookie", "userid=" + token)]),
    body: "",
  })
  assert_eq(reader.signed_cookie("userid", "s3cret"), Some("alice"))
  assert_eq(reader.signed_cookie("user id", "s3cret"), Some("alice"))
  assert_eq(reader.signed_cookie("userid", "wrong-secret"), None)
}
