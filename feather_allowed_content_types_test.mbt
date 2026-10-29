///|
fn allowed_content_type_response(
  types : Array[String],
  allow_missing : Bool,
  content_type : String,
  body : String,
) -> @feather.Response {
  let headers : Map[String, String] = Map([])
  if content_type != "" {
    headers.set("Content-Type", content_type)
  }
  @feather.App::new()
    .use(
      @feather.middleware_allowed_content_types(
        types, allow_missing=allow_missing,
      ),
    )
    .post("/upload", fn(ctx) { ctx.text(200, "accepted") })
    .respond({ method: "POST", path: "/upload", headers, body })
}

///|
test "allowed content types accepts exact and parameterized types" {
  let exact = allowed_content_type_response(
    ["application/json"], false, "application/json", "{\"ok\":true}",
  )
  assert_eq(exact.status, 200)
  assert_eq(exact.body, "accepted")

  let parameterized = allowed_content_type_response(
    ["application/json"],
    false,
    "Application/JSON; charset=utf-8",
    "{\"ok\":true}",
  )
  assert_eq(parameterized.status, 200)
  assert_eq(parameterized.body, "accepted")
}

///|
test "allowed content types rejects an unsupported body" {
  let response = allowed_content_type_response(
    ["application/json"], false, "text/plain", "hello",
  )
  assert_eq(response.status, 415)
  assert_eq(response.body, "415 Unsupported Media Type")
  assert_eq(
    response.headers.get("Content-Type"),
    Some("text/plain; charset=utf-8"),
  )
}

///|
test "allowed content types ignores bodyless requests" {
  let no_type = allowed_content_type_response(
    ["application/json"], false, "", "",
  )
  assert_eq(no_type.status, 200)
  assert_eq(no_type.body, "accepted")

  let unrelated_type = allowed_content_type_response(
    ["application/json"], false, "text/plain", "",
  )
  assert_eq(unrelated_type.status, 200)
  assert_eq(unrelated_type.body, "accepted")
}

///|
test "allowed content types rejects a missing type unless allowed" {
  let rejected = allowed_content_type_response(
    ["application/json"], false, "", "{\"ok\":true}",
  )
  assert_eq(rejected.status, 415)

  let accepted = allowed_content_type_response(
    ["application/json"], true, "", "{\"ok\":true}",
  )
  assert_eq(accepted.status, 200)
  assert_eq(accepted.body, "accepted")
}

///|
test "allowed content types supports wildcard patterns" {
  let subtype_wildcard = allowed_content_type_response(
    ["application/*"], false, "application/vnd.api+json", "{}",
  )
  assert_eq(subtype_wildcard.status, 200)

  let wrong_type = allowed_content_type_response(
    ["application/*"], false, "text/plain", "hello",
  )
  assert_eq(wrong_type.status, 415)

  let any_type = allowed_content_type_response(
    ["*/*"], false, "text/plain", "hello",
  )
  assert_eq(any_type.status, 200)

  let star = allowed_content_type_response(["*"], false, "text/plain", "hello")
  assert_eq(star.status, 200)
}

///|
test "allowed content types supports structured suffix patterns" {
  let vendor_json = allowed_content_type_response(
    ["application/*+json"], false, "application/vnd.api+json", "{}",
  )
  assert_eq(vendor_json.status, 200)

  let plain_json = allowed_content_type_response(
    ["application/*+json"], false, "application/json", "{}",
  )
  assert_eq(plain_json.status, 415)

  let wrong_type = allowed_content_type_response(
    ["application/*+json"], false, "text/vnd.api+json", "{}",
  )
  assert_eq(wrong_type.status, 415)
}

///|
test "allowed content types ignores invalid patterns and an empty list" {
  let invalid_only = allowed_content_type_response(
    ["json", "application/"], false, "application/json", "{}",
  )
  assert_eq(invalid_only.status, 415)

  let mixed = allowed_content_type_response(
    ["json", "application/json", "application/"],
    false,
    "application/json",
    "{}",
  )
  assert_eq(mixed.status, 200)

  let empty = allowed_content_type_response([], false, "application/json", "{}")
  assert_eq(empty.status, 415)
}
