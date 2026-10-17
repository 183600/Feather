///|
fn fz_trim_ascii_space(view : StringView) -> StringView {
  let length = view.length()
  let mut start = 0
  while start < length {
    let code = view.unsafe_get(start)
    if code > (' ' : UInt16) {
      break
    }
    if code != (' ' : UInt16) &&
      code != ('\t' : UInt16) &&
      code != ('\n' : UInt16) &&
      code != ('\r' : UInt16) {
      break
    }
    start = start + 1
  }
  let mut end = length
  while end > start {
    let code = view.unsafe_get(end - 1)
    if code > (' ' : UInt16) {
      break
    }
    if code != (' ' : UInt16) &&
      code != ('\t' : UInt16) &&
      code != ('\n' : UInt16) &&
      code != ('\r' : UInt16) {
      break
    }
    end = end - 1
  }
  view[start:end]
}

///|
fn orig_cookie(header : StringView, name : String) -> String? {
  let target = name.view()
  let length = header.length()
  let mut pos = 0
  let mut result : String? = None
  while pos <= length {
    let mut end = pos
    while end < length && header.unsafe_get(end) != (';' : UInt16) {
      end = end + 1
    }
    let pair = fz_trim_ascii_space(header[pos:end])
    if !pair.is_empty() {
      let pair_length = pair.length()
      let mut eq = 0
      while eq < pair_length && pair.unsafe_get(eq) != ('=' : UInt16) {
        eq = eq + 1
      }
      if eq < pair_length {
        let name_view = fz_trim_ascii_space(pair[:eq])
        if !name_view.is_empty() && name_view == target {
          let raw_value = pair[eq + 1:]
          let raw_length = raw_value.length()
          result = Some(
            if raw_length >= 2 &&
              raw_value.unsafe_get(0) == ('"' : UInt16) &&
              raw_value.unsafe_get(raw_length - 1) == ('"' : UInt16) {
              raw_value[1:raw_length - 1].to_owned()
            } else {
              raw_value.to_owned()
            },
          )
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
fn orig_cookies(header : StringView) -> Map[String, String] {
  let cookies : Map[String, String] = Map([], capacity=8)
  let length = header.length()
  let mut pos = 0
  while pos <= length {
    let mut end = pos
    while end < length && header.unsafe_get(end) != (';' : UInt16) {
      end = end + 1
    }
    let mut start = pos
    while start < end {
      let code = header.unsafe_get(start)
      if code > (' ' : UInt16) {
        break
      }
      if code != (' ' : UInt16) &&
        code != ('\t' : UInt16) &&
        code != ('\n' : UInt16) &&
        code != ('\r' : UInt16) {
        break
      }
      start = start + 1
    }
    let mut stop = end
    while stop > start {
      let code = header.unsafe_get(stop - 1)
      if code > (' ' : UInt16) {
        break
      }
      if code != (' ' : UInt16) &&
        code != ('\t' : UInt16) &&
        code != ('\n' : UInt16) &&
        code != ('\r' : UInt16) {
        break
      }
      stop = stop - 1
    }
    if start < stop {
      let mut eq = start
      while eq < stop && header.unsafe_get(eq) != ('=' : UInt16) {
        eq = eq + 1
      }
      if eq < stop {
        let mut name_end = eq
        while name_end > start {
          let code = header.unsafe_get(name_end - 1)
          if code > (' ' : UInt16) {
            break
          }
          if code != (' ' : UInt16) &&
            code != ('\t' : UInt16) &&
            code != ('\n' : UInt16) &&
            code != ('\r' : UInt16) {
            break
          }
          name_end = name_end - 1
        }
        if name_end > start {
          let name = header[start:name_end].to_owned()
          let raw_start = eq + 1
          let value = if stop - raw_start >= 2 &&
            header.unsafe_get(raw_start) == ('"' : UInt16) &&
            header.unsafe_get(stop - 1) == ('"' : UInt16) {
            header[raw_start + 1:stop - 1].to_owned()
          } else {
            header[raw_start:stop].to_owned()
          }
          cookies.set(name, value)
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
fn orig_query_key_matches(
  source : StringView,
  start : Int,
  end : Int,
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
  if !key.contains("%") && !key.contains("+") {
    return false
  }
  name.equal_to_string(url_decode(key.to_owned()))
}

///|
fn orig_query_param(source : StringView, name : String) -> String {
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
      if orig_query_key_matches(source, pair_start, key_end, name_view) {
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
    Some(value) => url_decode(value.to_owned())
    None => ""
  }
}

///|
fn fz_hash(state : Array[Int], salt : Int) -> Int {
  state[0] = ((state[0].to_int64() * 48271L + 1L) % 2147483647L).to_int()
  (state[0] + salt) % 1000003
}

///|
fn fz_char(state : Array[Int], alphabet : Array[Char]) -> Char {
  alphabet[fz_hash(state, 0) % alphabet.length()]
}

///|
fn fz_string(
  state : Array[Int],
  alphabet : Array[Char],
  max_length : Int,
) -> String {
  let builder = StringBuilder()
  let length = fz_hash(state, 7) % (max_length + 1)
  for i = 0; i < length; i = i + 1 {
    builder.write_char(fz_char(state, alphabet))
  }
  builder.to_string()
}

///|
fn fz_check_opt(what : String, sample : String, reference : String?, got : String?) -> Unit {
  match (reference, got) {
    (None, None) => ()
    (Some(a), Some(b)) => if a != b {
      abort("\{what} value differ for \{sample}: ref=[\{a}] got=[\{b}]")
    }
    _ => abort("\{what} presence differ for \{sample}: ref=\{reference} got=\{got}")
  }
}

///|
fn fz_check_str(what : String, sample : String, reference : String, got : String) -> Unit {
  if reference != got {
    abort("\{what} value differ for \{sample}: ref=[\{reference}] got=[\{got}]")
  }
}

///|
fn fz_check_map(
  what : String,
  sample : String,
  reference : Map[String, String],
  got : Map[String, String],
) -> Unit {
  if reference.capacity() != got.capacity() {
    abort(
      "\{what} capacity differ for \{sample}: ref=\{reference.capacity()} got=\{got.capacity()}",
    )
  }
  let ref_pairs = reference.to_array()
  let got_pairs = got.to_array()
  if ref_pairs.length() != got_pairs.length() {
    abort(
      "\{what} size differ for \{sample}: ref=\{ref_pairs.length()} got=\{got_pairs.length()}",
    )
  }
  for i = 0; i < ref_pairs.length(); i = i + 1 {
    let (rk, rv) = ref_pairs[i]
    let (gk, gv) = got_pairs[i]
    if rk != gk || rv != gv {
      abort("\{what} pair \{i} differ for \{sample}: ref=[\{rk}]=[\{rv}] got=[\{gk}]=[\{gv}]")
    }
  }
}

///|
fn fz_names() -> Array[String] {
  [
    "",
    "a",
    "b",
    "x",
    "name",
    "session",
    "tracking",
    "theme",
    "missing",
    "=",
    "\"",
    "%",
    "+",
    " ",
    "a b",
    "a\tb",
    "a%20b",
    "\u{4e16}",
    "lang",
    "empty",
    "quoted",
  ]
}

///|
test "fz-cookie-query" {
  let state : Array[Int] = [987654321]
  let cookie_alphabet : Array[Char] = [
    'a', 'b', 'c', 's', 'e', 't', 'x', '1', '2', '3', ';', ' ', '\t', '\n',
    '\r', '\u{b}', '=', '"', '\\', '%', '+', ',', ':', '\u{4e16}', 'A', 'Z',
  ]
  let query_alphabet : Array[Char] = [
    'a', 'b', 'q', 'x', '1', '2', '&', '=', '%', '+', '2', '0', '5', 'F', '_',
    '-', '.', '?', '\u{4e16}',
  ]
  let names = fz_names()
  for round = 0; round < 2000; round = round + 1 {
    let header = fz_string(state, cookie_alphabet, 48)
    let header_view = header.view()
    let slice_start = fz_hash(state, 3) % (header_view.length() + 1)
    let slice_end = slice_start +
      (fz_hash(state, 5) % (header_view.length() - slice_start + 1))
    let header_slice = header_view[slice_start:slice_end].to_owned()
    let ctx = Context::new({
      method: "GET",
      path: "/",
      headers: Map([("Cookie", header)]),
      body: "",
    })
    let ref_map = orig_cookies(header.view())
    let fz_name = fz_string(state, cookie_alphabet, 6)
    fz_check_opt(
      "cookie-pre-cache",
      header + " / " + fz_name,
      orig_cookie(header.view(), fz_name),
      ctx.cookie(fz_name),
    )
    fz_check_opt(
      "cookie-slice",
      header + " / " + header_slice,
      orig_cookie(header.view(), header_slice),
      ctx.cookie(header_slice),
    )
    fz_check_map("cookies", header, ref_map, ctx.cookies())
    fz_check_opt(
      "cookie-slice-cached",
      header + " / " + header_slice,
      orig_cookie(header.view(), header_slice),
      ctx.cookie(header_slice),
    )
    for name in names {
      fz_check_opt(
        "cookie-cached",
        header + " / " + name,
        orig_cookie(header.view(), name),
        ctx.cookie(name),
      )
    }
    fz_check_opt(
      "cookie-cached-random",
      header + " / " + fz_name,
      orig_cookie(header.view(), fz_name),
      ctx.cookie(fz_name),
    )
    let query = fz_string(state, query_alphabet, 40)
    let query_view = query.view()
    let qs = fz_hash(state, 9) % (query_view.length() + 1)
    let qe = qs + (fz_hash(state, 11) % (query_view.length() - qs + 1))
    let query_slice = query_view[qs:qe].to_owned()
    let path_str = "/p?" + query
    let qctx = Context::new({
      method: "GET",
      path: path_str,
      headers: Map([]),
      body: "",
    })
    let qname = fz_string(state, query_alphabet, 6)
    fz_check_str(
      "query-pre-cache",
      query + " / " + qname,
      orig_query_param(query.view(), qname),
      qctx.query(qname),
    )
    fz_check_str(
      "query-slice",
      query + " / " + query_slice,
      orig_query_param(query.view(), query_slice),
      qctx.query(query_slice),
    )
    fz_check_map(
      "queries",
      query,
      parse_urlencoded(query),
      qctx.queries(),
    )
    fz_check_str(
      "query-slice-cached",
      query + " / " + query_slice,
      orig_query_param(query.view(), query_slice),
      qctx.query(query_slice),
    )
    for name in names {
      fz_check_str(
        "query-cached-2",
        query + " / " + name,
        orig_query_param(query.view(), name),
        qctx.query(name),
      )
    }
  }
  println("fuzz done")
}
