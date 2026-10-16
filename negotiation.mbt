///|
fn media_range_parts(range : StringView) -> (StringView, StringView)? {
  let mut end = range.length()
  let mut slash = -1
  let mut i = 0
  while i < end {
    let code = range.unsafe_get(i)
    if code == (';' : UInt16) {
      end = i
      break
    }
    if code == ('/' : UInt16) && slash < 0 {
      slash = i
    }
    i = i + 1
  }
  if slash <= 0 || slash + 1 >= end {
    return None
  }
  let media_type = trim_ascii_space(range[:slash])
  let subtype = trim_ascii_space(range[slash + 1:end])
  if media_type.is_empty() || subtype.is_empty() {
    return None
  }
  Some((media_type, subtype))
}

///|
fn accept_quality_for(header : StringView, media_type : StringView) -> Int {
  let (want_type, want_subtype) = match media_range_parts(media_type) {
    Some(parts) => parts
    None => return 0
  }
  if trim_ascii_space(header).is_empty() {
    return 1000
  }
  let length = header.length()
  let mut pos = 0
  let mut best_q = -1
  let mut best_specificity = -1
  let mut saw_entry = false
  while pos < length {
    let mut end = pos
    while end < length {
      let code = header.unsafe_get(end)
      if code == (';' : UInt16) || code == (',' : UInt16) {
        break
      }
      end = end + 1
    }
    let token = trim_ascii_space(header[pos:end])
    let mut quality = 1000
    let mut scan = end
    while scan < length && header.unsafe_get(scan) == (';' : UInt16) {
      scan = scan + 1
      let parameter_start = scan
      while scan < length {
        let code = header.unsafe_get(scan)
        if code == (';' : UInt16) || code == (',' : UInt16) {
          break
        }
        scan = scan + 1
      }
      let parameter = trim_ascii_space(header[parameter_start:scan])
      if parameter.length() >= 2 &&
        (parameter.unsafe_get(0) == ('q' : UInt16) ||
          parameter.unsafe_get(0) == ('Q' : UInt16)) {
        let mut marker = 1
        while marker < parameter.length() &&
          parameter.unsafe_get(marker) == (' ' : UInt16) {
          marker = marker + 1
        }
        if marker < parameter.length() &&
          parameter.unsafe_get(marker) == ('=' : UInt16) {
          quality = parse_quality(trim_ascii_space(parameter[marker + 1:]))
        }
      }
    }
    if !token.is_empty() {
      let parts = if token == "*" {
        Some(("*".view(), "*".view()))
      } else {
        media_range_parts(token)
      }
      match parts {
        Some((range_type, range_subtype)) => {
          saw_entry = true
          let specificity = if range_type == "*" && range_subtype == "*" {
            0
          } else if range_subtype == "*" {
            if range_type.equal_ignore_ascii_case(want_type) { 1 } else { -1 }
          } else if range_type.equal_ignore_ascii_case(want_type) &&
            range_subtype.equal_ignore_ascii_case(want_subtype) {
            2
          } else {
            -1
          }
          if specificity >= 0 && specificity > best_specificity {
            best_specificity = specificity
            best_q = quality
          }
        }
        None => ()
      }
    }
    pos = scan
    if pos < length && header.unsafe_get(pos) == (',' : UInt16) {
      pos = pos + 1
    }
  }
  if !saw_entry {
    return 1000
  }
  if best_specificity < 0 {
    0
  } else {
    best_q
  }
}

///|
/// Check whether the request's `Accept` header allows `media_type`.
///
/// `media_type` may be a concrete type such as `application/json` or contain
/// wildcards such as `text/*` or `*/*`. A missing or empty `Accept` header
/// accepts everything; `q=0` entries reject the matched media type.
pub fn Context::accepts(self : Context, media_type : String) -> Bool {
  accept_quality_for(self.header("Accept").view(), media_type.view()) > 0
}

///|
/// Pick the most preferred media type from `offers` according to the
/// request's `Accept` header.
///
/// Returns `None` when the client rejects every offer. Ties keep the order of
/// `offers`, so the server can express its own preference.
pub fn Context::preferred_type(
  self : Context,
  offers : ArrayView[String],
) -> String? {
  let header = self.header("Accept").view()
  let mut best : String? = None
  let mut best_q = 0
  for offer in offers {
    let quality = accept_quality_for(header, offer.view())
    if quality > best_q {
      best_q = quality
      best = Some(offer)
    }
  }
  best
}
