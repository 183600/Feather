///|
fn is_bearer_token_base_char(code : Int) -> Bool {
  (code >= 65 && code <= 90) ||
  (code >= 97 && code <= 122) ||
  (code >= 48 && code <= 57) ||
  code == 45 ||
  code == 46 ||
  code == 95 ||
  code == 126 ||
  code == 43 ||
  code == 47
}

///|
/// Whether `view` is an RFC 6750 `token68` credential: one or more base
/// characters followed by zero or more `=` padding characters.
fn bearer_token_is_valid(view : StringView) -> Bool {
  let length = view.length()
  if length == 0 {
    return false
  }
  let mut i = 0
  let mut has_base = false
  let mut padding = false
  while i < length {
    let code = view.unsafe_get(i).to_int()
    if code == 61 {
      padding = true
    } else {
      if padding || !is_bearer_token_base_char(code) {
        return false
      }
      has_base = true
    }
    i += 1
  }
  has_base
}

///|
/// Parse an `Authorization: Bearer ...` header into the opaque bearer token.
/// Returns `None` when the header is missing or the credential is not a valid
/// RFC 6750 `token68` value.
pub fn Context::bearer_token(self : Context) -> String? {
  let authorization = self.header("Authorization")
  let view = authorization.view()
  if !starts_with_ignore_ascii_case(view, "Bearer".view()) {
    return None
  }
  let rest = view[6:]
  let len = rest.length()
  let mut i = 0
  while i < len {
    let c = rest.unsafe_get(i).to_int()
    if c == 32 || c == 9 {
      i += 1
    } else {
      break
    }
  }
  if i == 0 {
    return None
  }
  let token = trim_ascii_space(rest[i:])
  if bearer_token_is_valid(token) {
    Some(token.to_owned())
  } else {
    None
  }
}

///|
/// Parse an `Authorization: Basic ...` header into a `(username, password)`
/// pair. Returns `None` when the header is missing or malformed.
pub fn Context::basic_auth(self : Context) -> (String, String)? {
  let authorization = self.header("Authorization")
  let view = authorization.view()
  if !starts_with_ignore_ascii_case(view, "Basic".view()) {
    return None
  }
  let rest = view[5:]
  let mut i = 0
  let len = rest.length()
  while i < len {
    let c = rest.unsafe_get(i).to_int()
    if c == 32 || c == 9 {
      i += 1
    } else {
      break
    }
  }
  if i == 0 {
    return None
  }
  let encoded = trim_ascii_space(rest[i:])
  if encoded.is_empty() {
    return None
  }
  let decoded = match base64_decode_view(encoded) {
    Some(decoded) => @utf8.decode_lossy(decoded)
    None => return None
  }
  match decoded.find(":") {
    Some(index) =>
      Some((decoded[:index].to_owned(), decoded[index + 1:].to_owned()))
    None => Some((decoded, ""))
  }
}

///|
pub fn Context::request_id(self : Context) -> String {
  match self.state.get("request_id") {
    Some(value) => value
    None => ""
  }
}

