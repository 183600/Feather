///|
fn connection_request(value : String) -> @http.Request {
  {
    meth: @http.Get,
    path: "/",
    headers: Map([(header_connection, value)]),
  }
}

///|
test "Connection tokens are matched literally, not as wildcards" {
  assert_true(request_wants_close(connection_request("close")))
  assert_true(request_wants_close(connection_request("keep-alive, close")))
  assert_false(request_wants_close(connection_request("*")))
  assert_false(request_wants_close(connection_request("keep-alive")))
}
