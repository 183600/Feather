///|
pub(all) enum ByteRange {
  ByteRangeFull
  ByteRangeSpec(Int64, Int64)
  ByteRangeInvalid
}

///|
fn etag_header_matches(value : StringView, etag : String) -> Bool {
  let etag_view = etag.view()
  let etag_opaque = if etag_view.has_prefix("W/") {
    etag_view[2:]
  } else {
    etag_view
  }
  let length = value.length()
  let mut start = 0
  let mut i = 0
  let mut in_quotes = false
  while i <= length {
    if i == length || (value.unsafe_get(i) == (',' : UInt16) && !in_quotes) {
      let token = trim_ascii_space(value[start:i])
      if token == "*" {
        return true
      }
      let token_opaque = if token.has_prefix("W/") { token[2:] } else { token }
      if !token_opaque.is_empty() && token_opaque == etag_opaque {
        return true
      }
      start = i + 1
    } else if value.unsafe_get(i) == ('"' : UInt16) {
      in_quotes = !in_quotes
    }
    i = i + 1
  }
  false
}

///|
/// Whether an `If-Match` field value satisfies the strong comparison function
/// (RFC 9110 §13.1.1) against `etag`. The wildcard `*` matches any existing
/// representation; weak tags never match, because `If-Match` requires strong
/// comparison.
fn if_match_header_matches(value : StringView, etag : String) -> Bool {
  let length = value.length()
  let etag_view = etag.view()
  let etag_is_strong = etag != "" && !etag_view.has_prefix("W/")
  let mut start = 0
  let mut i = 0
  let mut in_quotes = false
  while i <= length {
    if i == length || (value.unsafe_get(i) == (',' : UInt16) && !in_quotes) {
      let token = trim_ascii_space(value[start:i])
      if token == "*" {
        return true
      }
      if etag_is_strong && !token.has_prefix("W/") && token == etag_view {
        return true
      }
      start = i + 1
    } else if value.unsafe_get(i) == ('"' : UInt16) {
      in_quotes = !in_quotes
    }
    i = i + 1
  }
  false
}

///|
/// Whether the `If-Unmodified-Since` condition holds for a representation last
/// modified at `mtime_secs`. An invalid date or an unknown modification date
/// is ignored, as is the condition for a modification exactly at the given
/// second, matching the one-second granularity of HTTP dates. The epoch is a
/// real validator, so `None` (not `0`) marks an unknown modification date.
fn if_unmodified_since_ok(value : StringView, mtime_secs : Int64?) -> Bool {
  match mtime_secs {
    None => true
    Some(mtime_secs) =>
      match parse_http_date_view(trim_ascii_space(value)) {
        Some(since) => mtime_secs <= since
        None => true
      }
  }
}

///|
/// Result of evaluating a request's precondition headers against the selected
/// representation's validators.
priv enum PreconditionOutcome {
  PreconditionPass
  PreconditionNotModified
  PreconditionFailed
}

///|
/// The four precondition request headers `evaluate_preconditions_input`
/// consults, shared by the server and the offline `App::respond` path.
priv struct PreconditionInput {
  if_match : String?
  if_none_match : String?
  if_modified_since : String?
  if_unmodified_since : String?
}

///|
fn precondition_input_from_http(request : @http.Request) -> PreconditionInput {
  {
    if_match: request.headers.get(header_if_match),
    if_none_match: request.headers.get(header_if_none_match),
    if_modified_since: request.headers.get(header_if_modified_since),
    if_unmodified_since: request.headers.get(header_if_unmodified_since),
  }
}

///|
/// The four precondition header names, resolved once.
let precondition_if_match_name : StringView = "If-Match".view()

///|
let precondition_if_none_match_name : StringView = "If-None-Match".view()

///|
let precondition_if_modified_since_name : StringView = "If-Modified-Since".view()

///|
let precondition_if_unmodified_since_name : StringView = "If-Unmodified-Since".view()

///|
/// Collect the precondition request headers from the map.
///
/// The map is mutable and can be changed in place without its length changing,
/// so the result is not cached.
fn precondition_input_from_map(
  headers : Map[String, String],
) -> PreconditionInput {
  if headers.is_empty() {
    return {
      if_match: None,
      if_none_match: None,
      if_modified_since: None,
      if_unmodified_since: None,
    }
  }
  let mut if_match : String? = None
  let mut if_none_match : String? = None
  let mut if_modified_since : String? = None
  let mut if_unmodified_since : String? = None
  headers.each(fn(key, value) {
    let key_view = key.view()
    let length = key_view.length()
    if length == 8 || length == 13 || length == 17 || length == 19 {
      let first = key_view.unsafe_get(0)
      if first == ('I' : UInt16) || first == ('i' : UInt16) {
        if length == 8 {
          if if_match is None &&
            key_view.equal_ignore_ascii_case(precondition_if_match_name) {
            if_match = Some(value)
          }
        } else if length == 13 {
          if if_none_match is None &&
            key_view.equal_ignore_ascii_case(precondition_if_none_match_name) {
            if_none_match = Some(value)
          }
        } else if length == 17 {
          if if_modified_since is None &&
            key_view.equal_ignore_ascii_case(
              precondition_if_modified_since_name,
            ) {
            if_modified_since = Some(value)
          }
        } else if if_unmodified_since is None &&
          key_view.equal_ignore_ascii_case(
            precondition_if_unmodified_since_name,
          ) {
          if_unmodified_since = Some(value)
        }
      }
    }
  })
  { if_match, if_none_match, if_modified_since, if_unmodified_since, }
}

///|
/// Evaluate `If-Match`, `If-Unmodified-Since`, `If-None-Match` and
/// `If-Modified-Since` in the order required by RFC 9110 §13.2.2.
///
/// `etag` and `mtime_secs` describe the selected representation; either may be
/// absent (empty tag / `0`). `allows_not_modified` is true for `GET`/`HEAD`,
/// the only methods that `304 Not Modified` may be sent for.
fn evaluate_preconditions_input(
  input : PreconditionInput,
  etag : String,
  mtime_secs : Int64?,
  allows_not_modified : Bool,
) -> PreconditionOutcome {
  match input.if_match {
    Some(value) =>
      if !if_match_header_matches(value.view(), etag) {
        return PreconditionFailed
      }
    None =>
      match input.if_unmodified_since {
        Some(value) =>
          if !if_unmodified_since_ok(value.view(), mtime_secs) {
            return PreconditionFailed
          }
        None => ()
      }
  }
  match input.if_none_match {
    Some(value) =>
      if etag_header_matches(value.view(), etag) {
        if allows_not_modified {
          return PreconditionNotModified
        } else {
          return PreconditionFailed
        }
      }
    None =>
      if allows_not_modified {
        match input.if_modified_since {
          Some(value) =>
            match mtime_secs {
              Some(mtime_secs) =>
                match parse_http_date_view(trim_ascii_space(value.view())) {
                  Some(since) =>
                    if mtime_secs <= since {
                      return PreconditionNotModified
                    }
                  None => ()
                }
              None => ()
            }
          None => ()
        }
      }
  }
  PreconditionPass
}

///|
/// Drop a satisfied `If-Match` (and the `If-Unmodified-Since` it suppresses)
/// before a transformation weakens the response validator.
///
/// Compression turns a strong handler ETag into a weak one. Re-evaluating the
/// original strong comparison after that would fail a request whose `If-Match`
/// matched the representation when it was selected. File responses run after
/// the dynamic pipeline's pre-compression check, so they apply this directly.
fn drop_satisfied_if_match(
  input : PreconditionInput,
  etag : String,
) -> PreconditionInput {
  match input.if_match {
    Some(value) =>
      if if_match_header_matches(value.view(), etag) {
        {
          if_match: None,
          if_none_match: input.if_none_match,
          if_modified_since: input.if_modified_since,
          if_unmodified_since: None,
        }
      } else {
        input
      }
    None => input
  }
}

///|
/// Request-state keys remembering the validators that made the last
/// `Context::fresh` call report the representation as fresh.
const FRESH_ETAG_STATE_KEY : String = "__feather_fresh_etag"
const FRESH_LAST_MODIFIED_STATE_KEY : String = "__feather_fresh_last_modified"

///|
fn Context::remember_fresh_validators(
  self : Context,
  etag : String,
  last_modified : String?,
) -> Unit {
  if etag != "" {
    self.state.set(FRESH_ETAG_STATE_KEY, etag)
  }
  match last_modified {
    Some(value) => if value != "" {
      self.state.set(FRESH_LAST_MODIFIED_STATE_KEY, value)
    }
    None => ()
  }
}

///|
/// Whether the request's conditional headers report that the representation
/// described by `etag` and/or `last_modified` is still fresh.
///
/// A present `If-None-Match` is evaluated first and takes precedence over
/// `If-Modified-Since`, as RFC 9110 requires. Both conditions only apply to
/// `GET` and `HEAD`, the methods for which a `304` is defined; on any other
/// method this returns `false` so a handler cannot accidentally answer a
/// conditional `POST`/`PUT` with `304`. Pass `last_modified` (an HTTP-date such
/// as the value returned by `format_http_date`) to also answer date-only
/// `If-Modified-Since` requests. Returns `false` when neither validator matches
/// or both are absent/invalid.
///
/// When the answer is `true`, the validators are remembered so a following
/// `Context::not_modified()` without arguments can repeat the same `ETag` and
/// `Last-Modified` that the matching `200` response would carry.
pub fn Context::fresh(
  self : Context,
  etag : String,
  last_modified? : String,
) -> Bool {
  ignore(self.state.remove(FRESH_ETAG_STATE_KEY))
  ignore(self.state.remove(FRESH_LAST_MODIFIED_STATE_KEY))
  let http_method = normalize_method(self.request.method)
  let allows_not_modified = http_method == "GET" || http_method == "HEAD"
  let none_match = self.header("If-None-Match")
  // Presence matters, not just a non-empty value: an empty or malformed
  // `If-None-Match` field still takes precedence over `If-Modified-Since`
  // (RFC 9110 §13.1.3), so it must not fall through to the date condition.
  // A `304` is only valid for a retrieval, so an unsafe method never reports
  // the representation as fresh even when the tag matches.
  if self.has_header("If-None-Match") {
    if !allows_not_modified {
      return false
    }
    // A present but non-matching tag must not fall back to the date
    // condition. Without a representation ETag only the wildcard can match:
    // `*` names any existing representation, so it stays true even when the
    // caller does not have a validator to pass.
    let matched = if etag == "" {
      etag_header_matches(none_match.view(), "")
    } else {
      etag_header_matches(none_match.view(), etag)
    }
    if matched {
      self.remember_fresh_validators(etag, last_modified)
    }
    return matched
  }
  // A date validator only makes sense for the safe retrieval methods.
  if !allows_not_modified {
    return false
  }
  let modified = match last_modified {
    Some(value) =>
      match parse_http_date_view(trim_ascii_space(value.view())) {
        Some(seconds) => Some(seconds)
        None => None
      }
    None => None
  }
  let since = match modified {
    Some(_) =>
      match parse_http_date_view(
        trim_ascii_space(self.header("If-Modified-Since").view()),
      ) {
        Some(seconds) => Some(seconds)
        None => None
      }
    None => None
  }
  let matched = match (modified, since) {
    (Some(modified), Some(since)) => modified <= since
    _ => false
  }
  if matched {
    self.remember_fresh_validators(etag, last_modified)
  }
  matched
}

///|
pub fn Context::not_modified(
  self : Context,
  etag? : String,
  last_modified? : String,
) -> Unit {
  self.file = None
  self.response.status = 304
  self.response.body = ""
  self.response.data = None
  ignore(remove_header_ignore_case(self.response.headers, "Content-Type"))
  ignore(remove_header_ignore_case(self.response.headers, "Content-Length"))
  ignore(remove_header_ignore_case(self.response.headers, "Content-Range"))
  ignore(remove_header_ignore_case(self.response.headers, "Content-Disposition"))
  let resolved_etag = match etag {
    Some(value) => Some(value)
    None => self.state.get(FRESH_ETAG_STATE_KEY)
  }
  let resolved_last_modified = match last_modified {
    Some(value) => Some(value)
    None => self.state.get(FRESH_LAST_MODIFIED_STATE_KEY)
  }
  match resolved_etag {
    Some(etag) => set_header_ignore_case(self.response.headers, "ETag", etag)
    None => ()
  }
  match resolved_last_modified {
    Some(last_modified) =>
      set_header_ignore_case(
        self.response.headers,
        "Last-Modified",
        last_modified,
      )
    None => ()
  }
}

