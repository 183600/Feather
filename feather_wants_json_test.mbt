///|
fn wants_json_ctx(headers : Map[String, String]) -> Context {
  Context::new({ method: "GET", path: "/", headers, body: "" })
}

///|
test "wants_json is false without an accept header" {
  assert_false(wants_json_ctx(Map([])).wants_json())
  assert_false(wants_json_ctx(Map([("Accept", "  ")])).wants_json())
}

///|
test "wants_json recognizes explicit json types" {
  assert_true(wants_json_ctx(Map([("Accept", "application/json")])).wants_json())
  assert_true(
    wants_json_ctx(
      Map([("Accept", "application/problem+json")]),
    ).wants_json(),
  )
  assert_true(
    wants_json_ctx(Map([("Accept", "Application/JSON")])).wants_json(),
  )
  assert_false(wants_json_ctx(Map([("Accept", "text/html")])).wants_json())
  assert_false(wants_json_ctx(Map([("Accept", "*/*")])).wants_json())
  assert_false(
    wants_json_ctx(Map([("Accept", "application/xml")])).wants_json(),
  )
}

///|
test "wants_json honors quality ordering and rejection" {
  assert_true(
    wants_json_ctx(
      Map([("Accept", "text/html;q=0.5, application/json")]),
    ).wants_json(),
  )
  assert_false(
    wants_json_ctx(
      Map([("Accept", "text/html, application/json;q=0.5")]),
    ).wants_json(),
  )
  assert_false(
    wants_json_ctx(Map([("Accept", "application/json;q=0")])).wants_json(),
  )
}

///|
test "wants_json recognizes ajax requests" {
  assert_true(
    wants_json_ctx(
      Map([("X-Requested-With", "XMLHttpRequest")]),
    ).wants_json(),
  )
  assert_true(
    wants_json_ctx(Map([("X-Requested-With", "xmlhttprequest")])).wants_json(),
  )
  assert_false(
    wants_json_ctx(Map([("X-Requested-With", "fetch")])).wants_json(),
  )
}
