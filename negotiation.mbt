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
/// Quality value (in thousandths) that `header` assigns to `media_type`, or
/// `0` when it is rejected. Used directly by white-box tests.
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
/// Parsed `Accept` headers keyed by content. The stored key owns the text the
/// entry views point at.
let accept_entries_cache : Map[String, Array[AcceptEntry]] = Map([])

///|
/// Recency ticks for `accept_entries_cache`.
let accept_entries_cache_ages : Map[String, Int] = Map([])

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
  match accept_entries_cache.get(header) {
    Some(entries) => {
      cache_touch(accept_entries_cache_ages, header)
      last_accept_header.val = Some(header)
      last_accept_entries.val = Some(entries)
      return entries
    }
    None => ()
  }
  let entries = parse_accept_entries(header.view())
  if header.length() <= PARSE_CACHE_MAX_KEY {
    cache_set(accept_entries_cache, accept_entries_cache_ages, 32, header, entries)
  }
  last_accept_header.val = Some(header)
  last_accept_entries.val = Some(entries)
  entries
}

///|
/// Parsed spellings of media types passed to `Context::accepts`, keyed by
/// content.
let media_type_parts_cache : Map[String, (String, String)] = Map([])

///|
/// Recency ticks for `media_type_parts_cache`.
let media_type_parts_cache_ages : Map[String, Int] = Map([])

///|
/// Most recently parsed media type and its parts. Offers are usually string
/// literals reused across calls, so a physical-equality fast path skips the
/// map lookups for the common case.
let last_media_type_text : Ref[String?] = Ref(None)
let last_media_type_value : Ref[(String, String)?] = Ref(None)
let last_media_type_hit : Ref[Bool] = Ref(false)

///|
fn media_type_parts_cached(media_type : String) -> (String, String)? {
  match last_media_type_text.val {
    Some(cached) =>
      if physical_equal(cached, media_type) && last_media_type_hit.val {
        return last_media_type_value.val
      }
    None => ()
  }
  match media_type_parts_cache.get(media_type) {
    Some(parts) => {
      cache_touch(media_type_parts_cache_ages, media_type)
      last_media_type_text.val = Some(media_type)
      last_media_type_value.val = Some(parts)
      last_media_type_hit.val = true
      Some(parts)
    }
    None => {
      let parts = match media_range_parts(media_type.view()) {
        Some((media_type, subtype)) => Some((media_type.to_owned(), subtype.to_owned()))
        None => None
      }
      last_media_type_text.val = Some(media_type)
      last_media_type_value.val = parts
      last_media_type_hit.val = true
      match parts {
        Some(parts) => {
          if media_type.length() <= PARSE_CACHE_MAX_KEY {
            cache_set(
              media_type_parts_cache,
              media_type_parts_cache_ages,
              32,
              media_type,
              parts,
            )
          }
          Some(parts)
        }
        None => None
      }
    }
  }
}

///|
/// Check whether the request's `Accept` header allows `media_type`.
///
/// `media_type` may be a concrete type such as `application/json` or contain
/// wildcards such as `text/*` or `*/*`. A missing or empty `Accept` header
/// accepts everything; `q=0` entries reject the matched media type.
pub fn Context::accepts(self : Context, media_type : String) -> Bool {
  let (want_type, want_subtype) = match media_type_parts_cached(media_type) {
    Some(parts) => parts
    None => return false
  }
  let header = self.header("Accept")
  if trim_ascii_space(header.view()).is_empty() {
    return true
  }
  accept_quality_from(
    accept_entries_cached(header),
    want_type.view(),
    want_subtype.view(),
  ) >
  0
}

///|
/// Whether a parsed `Accept` range asks for JSON.
fn accept_entry_asks_json(entry : AcceptEntry) -> Bool {
  let range_type = entry.range_type
  if range_type == "*" {
    return false
  }
  if !range_type.equal_ignore_ascii_case("application".view()) {
    return false
  }
  let subtype = entry.range_subtype
  if subtype.equal_ignore_ascii_case("json".view()) {
    return true
  }
  let length = subtype.length()
  length > 5 && subtype[length - 5:].equal_ignore_ascii_case("+json".view())
}

///|
/// Whether the request prefers a JSON response.
///
/// True when the client sends `X-Requested-With: XMLHttpRequest`, or when the
/// most preferred media range of the `Accept` header asks for JSON
/// (`application/json`, `application/problem+json`, ...). A missing or empty
/// `Accept` header is not a JSON preference, so plain browser requests keep
/// getting HTML. This is the usual switch for handlers that render JSON for
/// API clients and HTML for browsers.
pub fn Context::wants_json(self : Context) -> Bool {
  let requested_with = trim_ascii_space(self.header("X-Requested-With").view())
  if requested_with.equal_ignore_ascii_case("XMLHttpRequest".view()) {
    return true
  }
  let header = self.header("Accept")
  if trim_ascii_space(header.view()).is_empty() {
    return false
  }
  let mut found = false
  let mut best_quality = 0
  let mut best_asks_json = false
  for entry in accept_entries_cached(header) {
    if entry.quality <= 0 {
      continue
    }
    if !found || entry.quality > best_quality {
      found = true
      best_quality = entry.quality
      best_asks_json = accept_entry_asks_json(entry)
    }
  }
  found && best_asks_json
}

///|
/// Most recent header/offers pair scored by `preferred_type` and its result.
/// The inputs are copied so later mutations of the caller's array cannot
/// change a cached result.
let last_preferred_type : Ref[(String, Array[String], String?)?] = Ref(None)

///|
fn Context::preferred_type_compute(
  self : Context,
  header : String,
  offers : ArrayView[String],
) -> String? {
  if trim_ascii_space(header.view()).is_empty() {
    for offer in offers {
      if media_type_parts_cached(offer) is Some(_) {
        return Some(offer)
      }
    }
    return None
  }
  let entries = accept_entries_cached(header)
  let mut best : String? = None
  let mut best_q = 0
  for offer in offers {
    let (want_type, want_subtype) = match media_type_parts_cached(offer) {
      Some(parts) => parts
      None => continue
    }
    let quality = accept_quality_from(
      entries,
      want_type.view(),
      want_subtype.view(),
    )
    if quality >= 1000 {
      return Some(offer)
    }
    if quality > best_q {
      best_q = quality
      best = Some(offer)
    }
  }
  best
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
  let header = self.header("Accept")
  match last_preferred_type.val {
    Some((cached_header, cached_offers, cached_result)) =>
      if (physical_equal(cached_header, header) || cached_header == header) &&
        cached_offers.length() == offers.length() {
        let mut same = true
        for i = 0; i < cached_offers.length(); i = i + 1 {
          if !physical_equal(cached_offers[i], offers[i]) &&
            cached_offers[i] != offers[i] {
            same = false
            break
          }
        }
        if same {
          return cached_result
        }
      }
    None => ()
  }
  let result = self.preferred_type_compute(header, offers)
  let copied : Array[String] = Array(capacity=offers.length())
  for offer in offers {
    copied.push(offer)
  }
  last_preferred_type.val = Some((header, copied, result))
  result
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
/// Most recently parsed `Accept-Encoding` header and its coding entries.
let last_encoding_header : Ref[String?] = Ref(None)

///|
let last_encoding_entries : Ref[Array[EncodingEntry]?] = Ref(None)

///|
/// Parsed `Accept-Encoding` headers keyed by content.
let encoding_entries_cache : Map[String, Array[EncodingEntry]] = Map([])

///|
/// Recency ticks for `encoding_entries_cache`.
let encoding_entries_cache_ages : Map[String, Int] = Map([])

///|
fn encoding_entries_cached(header : String) -> Array[EncodingEntry] {
  match last_encoding_header.val {
    Some(cached) =>
      if physical_equal(cached, header) {
        match last_encoding_entries.val {
          Some(entries) => return entries
          None => ()
        }
      }
    None => ()
  }
  match encoding_entries_cache.get(header) {
    Some(entries) => {
      cache_touch(encoding_entries_cache_ages, header)
      last_encoding_header.val = Some(header)
      last_encoding_entries.val = Some(entries)
      return entries
    }
    None => ()
  }
  let entries = parse_encoding_entries(header.view())
  if header.length() <= PARSE_CACHE_MAX_KEY {
    cache_set(encoding_entries_cache, encoding_entries_cache_ages, 32, header, entries)
  }
  last_encoding_header.val = Some(header)
  last_encoding_entries.val = Some(entries)
  entries
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
/// A request without the header has no stated preference, so every encoding is
/// accepted. An empty header value requests no content coding at all, so only
/// `identity` (the absence of a coding) remains acceptable. `q=0` entries
/// reject the matched encoding, and an encoding that is neither listed nor
/// matched by `*` is not acceptable; `identity` is the exception and stays
/// acceptable whenever it is not explicitly rejected (RFC 9110 §12.5.3).
pub fn Context::accepts_encoding(self : Context, encoding : String) -> Bool {
  match get_header_ignore_case(self.request.headers, "Accept-Encoding") {
    None => true
    Some(header) =>
      encoding_quality_from(encoding_entries_cached(header), encoding.view()) >
      0
  }
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
  match get_header_ignore_case(self.request.headers, "Accept-Encoding") {
    None =>
      // No stated preference: keep the server's own order.
      if offers.length() > 0 {
        Some(offers[0])
      } else {
        None
      }
    Some(header) => {
      let entries = encoding_entries_cached(header)
      let mut best : String? = None
      let mut best_q = 0
      for offer in offers {
        let quality = encoding_quality_from(entries, offer.view())
        if quality >= 1000 {
          return Some(offer)
        }
        if quality > best_q {
          best_q = quality
          best = Some(offer)
        }
      }
      best
    }
  }
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
/// Most recently parsed `Accept-Language` header and its language entries.
let last_language_header : Ref[String?] = Ref(None)

///|
let last_language_entries : Ref[Array[LanguageEntry]?] = Ref(None)

///|
/// Parsed `Accept-Language` headers keyed by content.
let language_entries_cache : Map[String, Array[LanguageEntry]] = Map([])

///|
/// Recency ticks for `language_entries_cache`.
let language_entries_cache_ages : Map[String, Int] = Map([])

///|
fn language_entries_cached(header : String) -> Array[LanguageEntry] {
  match last_language_header.val {
    Some(cached) =>
      if physical_equal(cached, header) {
        match last_language_entries.val {
          Some(entries) => return entries
          None => ()
        }
      }
    None => ()
  }
  match language_entries_cache.get(header) {
    Some(entries) => {
      cache_touch(language_entries_cache_ages, header)
      last_language_header.val = Some(header)
      last_language_entries.val = Some(entries)
      return entries
    }
    None => ()
  }
  let entries = parse_language_entries(header.view())
  if header.length() <= PARSE_CACHE_MAX_KEY {
    cache_set(language_entries_cache, language_entries_cache_ages, 32, header, entries)
  }
  last_language_header.val = Some(header)
  last_language_entries.val = Some(entries)
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
/// Check whether the request's `Accept-Language` header allows `language`.
///
/// A missing or empty header accepts every language; `q=0` entries reject the
/// matched language, and a language that matches no range and is not covered
/// by `*` is not acceptable.
pub fn Context::accepts_language(self : Context, language : String) -> Bool {
  let header = self.header("Accept-Language")
  if trim_ascii_space(header.view()).is_empty() {
    return true
  }
  language_quality_from(language_entries_cached(header), language.view()) > 0
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
  let header = self.header("Accept-Language")
  if trim_ascii_space(header.view()).is_empty() {
    if offers.length() > 0 {
      return Some(offers[0])
    }
    return None
  }
  let entries = language_entries_cached(header)
  let mut best : String? = None
  let mut best_q = 0
  for offer in offers {
    let quality = language_quality_from(entries, offer.view())
    if quality >= 1000 {
      return Some(offer)
    }
    if quality > best_q {
      best_q = quality
      best = Some(offer)
    }
  }
  best
}
