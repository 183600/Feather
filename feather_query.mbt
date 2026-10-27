///|
/// Estimated capacity for a url-encoded result map, based on the source length.
fn urlencoded_capacity(source : StringView) -> Int32 {
  let estimate = source.length() >> 3
  if estimate < 4 {
    4
  } else if estimate > 256 {
    256
  } else {
    estimate
  }
}

///|
fn parse_urlencoded_view(source : StringView) -> Map[String, String] {
  let result : Map[String, String] = Map(
    [],
    capacity=urlencoded_capacity(source),
  )
  let length = source.length()
  let mut pos = 0
  while pos <= length {
    let mut end = pos
    let mut eq = -1
    let mut key_escaped = false
    let mut value_escaped = false
    while end < length {
      let code = source.unsafe_get(end)
      if code == ('&' : UInt16) {
        break
      }
      if code == ('=' : UInt16) {
        if eq < 0 {
          eq = end
        }
      } else if code == ('%' : UInt16) || code == ('+' : UInt16) {
        if eq < 0 {
          key_escaped = true
        } else {
          value_escaped = true
        }
      }
      end = end + 1
    }
    if end > pos {
      if eq >= 0 {
        let key = if key_escaped {
          decode_url(source[pos:eq])
        } else {
          source[pos:eq].to_owned()
        }
        let value = if value_escaped {
          decode_url(source[eq + 1:end])
        } else {
          source[eq + 1:end].to_owned()
        }
        result.set(key, value)
      } else {
        let key = if key_escaped {
          decode_url(source[pos:end])
        } else {
          source[pos:end].to_owned()
        }
        result.set(key, "")
      }
    }
    if end >= length {
      break
    }
    pos = end + 1
  }
  result
}

///|
/// Most recently parsed url-encoded text and the owned map it produced.
/// Callers always receive a copy so the cached parse cannot be mutated.
let last_parsed_urlencoded_source : Ref[String?] = Ref(None)

///|
let last_parsed_urlencoded_map : Ref[Map[String, String]?] = Ref(None)

///|
let last_parsed_urlencoded_valid : Ref[Bool] = Ref(false)

///|
pub fn parse_urlencoded(source : String) -> Map[String, String] {
  match last_parsed_urlencoded_source.val {
    Some(cached) =>
      if last_parsed_urlencoded_valid.val &&
        (physical_equal(cached, source) || cached == source) {
        match last_parsed_urlencoded_map.val {
          Some(map) => return map.copy()
          None => ()
        }
      }
    None => ()
  }
  let parsed = parse_urlencoded_view(source)
  if source.length() <= PARSE_CACHE_MAX_KEY {
    last_parsed_urlencoded_source.val = Some(source)
    last_parsed_urlencoded_map.val = Some(parsed.copy())
    last_parsed_urlencoded_valid.val = true
  }
  parsed
}

///|
/// Parse a url-encoded source into every value of each key, preserving the
/// order in which the pairs appear.
fn parse_urlencoded_multi(source : StringView) -> Map[String, Array[String]] {
  let result : Map[String, Array[String]] = Map(
    [],
    capacity=urlencoded_capacity(source),
  )
  // Decoded spelling of keys that contain `%` or `+`. Keys without either
  // character keep their raw spelling.
  let escaped_keys : Map[StringView, String] = Map([], capacity=4)
  let length = source.length()
  let mut pos = 0
  while pos <= length {
    let mut end = pos
    let mut eq = -1
    let mut key_escaped = false
    let mut value_escaped = false
    while end < length {
      let code = source.unsafe_get(end)
      if code == ('&' : UInt16) {
        break
      }
      if code == ('=' : UInt16) {
        if eq < 0 {
          eq = end
        }
      } else if code == ('%' : UInt16) || code == ('+' : UInt16) {
        if eq < 0 {
          key_escaped = true
        } else {
          value_escaped = true
        }
      }
      end = end + 1
    }
    if end > pos {
      let raw_key = if eq >= 0 { source[pos:eq] } else { source[pos:end] }
      let value = if eq >= 0 {
        if value_escaped {
          decode_url(source[eq + 1:end])
        } else {
          source[eq + 1:end].to_owned()
        }
      } else {
        ""
      }
      // A key with neither `%` nor `+` uses its raw spelling; escaped keys are
      // decoded before the lookup, since the map stores decoded spellings.
      if !key_escaped {
        match result.get_from_string(raw_key) {
          Some(values) => values.push(value)
          None => result.set(raw_key.to_owned(), [value])
        }
      } else {
        let key = match escaped_keys.get(raw_key) {
          Some(key) => key
          None => {
            let key = decode_url(raw_key)
            escaped_keys.set(raw_key, key)
            key
          }
        }
        match result.get(key) {
          Some(values) => values.push(value)
          None => result.set(key, [value])
        }
      }
    }
    if end >= length {
      break
    }
    pos = end + 1
  }
  result
}

///|
fn query_key_matches(
  source : StringView,
  start : Int32,
  end : Int32,
  name : StringView,
) -> Bool {
  let name_length = name.length()
  if end - start == name_length {
    let mut i = start
    let mut j = 0
    let mut equal = true
    while j < name_length {
      if source.unsafe_get(i) != name.unsafe_get(j) {
        equal = false
        break
      }
      i = i + 1
      j = j + 1
    }
    if equal {
      return true
    }
  }
  let key = source[start:end]
  if !name_needs_raw(key) {
    return false
  }
  name.equal_to_string(decode_url(key))
}

///|
/// Whether a parameter name contains a character (`%` or `+`) whose spelling
/// changes between the raw key text and the decoded key. Names without one can
/// be looked up in the parsed map directly; names with one must also be
/// compared against the raw key text, which is what `query_param_opt` does.
fn name_needs_raw(name : StringView) -> Bool {
  let length = name.length()
  let mut i = 0
  while i < length {
    let code = name.unsafe_get(i)
    if code == ('%' : UInt16) || code == ('+' : UInt16) {
      return true
    }
    i = i + 1
  }
  false
}

///|
/// Find the value of `name` in the raw query or form source, comparing each
/// key against both its raw and its decoded spelling. The last matching pair
/// wins, mirroring `parse_urlencoded_view`. Returns `None` when no pair
/// carries the parameter.
fn query_param_opt(source : StringView, name : String) -> String? {
  let name_view = name.view()
  let mut found : StringView? = None
  let length = source.length()
  let mut pos = 0
  while pos < length {
    let pair_start = pos
    let mut eq = -1
    let mut end = pos
    while end < length {
      let code = source.unsafe_get(end)
      if code == ('&' : UInt16) {
        break
      }
      if code == ('=' : UInt16) && eq < 0 {
        eq = end
      }
      end = end + 1
    }
    if end > pair_start {
      let key_end = if eq >= 0 { eq } else { end }
      if query_key_matches(source, pair_start, key_end, name_view) {
        if eq >= 0 {
          found = Some(source[eq + 1:end])
        } else {
          found = Some("")
        }
      }
    }
    pos = end + 1
  }
  match found {
    Some(value) => Some(decode_url(value))
    None => None
  }
}

///|
fn query_param(source : StringView, name : String) -> String {
  match query_param_opt(source, name) {
    Some(value) => value
    None => ""
  }
}

///|
pub fn Context::query(self : Context, name : String) -> String {
  let path = self.request.path
  match path_query_index(path) {
    Some(index) =>
      if name_needs_raw(name.view()) {
        query_param(query_source_view(path, index), name)
      } else {
        match query_map_lookup(path, index).get(name) {
          Some(value) => value
          None => ""
        }
      }
    None => ""
  }
}

///|
/// Look up the query parameter `name`, returning `default` when the query
/// string does not carry the parameter. Name matching follows `Context::query`,
/// so names containing `%` or `+` also match the raw key spelling. Unlike
/// `Context::query`, a parameter that is present with an empty value is
/// returned as-is instead of being replaced by `default`.
pub fn Context::query_default(
  self : Context,
  name : String,
  default : String,
) -> String {
  match path_query_index(self.request.path) {
    Some(index) =>
      if name_needs_raw(name.view()) {
        match query_param_opt(
          query_source_view(self.request.path, index),
          name,
        ) {
          Some(value) => value
          None => default
        }
      } else {
        match query_map_lookup(self.request.path, index).get(name) {
          Some(value) => value
          None => default
        }
      }
    None => default
  }
}

///|
pub fn Context::form(self : Context, name : String) -> String {
  if !self.is_form() {
    return ""
  }
  if name_needs_raw(name.view()) {
    query_param(self.request.body.view(), name)
  } else {
    match form_map_lookup(self.request.body).get(name) {
      Some(value) => value
      None => ""
    }
  }
}

///|
/// Look up the url-encoded form field `name`, returning `default` when the
/// request body is not a form or does not carry the field. Name matching
/// follows `Context::form`, so names containing `%` or `+` also match the raw
/// key spelling. A field that is present with an empty value is returned as-is
/// instead of being replaced by `default`.
pub fn Context::form_default(
  self : Context,
  name : String,
  default : String,
) -> String {
  if !self.is_form() {
    return default
  }
  if name_needs_raw(name.view()) {
    match query_param_opt(self.request.body.view(), name) {
      Some(value) => value
      None => default
    }
  } else {
    match form_map_lookup(self.request.body).get(name) {
      Some(value) => value
      None => default
    }
  }
}

///|
/// The parsed query string, keyed by name. The result is a fresh copy, so
/// mutating it cannot disturb a later request that carries the same query.
pub fn Context::queries(self : Context) -> Map[String, String] {
  let path = self.request.path
  match path_query_index(path) {
    Some(index) => query_map_lookup(path, index).copy()
    None => Map([])
  }
}

///|
/// All query parameters, keyed by name, with every repeated value preserved in
/// appearance order. Unlike `Context::queries`, which keeps only the last value
/// of a repeated parameter, this lets a caller enumerate the complete query
/// without knowing its keys in advance.
///
/// Both the map and its arrays are fresh copies, so mutating the result cannot
/// disturb a later request that carries the same query.
pub fn Context::query_all(
  self : Context,
) -> Map[String, Array[String]] {
  let path = self.request.path
  match path_query_index(path) {
    Some(index) => copy_values_map(query_multi_lookup(path, index))
    None => Map([])
  }
}

///|
/// Whether the query string carries `name`, matching the same decoded and raw
/// spellings as `Context::query`.
///
/// Unlike `Context::query`, this distinguishes an absent parameter from one
/// that is present with an empty value (`?flag` or `?flag=`).
pub fn Context::has_query(self : Context, name : String) -> Bool {
  if name == "" {
    return false
  }
  let path = self.request.path
  match path_query_index(path) {
    Some(index) =>
      if name_needs_raw(name.view()) {
        query_param_opt(query_source_view(path, index), name) is Some(_)
      } else {
        query_map_lookup(path, index).contains(name)
      }
    None => false
  }
}

///|
fn collect_values(source : StringView, name : String) -> Array[String] {
  let values : Array[String] = []
  let name_view = name.view()
  let length = source.length()
  let mut pos = 0
  while pos < length {
    let pair_start = pos
    let mut eq = -1
    let mut end = pos
    while end < length {
      let code = source.unsafe_get(end)
      if code == ('&' : UInt16) {
        break
      }
      if code == ('=' : UInt16) && eq < 0 {
        eq = end
      }
      end = end + 1
    }
    if end > pair_start {
      let key_end = if eq >= 0 { eq } else { end }
      if query_key_matches(source, pair_start, key_end, name_view) {
        if eq >= 0 {
          values.push(decode_url(source[eq + 1:end]))
        } else {
          values.push("")
        }
      }
    }
    pos = end + 1
  }
  values
}

///|
/// Collect every value of a possibly repeated query parameter, in the order
/// they appear in the query string. The result is a fresh array, so mutating
/// it cannot disturb a later request that carries the same query.
pub fn Context::query_values(self : Context, name : String) -> Array[String] {
  match path_query_index(self.request.path) {
    Some(index) =>
      if name_needs_raw(name.view()) {
        collect_values(query_source_view(self.request.path, index), name)
      } else {
        match query_multi_lookup(self.request.path, index).get(name) {
          Some(values) => values.copy()
          None => []
        }
      }
    None => []
  }
}

///|
/// Collect every value of a possibly repeated url-encoded form field, in the
/// order they appear in the request body.
///
/// Returns an empty array when the body is not
/// `application/x-www-form-urlencoded`. The result is a fresh array, so
/// mutating it cannot disturb a later request that carries the same body.
pub fn Context::form_values(self : Context, name : String) -> Array[String] {
  if !self.is_form() {
    return []
  }
  if name_needs_raw(name.view()) {
    collect_values(self.request.body.view(), name)
  } else {
    match form_values_lookup(self.request.body).get(name) {
      Some(values) => values.copy()
      None => []
    }
  }
}

///|
/// The parsed url-encoded form body, keyed by name. The result is a fresh
/// copy, so mutating it cannot disturb a later request that carries the same
/// body.
pub fn Context::form_map(self : Context) -> Map[String, String] {
  if !self.is_form() {
    return Map([])
  }
  form_map_lookup(self.request.body).copy()
}

///|
/// All url-encoded form fields, keyed by name, with every repeated value
/// preserved in appearance order. Returns an empty map when the body is not
/// `application/x-www-form-urlencoded`.
///
/// Both the map and its arrays are fresh copies, so mutating the result cannot
/// disturb a later request that carries the same body.
pub fn Context::form_all(
  self : Context,
) -> Map[String, Array[String]] {
  if !self.is_form() {
    return Map([])
  }
  copy_values_map(form_values_lookup(self.request.body))
}

///|
/// Whether the url-encoded form body carries `name`, matching the same decoded
/// and raw spellings as `Context::form`. Returns `false` for another content
/// type, just like the other form accessors.
///
/// Unlike `Context::form`, this distinguishes an absent field from one that is
/// present with an empty value (`flag` or `flag=`).
pub fn Context::has_form(self : Context, name : String) -> Bool {
  if name == "" || !self.is_form() {
    return false
  }
  if name_needs_raw(name.view()) {
    query_param_opt(self.request.body.view(), name) is Some(_)
  } else {
    form_map_lookup(self.request.body).contains(name)
  }
}

