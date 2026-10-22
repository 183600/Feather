///|
fn csrf_safe_request(
  method : String,
  session_id : String,
  token? : String,
) -> @feather.Context {
  let headers : Map[String, String] = Map([
    ("Cookie", "feather_session=" + session_id),
  ])
  match token {
    Some(token) => headers.set("X-CSRF-Token", token)
    None => ()
  }
  @feather.Context::new({ method, path: "/submit", headers, body: "" })
}

///|
fn csrf_safe_session(
  store : @feather.SessionStore,
) -> @feather.Session {
  let session = store.create()
  session.data.set("_csrf", "token-value")
  store.save(session)
  session
}

///|
test "csrf safe_methods empty protects even GET" {
  let store = @feather.SessionStore::new()
  let session = csrf_safe_session(store)
  let handler = @feather.apply_middleware(
    [
      @feather.middleware_session(store),
      @feather.middleware_csrf(safe_methods=[]),
    ],
    fn(ctx) { ctx.text(200, "ok") },
  )
  let rejected = csrf_safe_request("GET", session.id)
  handler(rejected)
  assert_eq(rejected.response.status, 403)
  let accepted = csrf_safe_request("GET", session.id, token="token-value")
  handler(accepted)
  assert_eq(accepted.response.status, 200)
}

///|
test "csrf safe_methods can exempt a non-standard method case-insensitively" {
  let store = @feather.SessionStore::new()
  let session = csrf_safe_session(store)
  let handler = @feather.apply_middleware(
    [
      @feather.middleware_session(store),
      @feather.middleware_csrf(safe_methods=["pOsT"]),
    ],
    fn(ctx) { ctx.text(200, "ok") },
  )
  let post = csrf_safe_request("POST", session.id)
  handler(post)
  assert_eq(post.response.status, 200)
  let delete = csrf_safe_request("DELETE", session.id)
  handler(delete)
  assert_eq(delete.response.status, 403)
}

///|
test "csrf safe_methods replaces the default exemption list" {
  let store = @feather.SessionStore::new()
  let session = csrf_safe_session(store)
  let handler = @feather.apply_middleware(
    [
      @feather.middleware_session(store),
      @feather.middleware_csrf(safe_methods=["GET"]),
    ],
    fn(ctx) { ctx.text(200, "ok") },
  )
  // GET is exempt, but TRACE is no longer part of the default list.
  let get = csrf_safe_request("GET", session.id)
  handler(get)
  assert_eq(get.response.status, 200)
  let trace = csrf_safe_request("TRACE", session.id)
  handler(trace)
  assert_eq(trace.response.status, 403)
  let trace_with_token = csrf_safe_request(
    "TRACE",
    session.id,
    token="token-value",
  )
  handler(trace_with_token)
  assert_eq(trace_with_token.response.status, 200)
}
