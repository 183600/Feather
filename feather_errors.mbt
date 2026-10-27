///|
/// Media type of an RFC 7807 problem-details document.
pub const PROBLEM_CONTENT_TYPE : String = "application/problem+json; charset=utf-8"

///|
/// Render an RFC 7807 problem-details document as JSON.
///
/// An empty `type_name` becomes `about:blank` and an empty `title` becomes the
/// status text, so callers only pass the fields they actually have. `detail`
/// and `instance` are omitted when empty, as the RFC allows.
pub fn build_problem_document(
  status : Int32,
  type_name : String,
  title : String,
  detail : String,
  instance : String,
) -> String {
  let body : Map[String, Json] = Map([], capacity=5)
  let kind = if type_name == "" { "about:blank" } else { type_name }
  let heading = if title == "" { status_text(status) } else { title }
  body.set("type", Json::string(kind))
  body.set("title", Json::string(heading))
  body.set("status", Json::number(status.to_double()))
  if detail != "" {
    body.set("detail", Json::string(detail))
  }
  if instance != "" {
    body.set("instance", Json::string(instance))
  }
  Json::object(body).stringify()
}

///|
/// Write an RFC 7807 problem-details response onto `ctx`.
///
/// Unlike the negotiated error helpers this always answers with
/// `application/problem+json`, because the handler asked for problem details
/// explicitly.
pub fn problem_response(
  ctx : Context,
  status : Int32,
  type_name : String,
  title : String,
  detail : String,
  instance : String,
) -> Unit {
  ctx.file = None
  ctx.response.status = status
  clear_replaced_body_headers(ctx.response.headers)
  clear_replaced_representation_headers(ctx.response.headers)
  set_header_ignore_case(
    ctx.response.headers,
    "Content-Type",
    PROBLEM_CONTENT_TYPE,
  )
  ctx.response.data = None
  ctx.response.body = build_problem_document(
    status, type_name, title, detail, instance,
  )
}

///|
/// Give `ctx` a problem-details body for `status`, keeping the negotiated
/// rendering used by every default error path: clients that ask for
/// `application/problem+json` get problem details, everyone else keeps the
/// plain rendering passed in `plain_body`.
fn negotiated_error_body(
  ctx : Context,
  status : Int32,
  plain_content_type : String,
  plain_body : String,
  plain_detail : String,
) -> Unit {
  clear_replaced_body_headers(ctx.response.headers)
  clear_replaced_representation_headers(ctx.response.headers)
  // The rendering below is chosen from `Accept`, so the response must not be
  // reused for a request with different preferences.
  ctx.vary("Accept")
  if ctx.wants_problem_details() {
    set_header_ignore_case(
      ctx.response.headers,
      "Content-Type",
      PROBLEM_CONTENT_TYPE,
    )
    ctx.response.data = None
    ctx.response.body = build_problem_document(
      status,
      "",
      status_text(status),
      plain_detail,
      "",
    )
  } else {
    set_header_ignore_case(
      ctx.response.headers,
      "Content-Type",
      plain_content_type,
    )
    ctx.response.data = None
    ctx.response.body = plain_body
  }
}

///|
pub fn not_found(ctx : Context) -> Unit {
  ctx.file = None
  ctx.response.status = 404
  negotiated_error_body(
    ctx, 404, "text/plain; charset=utf-8", "404 Not Found", "",
  )
}

///|
fn method_not_allowed_with_allow(ctx : Context, allow : String) -> Unit {
  ctx.file = None
  ctx.response.status = 405
  set_header_ignore_case(ctx.response.headers, "Allow", allow)
  negotiated_error_body(
    ctx, 405, "text/plain; charset=utf-8", "405 Method Not Allowed", "",
  )
}

///|
pub fn method_not_allowed(ctx : Context, allowed : Array[String]) -> Unit {
  method_not_allowed_with_allow(ctx, allow_header_value(allowed))
}

///|
fn respond_options_with_allow(ctx : Context, allow : String) -> Unit {
  ctx.file = None
  ctx.response.status = 204
  clear_replaced_body_headers(ctx.response.headers)
  clear_replaced_representation_headers(ctx.response.headers)
  // A 204 carries no representation, so a content type prepared for an
  // earlier response must not leak into the automatic OPTIONS answer.
  ignore(remove_header_ignore_case(ctx.response.headers, "Content-Type"))
  set_header_ignore_case(ctx.response.headers, "Allow", allow)
  ctx.response.data = None
  ctx.response.body = ""
}

///|
/// Answer an `OPTIONS` request for a path that exists under other methods with
/// `204 No Content` and an `Allow` header, without running any handler.
pub fn respond_options(ctx : Context, allowed : Array[String]) -> Unit {
  respond_options_with_allow(ctx, allow_header_value(allowed))
}

///|
/// Answer with the generic 500 body. `detail` is only recorded in request
/// state for logs and middleware; it is never sent to the client, in either
/// the plain or the problem-details rendering.
pub fn internal_error(ctx : Context, detail : String) -> Unit {
  ctx.file = None
  ctx.state.set("error", detail)
  ctx.response.status = 500
  negotiated_error_body(
    ctx, 500, "text/plain; charset=utf-8", "Internal Server Error", "",
  )
}

///|
let error_body_cache : Map[Int32, Map[String, String]] = Map([])

///|
/// Recency ticks for the cached error bodies, keyed by status and message.
let error_body_cache_ages : Map[Int32, Map[String, Int32]] = Map([])

///|
/// Cache of the problem-details rendering of the same errors, kept apart from
/// the plain bodies so one variant can never be served for the other.
let problem_body_cache : Map[Int32, Map[String, String]] = Map([])

///|
let problem_body_cache_ages : Map[Int32, Map[String, Int32]] = Map([])

///|
/// Look up `status`/`message` in `cache`, building and storing the body on a
/// miss. Bodies are dropped once the per-status map grows past eight entries
/// and the whole cache past 32 statuses; `build` renders on demand either way.
fn error_body_from_cache(
  cache : Map[Int32, Map[String, String]],
  ages_by_status : Map[Int32, Map[String, Int32]],
  status : Int32,
  message : String,
  build : () -> String,
) -> String {
  let by_message = match cache.get(status) {
    Some(by_message) => by_message
    None => {
      if cache.length() >= 32 {
        cache.clear()
        ages_by_status.clear()
      }
      let by_message : Map[String, String] = Map([], capacity=4)
      cache.set(status, by_message)
      by_message
    }
  }
  let ages = match ages_by_status.get(status) {
    Some(ages) => ages
    None => {
      let ages : Map[String, Int32] = Map([], capacity=4)
      ages_by_status.set(status, ages)
      ages
    }
  }
  match by_message.get(message) {
    Some(body) => {
      cache_touch(ages, message)
      body
    }
    None => {
      let body = build()
      if message.length() <= 128 {
        cache_set(by_message, ages, 8, message, body)
      }
      body
    }
  }
}

///|
fn cached_error_body(status : Int32, message : String) -> String {
  error_body_from_cache(
    error_body_cache,
    error_body_cache_ages,
    status,
    message,
    fn() {
      let payload : Map[String, Json] = Map([], capacity=2)
      payload.set("status", Json::number(status.to_double()))
      payload.set("error", Json::string(message))
      Json::object(payload).stringify()
    },
  )
}

///|
/// The cached problem-details rendering of `error_response` for a client that
/// prefers `application/problem+json`.
fn cached_problem_body(status : Int32, message : String) -> String {
  error_body_from_cache(
    problem_body_cache,
    problem_body_cache_ages,
    status,
    message,
    fn() {
      build_problem_document(status, "", status_text(status), message, "")
    },
  )
}

///|
pub fn error_response(ctx : Context, status : Int32, message : String) -> Unit {
  ctx.file = None
  ctx.response.status = status
  clear_replaced_body_headers(ctx.response.headers)
  clear_replaced_representation_headers(ctx.response.headers)
  ctx.vary("Accept")
  if ctx.wants_problem_details() {
    set_header_ignore_case(
      ctx.response.headers,
      "Content-Type",
      PROBLEM_CONTENT_TYPE,
    )
    ctx.response.data = None
    ctx.response.body = cached_problem_body(status, message)
  } else {
    set_header_ignore_case(
      ctx.response.headers,
      "Content-Type",
      "application/json; charset=utf-8",
    )
    ctx.response.data = None
    ctx.response.body = cached_error_body(status, message)
  }
}

///|
pub fn error_response_with_payload(
  ctx : Context,
  status : Int32,
  message : String,
  payload : Json,
) -> Unit {
  ctx.file = None
  ctx.vary("Accept")
  let problem = ctx.wants_problem_details()
  let body : Map[String, Json] = Map([], capacity=5)
  if problem {
    body.set("type", Json::string("about:blank"))
    body.set("title", Json::string(status_text(status)))
    body.set("status", Json::number(status.to_double()))
    body.set("detail", Json::string(message))
  } else {
    body.set("status", Json::number(status.to_double()))
    body.set("error", Json::string(message))
  }
  match payload {
    Json::Object(extra) =>
      for key, value in extra {
        if problem &&
          (
            key == "type" ||
            key == "title" ||
            key == "status" ||
            key == "detail" ||
            key == "instance"
          ) {
          continue
        }
        body.set(key, value)
      }
    _ =>
      // RFC 7807 requires `detail` to be a string. In problem mode it already
      // carries the error message, so keep non-object payloads in an extension
      // member instead of replacing it with arbitrary JSON.
      if problem {
        body.set("payload", payload)
      } else {
        body.set("detail", payload)
      }
  }
  ctx.response.status = status
  clear_replaced_body_headers(ctx.response.headers)
  clear_replaced_representation_headers(ctx.response.headers)
  if problem {
    set_header_ignore_case(
      ctx.response.headers,
      "Content-Type",
      PROBLEM_CONTENT_TYPE,
    )
  } else {
    set_header_ignore_case(
      ctx.response.headers,
      "Content-Type",
      "application/json; charset=utf-8",
    )
  }
  ctx.response.data = None
  ctx.response.body = Json::object(body).stringify()
}

///|
pub fn Context::fail(
  self : Context,
  status : Int32,
  message : String,
) -> Unit raise HttpError {
  ignore(self)
  raise HttpError(status, message)
}

///|
pub fn Context::fail_with(
  self : Context,
  status : Int32,
  message : String,
  payload : Json,
) -> Unit raise HttpErrorPayload {
  ignore(self)
  raise HttpErrorPayload(status, message, payload)
}

///|
/// Write an RFC 7807 problem-details response directly from a handler.
///
/// `title` defaults to the status text, `type_name` to `about:blank`; pass
/// `detail` for the human-readable explanation and `instance` for the URI of
/// the specific occurrence.
pub fn Context::problem(
  self : Context,
  status : Int32,
  detail : String,
  title~ : String = "",
  type_name~ : String = "",
  instance~ : String = "",
) -> Unit {
  problem_response(self, status, type_name, title, detail, instance)
}

///|
/// Raise an RFC 7807 problem detail. Every dispatch path renders it as an
/// `application/problem+json` body, so it works from handlers, route
/// middleware and mounted applications alike.
pub fn Context::fail_problem(
  self : Context,
  status : Int32,
  detail : String,
  title~ : String = "",
  type_name~ : String = "",
  instance~ : String = "",
) -> Unit raise HttpProblem {
  ignore(self)
  raise HttpProblem(status, type_name, title, detail, instance)
}

