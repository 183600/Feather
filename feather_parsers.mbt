///|
fn parse_int_value(value : StringView) -> Int32? {
  let length = value.length()
  if length == 0 {
    return None
  }
  let mut index = 0
  let mut negative = false
  let first = value.unsafe_get(0)
  if first == ('-' : UInt16) {
    negative = true
    index = 1
  } else if first == ('+' : UInt16) {
    index = 1
  }
  if index >= length {
    return None
  }
  let mut result = 0L
  while index < length {
    let digit = value.unsafe_get(index).to_int() - 48
    if digit < 0 || digit > 9 {
      return None
    }
    result = result * 10L + digit.to_int64()
    if result > 2147483648L {
      return None
    }
    index = index + 1
  }
  let signed = if negative { -result } else { result }
  if signed > 2147483647L || signed < -2147483648L {
    return None
  }
  Some(signed.to_int())
}

///|
/// Parse a signed decimal integer into a 64-bit value.
///
/// Unlike `parse_int_value`, the magnitude is accumulated in `UInt64` so the
/// full `Int64` range, including `-9223372036854775808`, can be represented
/// without overflowing before the sign is applied. Leading `+`/`-` signs are
/// accepted; any other non-digit character, an empty body or a value outside
/// the signed 64-bit range yields `None`.
fn parse_int64_value(value : StringView) -> Int64? {
  let length = value.length()
  if length == 0 {
    return None
  }
  let mut index = 0
  let mut negative = false
  let first = value.unsafe_get(0)
  if first == ('-' : UInt16) {
    negative = true
    index = 1
  } else if first == ('+' : UInt16) {
    index = 1
  }
  if index >= length {
    return None
  }
  let limit : UInt64 = if negative {
    9223372036854775808UL
  } else {
    9223372036854775807UL
  }
  let mut magnitude = 0UL
  while index < length {
    let digit = value.unsafe_get(index).to_int() - 48
    if digit < 0 || digit > 9 {
      return None
    }
    let digit64 = digit.to_uint64()
    if magnitude > (limit - digit64) / 10UL {
      return None
    }
    magnitude = magnitude * 10UL + digit64
    index = index + 1
  }
  let signed = if negative {
    (0UL - magnitude).to_int64()
  } else {
    magnitude.to_int64()
  }
  Some(signed)
}

///|
fn parse_bool_value(value : StringView) -> Bool? {
  if value == "true" || value == "1" {
    Some(true)
  } else if value == "false" || value == "0" {
    Some(false)
  } else {
    None
  }
}

///|
///|
/// The percent-decoded route parameter `name` parsed as a signed 32-bit
/// integer. Returns `None` when the parameter is absent or out of range.
pub fn Context::param_int(self : Context, name : String) -> Int32? {
  parse_int_value(self.param_decoded(name).view())
}

///|
/// The percent-decoded route parameter `name` parsed as a signed 64-bit
/// integer. Returns `None` when the parameter is absent or does not fit in
/// `Int64`.
pub fn Context::param_int64(self : Context, name : String) -> Int64? {
  parse_int64_value(self.param_decoded(name).view())
}

///|
/// The percent-decoded route parameter `name` parsed as a boolean.
pub fn Context::param_bool(self : Context, name : String) -> Bool? {
  parse_bool_value(self.param_decoded(name).view())
}

///|
pub fn Context::query_int(self : Context, name : String) -> Int32? {
  parse_int_value(self.query(name).view())
}

///|
/// The query parameter `name` parsed as a signed 64-bit integer. Returns
/// `None` when the parameter is absent or does not fit in `Int64`.
pub fn Context::query_int64(self : Context, name : String) -> Int64? {
  parse_int64_value(self.query(name).view())
}

///|
pub fn Context::query_bool(self : Context, name : String) -> Bool? {
  parse_bool_value(self.query(name).view())
}

///|
/// Parse a finite decimal floating-point value, rejecting malformed input and
/// the non-finite spellings (`nan`, `inf`, `-inf`) that JSON cannot represent.
fn parse_float_value(value : StringView) -> Double? {
  let length = value.length()
  if length == 0 {
    return None
  }
  // Validate the literal before delegating to `parse_double`, which also
  // accepts leading signs and digit separators such as underscores. Accept an
  // optional leading sign, digits with an optional fractional part, and an
  // optional exponent; at least one mantissa digit is required.
  let mut index = 0
  let first = value.unsafe_get(0)
  if first == ('+' : UInt16) || first == ('-' : UInt16) {
    index = 1
  }
  let mut digits = 0
  while index < length {
    let code = value.unsafe_get(index).to_int()
    if code < 48 || code > 57 {
      break
    }
    digits = digits + 1
    index = index + 1
  }
  if index < length && value.unsafe_get(index) == ('.' : UInt16) {
    index = index + 1
    while index < length {
      let code = value.unsafe_get(index).to_int()
      if code < 48 || code > 57 {
        break
      }
      digits = digits + 1
      index = index + 1
    }
  }
  if digits == 0 {
    return None
  }
  if index < length &&
    (
      value.unsafe_get(index) == ('e' : UInt16) ||
      value.unsafe_get(index) == ('E' : UInt16)
    ) {
    index = index + 1
    if index < length &&
      (
        value.unsafe_get(index) == ('+' : UInt16) ||
        value.unsafe_get(index) == ('-' : UInt16)
      ) {
      index = index + 1
    }
    let mut exponent_digits = 0
    while index < length {
      let code = value.unsafe_get(index).to_int()
      if code < 48 || code > 57 {
        break
      }
      exponent_digits = exponent_digits + 1
      index = index + 1
    }
    if exponent_digits == 0 {
      return None
    }
  }
  if index != length {
    return None
  }
  // `parse_double` otherwise expects the first character to be a digit, `-` or
  // `.`; the explicit plus sign is only stripped for the actual conversion.
  let normalized = if first == ('+' : UInt16) { value[1:] } else { value }
  let parsed = @string.parse_double(normalized) catch { _ => return None }
  if parsed.is_nan() || parsed.is_inf() {
    None
  } else {
    Some(parsed)
  }
}

///|
/// The percent-decoded route parameter `name` parsed as a finite
/// floating-point number.
pub fn Context::param_float(self : Context, name : String) -> Double? {
  parse_float_value(self.param_decoded(name).view())
}

///|
/// The query parameter `name` parsed as a finite floating-point number.
pub fn Context::query_float(self : Context, name : String) -> Double? {
  parse_float_value(self.query(name).view())
}

///|
/// The request header `name` parsed as a signed 32-bit integer.
///
/// Surrounding optional whitespace is ignored, matching the way header values
/// arrive on the wire. Returns `None` when the header is absent, malformed, or
/// outside the `Int32` range.
pub fn Context::header_int(self : Context, name : String) -> Int32? {
  parse_int_value(trim_ascii_space(self.header(name).view()))
}

///|
/// The request header `name` parsed as a signed 64-bit integer. Returns `None`
/// when the header is absent, malformed, or does not fit in `Int64`.
pub fn Context::header_int64(self : Context, name : String) -> Int64? {
  parse_int64_value(trim_ascii_space(self.header(name).view()))
}

///|
/// The request header `name` parsed as a boolean. Accepts the same spellings
/// as `Context::query_bool` (`true`/`false` and `1`/`0`).
pub fn Context::header_bool(self : Context, name : String) -> Bool? {
  parse_bool_value(trim_ascii_space(self.header(name).view()))
}

///|
/// The request header `name` parsed as a finite floating-point number.
/// Returns `None` when the header is absent, malformed, or names `nan`/`inf`.
pub fn Context::header_float(self : Context, name : String) -> Double? {
  parse_float_value(trim_ascii_space(self.header(name).view()))
}

///|
/// The form field `name` parsed as an integer. Both urlencoded and multipart
/// bodies are supported. Returns `None` when the request body is not a form,
/// the field is absent, or the value is not a valid 32-bit integer.
pub fn Context::form_int(self : Context, name : String) -> Int32? {
  parse_int_value(self.form(name).view())
}

///|
/// The form field `name` parsed as a signed 64-bit integer. Both urlencoded
/// and multipart bodies are supported. Returns `None` when the request body is
/// not a form, the field is absent, or the value does not fit in `Int64`.
pub fn Context::form_int64(self : Context, name : String) -> Int64? {
  parse_int64_value(self.form(name).view())
}

///|
/// The form field `name` parsed as a boolean. Both urlencoded and multipart
/// bodies are supported. Accepts the same spellings as `Context::query_bool`
/// (`true`/`false` and `1`/`0`).
pub fn Context::form_bool(self : Context, name : String) -> Bool? {
  parse_bool_value(self.form(name).view())
}

///|
/// The form field `name` parsed as a finite floating-point number. Both
/// urlencoded and multipart bodies are supported.
pub fn Context::form_float(self : Context, name : String) -> Double? {
  parse_float_value(self.form(name).view())
}

///|
pub fn Context::set_json(self : Context, key : String, value : Json) -> Unit {
  self.json_state.set(key, value)
}

///|
pub fn Context::get_json(self : Context, key : String) -> Json? {
  self.json_state.get(key)
}

///|
/// Whether JSON state contains `key`, including keys seeded from application
/// state. Unlike `Context::get_json`, this treats a stored JSON null as
/// present.
pub fn Context::has_json_state(self : Context, key : String) -> Bool {
  self.json_state.contains(key)
}

///|
/// Remove `key` from JSON state. Returns whether the key was present. Removing
/// a key seeded from application state only affects this request.
pub fn Context::remove_json_state(self : Context, key : String) -> Bool {
  match self.json_state.remove_and_get(key) {
    Some(_) => true
    None => false
  }
}

///|
/// Register `cleanup` to run when the request finishes, whether the handler
/// succeeded or failed. Cleanups run in reverse registration order and are
/// best-effort: a cleanup that raises does not stop the others.
pub fn Context::defer_cleanup(
  self : Context,
  cleanup : () -> Unit raise,
) -> Unit {
  self.cleanups.push(cleanup)
}

