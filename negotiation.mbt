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
  accept_quality_from(parse_accept_entries(header), want_type, want_subtype)
}

///|
/// One parsed media range of an `Accept` header.
priv struct AcceptEntry {
  range_type : StringView
  range_subtype : StringView
  quality : Int
}

///|
/// Parsed media ranges of an `Accept` header, for scoring against offers.
fn parse_accept_entries(header : StringView) -> Array[AcceptEntry] {
  let entries : Array[AcceptEntry] = Array(capacity=8)
  let length = header.length()
  let mut pos = 0
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
        Some((range_type, range_subtype)) =>
          entries.push({ range_type, range_subtype, quality })
        None => ()
      }
    }
    pos = scan
    if pos < length && header.unsafe_get(pos) == (',' : UInt16) {
      pos = pos + 1
    }
  }
  entries
}

///|
/// Score `want_type`/`want_subtype` against parsed media ranges with the same
/// selection rules as `accept_quality_for`.
fn accept_quality_from(
  entries : Array[AcceptEntry],
  want_type : StringView,
  want_subtype : StringView,
) -> Int {
  if entries.length() == 0 {
    return 1000
  }
  let mut best_q = -1
  let mut best_specificity = -1
  for entry in entries {
    let range_type = entry.range_type
    let range_subtype = entry.range_subtype
    let quality = entry.quality
    if want_type == "*" || want_subtype == "*" {
      let type_ok = range_type == "*" ||
        want_type == "*" ||
        range_type.equal_ignore_ascii_case(want_type)
      let subtype_ok = range_subtype == "*" ||
        want_subtype == "*" ||
        range_subtype.equal_ignore_ascii_case(want_subtype)
      if type_ok && subtype_ok && quality > best_q {
        best_specificity = 0
        best_q = quality
      }
    } else {
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
  }
  if best_specificity < 0 {
    0
  } else {
    best_q
  }
}

///|
/// Most recently parsed `Accept` header and its media ranges.
let last_accept_header : Ref[String?] = Ref(None)

///|
let last_accept_entries : Ref[Array[AcceptEntry]?] = Ref(None)

///|
fn accept_entries_cached(header : String) -> Array[AcceptEntry] {
  match last_accept_header.val {
    Some(cached) =>
      if physical_equal(cached, header) {
        match last_accept_entries.val {
          Some(entries) => return entries
          None => ()
        }
      }
    None => ()
  }
  let entries = parse_accept_entries(header.view())
  last_accept_header.val = Some(header)
  last_accept_entries.val = Some(entries)
  entries
}

///|
/// Check whether the request's `Accept` header allows `media_type`.
///
/// `media_type` may be a concrete type such as `application/json` or contain
/// wildcards such as `text/*` or `*/*`. A missing or empty `Accept` header
/// accepts everything; `q=0` entries reject the matched media type.
pub fn Context::accepts(self : Context, media_type : String) -> Bool {
  let (want_type, want_subtype) = match media_range_parts(media_type.view()) {
    Some(parts) => parts
    None => return false
  }
  let header = self.header("Accept")
  if trim_ascii_space(header.view()).is_empty() {
    return true
  }
  accept_quality_from(accept_entries_cached(header), want_type, want_subtype) > 0
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
  let entries = accept_entries_cached(self.header("Accept"))
  let mut best : String? = None
  let mut best_q = 0
  for offer in offers {
    let (want_type, want_subtype) = match media_range_parts(offer.view()) {
      Some(parts) => parts
      None => continue
    }
    let quality = accept_quality_from(entries, want_type, want_subtype)
    if quality > best_q {
      best_q = quality
      best = Some(offer)
    }
  }
  best
}

///|
/// One parsed `Accept-Encoding` entry: the coding token and its quality value
/// (in thousandths), in header order.
priv struct EncodingEntry {
  token : StringView
  quality : Int
}

///|
/// Parse an `Accept-Encoding` header into its coding entries. The header is
/// expected to be non-blank; parameters other than `q` are ignored.
fn parse_encoding_entries(header : StringView) -> Array[EncodingEntry] {
  let entries : Array[EncodingEntry] = Array(capacity=4)
  let length = header.length()
  let mut pos = 0
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
    entries.push({ token, quality })
    pos = scan
    if pos < length && header.unsafe_get(pos) == (',' : UInt16) {
      pos = pos + 1
    }
  }
  entries
}

///|
/// Quality assigned to `coding` by parsed `Accept-Encoding` entries. The last
/// entry naming `coding` (or `*`) wins, matching `accept_encoding_quality`.
fn encoding_quality_from(
  entries : Array[EncodingEntry],
  coding : StringView,
) -> Int {
  let mut exact_q = -1
  let mut star_q = -1
  for entry in entries {
    if entry.token.equal_ignore_ascii_case(coding) {
      exact_q = entry.quality
    } else if entry.token == "*" {
      star_q = entry.quality
    }
  }
  if exact_q >= 0 {
    exact_q
  } else if star_q >= 0 {
    star_q
  } else if coding.equal_ignore_ascii_case("identity".view()) {
    1000
  } else {
    0
  }
}

///|
/// Quality value (in thousandths) assigned to `coding` by an
/// `Accept-Encoding` header.
///
/// A missing header accepts every coding. An empty header value is treated
/// like a missing header. When the header is present but neither `coding` nor
/// `*` is listed, the coding is not acceptable and `0` is returned.
fn accept_encoding_quality(header : StringView, coding : StringView) -> Int {
  if trim_ascii_space(header).is_empty() {
    return 1000
  }
  encoding_quality_from(parse_encoding_entries(header), coding)
}

///|
/// Check whether the request's `Accept-Encoding` header allows `encoding`.
///
/// A missing or empty header accepts every encoding; `q=0` entries reject the
/// matched encoding, and an encoding that is neither listed nor matched by
/// `*` is not acceptable. The `identity` coding is the exception: it is
/// acceptable by default whenever the header does not explicitly reject it
/// (RFC 9110 §12.5.3).
pub fn Context::accepts_encoding(self : Context, encoding : String) -> Bool {
  accept_encoding_quality(self.header("Accept-Encoding").view(), encoding.view()) >
  0
}

///|
/// Pick the most preferred content coding from `offers` according to the
/// request's `Accept-Encoding` header.
///
/// Returns `None` when the client rejects every offer. Ties keep the order of
/// `offers`, so the server can express its own preference. Use the special
/// `"identity"` offer to represent an unencoded representation.
pub fn Context::preferred_encoding(
  self : Context,
  offers : ArrayView[String],
) -> String? {
  let header = self.header("Accept-Encoding").view()
  let blank = trim_ascii_space(header).is_empty()
  let entries = if blank { [] } else { parse_encoding_entries(header) }
  let mut best : String? = None
  let mut best_q = 0
  for offer in offers {
    let quality = if blank {
      1000
    } else {
      encoding_quality_from(entries, offer.view())
    }
    if quality > best_q {
      best_q = quality
      best = Some(offer)
    }
  }
  best
}

///|
/// One parsed `Accept-Language` entry: the language range and its quality
/// value (in thousandths), in header order.
priv struct LanguageEntry {
  token : StringView
  quality : Int
}

///|
/// Parse an `Accept-Language` header into its non-empty language ranges.
fn parse_language_entries(header : StringView) -> Array[LanguageEntry] {
  let entries : Array[LanguageEntry] = Array(capacity=4)
  let length = header.length()
  let mut pos = 0
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
      entries.push({ token, quality })
    }
    pos = scan
    if pos < length && header.unsafe_get(pos) == (',' : UInt16) {
      pos = pos + 1
    }
  }
  entries
}

///|
/// Quality assigned to `language` by parsed `Accept-Language` entries.
///
/// Matching follows RFC 9110 §12.5.4: a range matches when it is `*`, equals
/// the tag, or is a prefix of the tag ending at a `-` boundary, so `en`
/// matches `en-US`. The most specific matching range decides the quality. With
/// no entries (a missing or empty header) every language is accepted.
fn language_quality_from(
  entries : Array[LanguageEntry],
  language : StringView,
) -> Int {
  if entries.length() == 0 {
    return 1000
  }
  let mut best_q = -1
  let mut best_specificity = -1
  for entry in entries {
    let token = entry.token
    let specificity = if token == "*" {
      0
    } else if token.equal_ignore_ascii_case(language) {
      2
    } else if language.length() > token.length() &&
      token.length() > 0 &&
      language.unsafe_get(token.length()) == ('-' : UInt16) &&
      starts_with_ignore_ascii_case(language, token) {
      1
    } else {
      -1
    }
    if specificity >= 0 && specificity > best_specificity {
      best_specificity = specificity
      best_q = entry.quality
    }
  }
  if best_specificity < 0 {
    0
  } else {
    best_q
  }
}

///|
/// Quality value (in thousandths) assigned to `language` by an
/// `Accept-Language` header.
///
/// A missing or empty header accepts every language.
fn accept_language_quality(header : StringView, language : StringView) -> Int {
  language_quality_from(parse_language_entries(header), language)
}

///|
/// Check whether the request's `Accept-Language` header allows `language`.
///
/// A missing or empty header accepts every language; `q=0` entries reject the
/// matched language, and a language that matches no range and is not covered
/// by `*` is not acceptable.
pub fn Context::accepts_language(self : Context, language : String) -> Bool {
  accept_language_quality(self.header("Accept-Language").view(), language.view()) >
  0
}

///|
/// Pick the most preferred language from `offers` according to the request's
/// `Accept-Language` header.
///
/// Returns `None` when the client rejects every offer. Ties keep the order of
/// `offers`, so the server can express its own preference.
pub fn Context::preferred_language(
  self : Context,
  offers : ArrayView[String],
) -> String? {
  let entries = parse_language_entries(self.header("Accept-Language").view())
  let mut best : String? = None
  let mut best_q = 0
  for offer in offers {
    let quality = language_quality_from(entries, offer.view())
    if quality > best_q {
      best_q = quality
      best = Some(offer)
    }
  }
  best
}
