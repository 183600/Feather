///|
fn is_cookie_whitespace(code : UInt16) -> Bool {
  code == (' ' : UInt16) ||
  code == ('\t' : UInt16) ||
  code == ('\n' : UInt16) ||
  code == ('\r' : UInt16)
}

///|
/// Parse a `Cookie` request header into a name-to-value map.
///
/// User agents order same-name cookies with the longest (most specific) path
/// first (RFC 6265 §5.4), so the first occurrence is the one to use. Later
/// duplicates are ignored instead of shadowing a more specific cookie (such as
/// a session scoped to `/app`).
fn parse_cookie_map(header : StringView) -> Map[String, String] {
  let cookies : Map[String, String] = Map([], capacity=8)
  let length = header.length()
  let mut pos = 0
  while pos <= length {
    let mut end = pos
    while end < length && header.unsafe_get(end) != (';' : UInt16) {
      end = end + 1
    }
    let mut start = pos
    while start < end && is_cookie_whitespace(header.unsafe_get(start)) {
      start = start + 1
    }
    let mut stop = end
    while stop > start && is_cookie_whitespace(header.unsafe_get(stop - 1)) {
      stop = stop - 1
    }
    if start < stop {
      let mut eq = start
      while eq < stop && header.unsafe_get(eq) != ('=' : UInt16) {
        eq = eq + 1
      }
      if eq < stop {
        let mut name_end = eq
        while name_end > start &&
              is_cookie_whitespace(header.unsafe_get(name_end - 1)) {
          name_end = name_end - 1
        }
        if name_end > start {
          let name = header[start:name_end].to_owned()
          // A cookie name that is not an HTTP token cannot have been written
          // by `set_cookie` (which sanitizes names), so ignore it instead of
          // exposing a spelling that `Context::cookie` can never look up.
          let mut valid_name = true
          let mut name_index = start
          while name_index < name_end {
            if !is_cookie_name_character(header.unsafe_get(name_index)) {
              valid_name = false
              break
            }
            name_index = name_index + 1
          }
          let mut raw_start = eq + 1
          while raw_start < stop &&
                is_cookie_whitespace(header.unsafe_get(raw_start)) {
            raw_start = raw_start + 1
          }
          let value = if stop - raw_start >= 2 &&
            header.unsafe_get(raw_start) == ('"' : UInt16) &&
            header.unsafe_get(stop - 1) == ('"' : UInt16) {
            header[raw_start + 1:stop - 1].to_owned()
          } else {
            header[raw_start:stop].to_owned()
          }
          if valid_name && !cookies.contains(name) {
            cookies.set(name, value)
          }
        }
      }
    }
    if end >= length {
      break
    }
    pos = end + 1
  }
  cookies
}

///|
/// Parse a `Cookie` request header into every value of each name, preserving
/// header order. Invalid names are ignored just like `parse_cookie_map`.
fn parse_cookie_multi(
  header : StringView,
) -> Map[String, Array[String]] {
  let cookies : Map[String, Array[String]] = Map([], capacity=8)
  let length = header.length()
  let mut pos = 0
  while pos <= length {
    let mut end = pos
    while end < length && header.unsafe_get(end) != (';' : UInt16) {
      end = end + 1
    }
    let mut start = pos
    while start < end && is_cookie_whitespace(header.unsafe_get(start)) {
      start = start + 1
    }
    let mut stop = end
    while stop > start && is_cookie_whitespace(header.unsafe_get(stop - 1)) {
      stop = stop - 1
    }
    if start < stop {
      let mut eq = start
      while eq < stop && header.unsafe_get(eq) != ('=' : UInt16) {
        eq = eq + 1
      }
      if eq < stop {
        let mut name_end = eq
        while name_end > start &&
              is_cookie_whitespace(header.unsafe_get(name_end - 1)) {
          name_end = name_end - 1
        }
        if name_end > start {
          let name = header[start:name_end].to_owned()
          let mut valid_name = true
          let mut name_index = start
          while name_index < name_end {
            if !is_cookie_name_character(header.unsafe_get(name_index)) {
              valid_name = false
              break
            }
            name_index = name_index + 1
          }
          let mut raw_start = eq + 1
          while raw_start < stop &&
                is_cookie_whitespace(header.unsafe_get(raw_start)) {
            raw_start = raw_start + 1
          }
          let value = if stop - raw_start >= 2 &&
            header.unsafe_get(raw_start) == ('"' : UInt16) &&
            header.unsafe_get(stop - 1) == ('"' : UInt16) {
            header[raw_start + 1:stop - 1].to_owned()
          } else {
            header[raw_start:stop].to_owned()
          }
          if valid_name {
            match cookies.get(name) {
              Some(values) => values.push(value)
              None => cookies.set(name, [value])
            }
          }
        }
      }
    }
    if end >= length {
      break
    }
    pos = end + 1
  }
  cookies
}

///|
/// Deep-copy a map of multi-value parameters, so callers cannot mutate the
/// arrays held by the parse cache.
fn copy_values_map(
  source : Map[String, Array[String]],
) -> Map[String, Array[String]] {
  let copy : Map[String, Array[String]] = Map(
    [],
    capacity=source.length(),
  )
  for key, values in source {
    copy.set(key, values.copy())
  }
  copy
}

///|
/// Maximum number of entries kept in the parse caches.
const PARSE_CACHE_LIMIT : Int32 = 128

///|
/// Maximum key length stored in the parse caches.
const PARSE_CACHE_MAX_KEY : Int32 = 4096

///|
/// Monotonic tick used by the bounded caches to approximate LRU eviction.
let cache_clock : Ref[Int32] = Ref(0)

///|
/// How many entries an eviction samples before dropping the oldest one seen.
const CACHE_EVICT_SAMPLE : Int32 = 4

///|
/// Refresh a hit entry's recency tick only once the clock has moved this far
/// past it.
const CACHE_TOUCH_INTERVAL : Int32 = 16

///|
/// Return a fresh tick, marking the entry that uses it as most recent.
fn cache_advance() -> Int32 {
  cache_clock.val = cache_clock.val + 1
  cache_clock.val
}

///|
/// Record `key` as recently used unless its recorded tick is still close to the
/// current clock.
fn[K : Hash + Eq] cache_touch(ages : Map[K, Int32], key : K) -> Unit {
  let now = cache_clock.val
  match ages.get(key) {
    Some(tick) => if now - tick < CACHE_TOUCH_INTERVAL { return }
    None => ()
  }
  ages.set(key, cache_advance())
}

///|
/// Evict one entry, sampling a few candidates and dropping the one with the
/// oldest tick. The victim is approximate rather than exact LRU.
fn[K : Hash + Eq, V] cache_evict(
  cache : Map[K, V],
  ages : Map[K, Int32],
) -> Unit {
  let mut oldest : K? = None
  let mut oldest_tick = 0
  let mut sampled = 0
  for key, tick in ages {
    if sampled >= CACHE_EVICT_SAMPLE {
      break
    }
    let replace = match oldest {
      None => true
      Some(_) => tick < oldest_tick
    }
    if replace {
      oldest = Some(key)
      oldest_tick = tick
    }
    sampled = sampled + 1
  }
  match oldest {
    Some(key) => {
      ignore(cache.remove(key))
      ignore(ages.remove(key))
    }
    None =>
      match cache.keys().next() {
        Some(key) => ignore(cache.remove(key))
        None => ()
      }
  }
}

///|
/// Insert into a bounded cache, evicting the least recently used entry when
/// the cache is full.
fn[K : Hash + Eq, V] cache_set(
  cache : Map[K, V],
  ages : Map[K, Int32],
  limit : Int32,
  key : K,
  value : V,
) -> Unit {
  if cache.length() >= limit && !cache.contains(key) {
    cache_evict(cache, ages)
  }
  cache.set(key, value)
  ages.set(key, cache_advance())
}

///|
/// Insert into one of the parse caches.
fn[K : Hash + Eq, V] parse_cache_set(
  cache : Map[K, V],
  ages : Map[K, Int32],
  key : K,
  value : V,
) -> Unit {
  cache_set(cache, ages, PARSE_CACHE_LIMIT, key, value)
}

///|
/// Last parsed `Cookie` header, keyed by its raw value.
let cookies_cache : Map[String, Map[String, String]] = Map([])

///|
/// Recency ticks for `cookies_cache`.
let cookies_cache_ages : Map[String, Int32] = Map([])

///|
/// Last parsed query strings, keyed by the raw text after `?`.
let queries_cache : Map[StringView, Map[String, String]] = Map([])

///|
/// Recency ticks for `queries_cache`.
let queries_cache_ages : Map[StringView, Int32] = Map([])

///|
/// Most recently resolved `Cookie` header and its parsed map.
let last_cookie_header : Ref[String?] = Ref(None)

///|
let last_cookie_map : Ref[Map[String, String]?] = Ref(None)

///|
fn cookie_map_lookup(header : String) -> Map[String, String] {
  match last_cookie_header.val {
    Some(cached_header) =>
      if physical_equal(cached_header, header) {
        match last_cookie_map.val {
          Some(cached_map) => return cached_map
          None => ()
        }
      }
    None => ()
  }
  let parsed = match cookies_cache.get(header) {
    Some(cached) => {
      cache_touch(cookies_cache_ages, header)
      cached
    }
    None => {
      let parsed = parse_cookie_map(header.view())
      if header.length() <= PARSE_CACHE_MAX_KEY {
        parse_cache_set(cookies_cache, cookies_cache_ages, header, parsed)
      }
      parsed
    }
  }
  last_cookie_header.val = Some(header)
  last_cookie_map.val = Some(parsed)
  parsed
}

///|
/// Last parsed `Cookie` header with every value of each name.
let cookies_multi_cache : Map[String, Map[String, Array[String]]] = Map([])

///|
/// Recency ticks for `cookies_multi_cache`.
let cookies_multi_cache_ages : Map[String, Int32] = Map([])

///|
/// Most recently resolved `Cookie` header and its multi-value map.
let last_cookie_multi_header : Ref[String?] = Ref(None)

///|
let last_cookie_multi_map : Ref[Map[String, Array[String]]?] = Ref(None)

///|
fn cookie_multi_lookup(header : String) -> Map[String, Array[String]] {
  match last_cookie_multi_header.val {
    Some(cached_header) =>
      if physical_equal(cached_header, header) {
        match last_cookie_multi_map.val {
          Some(cached_map) => return cached_map
          None => ()
        }
      }
    None => ()
  }
  let parsed = match cookies_multi_cache.get(header) {
    Some(cached) => {
      cache_touch(cookies_multi_cache_ages, header)
      cached
    }
    None => {
      let parsed = parse_cookie_multi(header.view())
      if header.length() <= PARSE_CACHE_MAX_KEY {
        parse_cache_set(
          cookies_multi_cache,
          cookies_multi_cache_ages,
          header,
          parsed,
        )
      }
      parsed
    }
  }
  last_cookie_multi_header.val = Some(header)
  last_cookie_multi_map.val = Some(parsed)
  parsed
}

///|
/// Most recently scanned path and the position of its `?`.
let last_query_index_path : Ref[String?] = Ref(None)

///|
let last_query_index : Ref[Int32] = Ref(-1)

///|
/// Position of `?` in `path` for the most recent path, or `None` when there is
/// no query or a fragment starts before it.
fn path_query_index(path : String) -> Int32? {
  match last_query_index_path.val {
    Some(cached) =>
      if physical_equal(cached, path) {
        let index = last_query_index.val
        return if index < 0 { None } else { Some(index) }
      }
    None => ()
  }
  let result = match path.find("?") {
    Some(index) =>
      match path.find("#") {
        Some(fragment) => if fragment < index { None } else { Some(index) }
        None => Some(index)
      }
    None => None
  }
  last_query_index_path.val = Some(path)
  match result {
    Some(index) => {
      last_query_index.val = index
      Some(index)
    }
    None => {
      last_query_index.val = -1
      None
    }
  }
}

///|
/// The raw query text after `?`, stopping at a fragment delimiter. The path
/// fragment is never part of the query string, even when a hand-built request
/// carries one.
fn query_source_view(path : String, index : Int32) -> StringView {
  let source = path.view()[index + 1:]
  match source.find("#") {
    Some(fragment) => source[:fragment]
    None => source
  }
}

///|
/// Most recently resolved query string and its parsed map.
let last_query_path : Ref[String?] = Ref(None)

///|
let last_query_start : Ref[Int32] = Ref(-1)

///|
let last_query_map : Ref[Map[String, String]?] = Ref(None)

///|
fn query_map_lookup(path : String, index : Int32) -> Map[String, String] {
  match last_query_path.val {
    Some(cached_path) =>
      if physical_equal(cached_path, path) && last_query_start.val == index {
        match last_query_map.val {
          Some(cached_map) => return cached_map
          None => ()
        }
      }
    None => ()
  }
  let source = query_source_view(path, index)
  let parsed = match queries_cache.get(source) {
    Some(cached) => {
      cache_touch(queries_cache_ages, source)
      cached
    }
    None => {
      let parsed = parse_urlencoded_view(source)
      if source.length() <= PARSE_CACHE_MAX_KEY {
        parse_cache_set(queries_cache, queries_cache_ages, source, parsed)
      }
      parsed
    }
  }
  last_query_path.val = Some(path)
  last_query_start.val = index
  last_query_map.val = Some(parsed)
  parsed
}

///|
/// Most recently resolved multi-value query string and its parsed map.
let last_query_multi_path : Ref[String?] = Ref(None)

///|
let last_query_multi_start : Ref[Int32] = Ref(-1)

///|
let last_query_multi_map : Ref[Map[String, Array[String]]?] = Ref(None)

///|
/// Parsed multi-value query strings, keyed by the raw text after `?`.
let queries_multi_cache : Map[StringView, Map[String, Array[String]]] = Map([])

///|
/// Recency ticks for `queries_multi_cache`.
let queries_multi_cache_ages : Map[StringView, Int32] = Map([])

///|
fn query_multi_lookup(
  path : String,
  index : Int32,
) -> Map[String, Array[String]] {
  match last_query_multi_path.val {
    Some(cached_path) =>
      if physical_equal(cached_path, path) &&
        last_query_multi_start.val == index {
        match last_query_multi_map.val {
          Some(cached_map) => return cached_map
          None => ()
        }
      }
    None => ()
  }
  let source = query_source_view(path, index)
  let parsed = match queries_multi_cache.get(source) {
    Some(cached) => {
      cache_touch(queries_multi_cache_ages, source)
      cached
    }
    None => {
      let parsed = parse_urlencoded_multi(source)
      if source.length() <= PARSE_CACHE_MAX_KEY {
        parse_cache_set(
          queries_multi_cache, queries_multi_cache_ages, source, parsed,
        )
      }
      parsed
    }
  }
  last_query_multi_path.val = Some(path)
  last_query_multi_start.val = index
  last_query_multi_map.val = Some(parsed)
  parsed
}

///|
/// Most recently resolved url-encoded form body and its parsed map.
let last_form_body : Ref[String?] = Ref(None)

///|
let last_form_map : Ref[Map[String, String]?] = Ref(None)

///|
fn form_map_lookup(body : String) -> Map[String, String] {
  match last_form_body.val {
    Some(cached_body) =>
      if physical_equal(cached_body, body) {
        match last_form_map.val {
          Some(cached_map) => return cached_map
          None => ()
        }
      }
    None => ()
  }
  let parsed = parse_urlencoded_view(body.view())
  if body.length() <= PARSE_CACHE_MAX_KEY {
    last_form_body.val = Some(body)
    last_form_map.val = Some(parsed)
  }
  parsed
}

///|
/// Most recently resolved multi-value url-encoded form body and its parsed map.
/// Kept under the same size guard as `form_map_lookup`.
let last_form_values_body : Ref[String?] = Ref(None)

///|
let last_form_values_map : Ref[Map[String, Array[String]]?] = Ref(None)

///|
fn form_values_lookup(body : String) -> Map[String, Array[String]] {
  match last_form_values_body.val {
    Some(cached_body) =>
      if physical_equal(cached_body, body) {
        match last_form_values_map.val {
          Some(cached_map) => return cached_map
          None => ()
        }
      }
    None => ()
  }
  let parsed = parse_urlencoded_multi(body.view())
  if body.length() <= PARSE_CACHE_MAX_KEY {
    last_form_values_body.val = Some(body)
    last_form_values_map.val = Some(parsed)
  }
  parsed
}

///|
/// Most recently resolved multipart body, the content type it was parsed with
/// and its parsed parts.
let last_multipart_body : Ref[String?] = Ref(None)

///|
let last_multipart_content_type : Ref[String?] = Ref(None)

///|
let last_multipart_parts : Ref[Array[MultipartPart]?] = Ref(None)

///|
let last_multipart_raw_body : Ref[String?] = Ref(None)

///|
/// Copy one parsed part so callers get their own header map.
fn copy_multipart_part(part : MultipartPart) -> MultipartPart {
  {
    name: part.name,
    filename: part.filename,
    content_type: part.content_type,
    headers: part.headers.copy(),
    data: part.data,
    data_bytes: part.data_bytes,
  }
}

///|
/// Copy a parsed multipart result, including each part's header map, so callers
/// can mutate the result without disturbing the parse cache.
fn copy_multipart_parts(parts : Array[MultipartPart]) -> Array[MultipartPart] {
  let copy : Array[MultipartPart] = Array(capacity=parts.length())
  for part in parts {
    copy.push(copy_multipart_part(part))
  }
  copy
}

///|
/// Deep-copy a parsed multipart result, including each part's header map, so
/// callers can mutate the result without disturbing the parse cache.
fn clone_multipart_parts(parts : Array[MultipartPart]) -> Array[MultipartPart] {
  let copy : Array[MultipartPart] = Array(capacity=parts.length())
  for part in parts {
    copy.push(copy_multipart_part(part))
  }
  copy
}

///|
fn multipart_parts_lookup(
  body : String,
  content_type : String,
  raw_body~ : String? = None,
) -> Array[MultipartPart]? {
  match last_multipart_body.val {
    Some(cached_body) =>
      if physical_equal(cached_body, body) &&
        last_multipart_content_type.val is Some(cached_type) &&
        cached_type == content_type &&
        last_multipart_raw_body.val == raw_body {
        match last_multipart_parts.val {
          Some(cached) => return Some(cached)
          None => ()
        }
      }
    None => ()
  }
  let parsed = parse_multipart_uncached(body, content_type, raw_body~)
  match parsed {
    Some(parts) =>
      if body.length() <= PARSE_CACHE_MAX_KEY {
        last_multipart_body.val = Some(body)
        last_multipart_content_type.val = Some(content_type)
        last_multipart_parts.val = Some(parts)
        last_multipart_raw_body.val = raw_body
      }
    None => ()
  }
  parsed
}

