///|
fn zz_rand2(state : Ref[Int]) -> Int {
  state.val = (state.val * 31 + 7) % 1000003
  state.val
}

///|
fn zz_segs(path : StringView) -> Array[StringView] {
  let out : Array[StringView] = []
  for seg in path.split("/") {
    if !seg.is_empty() {
      out.push(seg)
    }
  }
  out
}

///|
fn zz_kind(seg : StringView) -> Int {
  if seg.has_prefix(":") {
    1
  } else if seg.has_prefix("*") {
    0
  } else {
    2
  }
}

///|
fn zz_pattern_matches(
  pattern : Array[StringView],
  path : Array[StringView],
) -> Bool {
  let mut i = 0
  while i < pattern.length() {
    let kind = zz_kind(pattern[i])
    if kind == 0 {
      return true
    }
    if i >= path.length() {
      return false
    }
    if kind == 2 && pattern[i] != path[i] {
      return false
    }
    i = i + 1
  }
  i == path.length()
}

///|
fn zz_extract(
  pattern : Array[StringView],
  path : Array[StringView],
) -> (Map[String, String], String) {
  let params : Map[String, String] = Map([])
  let mut wildcard = ""
  for i = 0; i < pattern.length(); i = i + 1 {
    let kind = zz_kind(pattern[i])
    if kind == 1 {
      params.set(pattern[i][1:].to_owned(), path[i].to_owned())
    } else if kind == 0 {
      wildcard = path[i:].map(fn(s) { s.to_owned() }).join("/")
      if pattern[i].length() > 1 {
        params.set(pattern[i][1:].to_owned(), wildcard)
      }
      break
    }
  }
  (params, wildcard)
}

///|
fn zz_better(p1 : Array[StringView], p2 : Array[StringView]) -> Bool {
  let n = if p1.length() < p2.length() { p1.length() } else { p2.length() }
  for i = 0; i < n; i = i + 1 {
    let k1 = zz_kind(p1[i])
    let k2 = zz_kind(p2[i])
    if k1 != k2 {
      return k1 > k2
    }
  }
  if p1.length() == p2.length() {
    return false
  }
  let longer = if p1.length() > p2.length() { p1 } else { p2 }
  let shorter_is_p1 = p1.length() < p2.length()
  if zz_kind(longer[n]) == 0 {
    return shorter_is_p1
  }
  false
}

///|
test "zz-fuzz-router" {
  let patterns = [
    "/", "/a", "/b", "/a/b", "/a/c", "/a/b/c", "/a/b/d", "/:x", "/:x/b",
    "/a/:p", "/a/b/:p", "/a/:p/c", "/a/*w", "/a/b/*w", "/*w", "/:x/*w",
  ]
  let parts = ["a", "b", "c", "d"]
  let paths : Array[String] = ["/"]
  for x in parts {
    paths.push("/" + x)
    for y in parts {
      paths.push("/" + x + "/" + y)
      for z in parts {
        paths.push("/" + x + "/" + y + "/" + z)
      }
    }
  }
  let state = Ref(2024)
  let mut failures = 0
  for round = 0; round < 60; round = round + 1 {
    let router = @feather.create_router()
    let active : Array[String] = []
    for pat in patterns {
      if zz_rand2(state) % 2 == 0 {
        active.push(pat)
        router.add_route("GET", pat, fn(_ctx) { () })
      }
    }
    let pattern_views : Array[Array[StringView]] = []
    for pat in active {
      pattern_views.push(zz_segs(pat.view()))
    }
    for path in paths {
      let path_segs = zz_segs(path.view())
      let mut best = -1
      for i = 0; i < pattern_views.length(); i = i + 1 {
        if zz_pattern_matches(pattern_views[i], path_segs) {
          if best < 0 || zz_better(pattern_views[i], pattern_views[best]) {
            best = i
          }
        }
      }
      let outcome = router.route("GET", path)
      let trie_path = match outcome {
        @feather.RouteFound(route) => Some(route.path)
        @feather.RouteMethodNotAllowed(_) => None
        @feather.RouteNotFound => None
      }
      if best < 0 {
        if trie_path is Some(_) {
          failures = failures + 1
        }
      } else {
        let expected = active[best]
        match trie_path {
          Some(p) =>
            if p != expected {
              failures = failures + 1
            } else {
              let route = match outcome {
                @feather.RouteFound(route) => route
                _ => abort("unreachable")
              }
              let (params, _) = zz_extract(pattern_views[best], path_segs)
              for name, value in params {
                match route.params.get(name) {
                  Some(got) =>
                    if got != value {
                      failures = failures + 1
                    }
                  None => failures = failures + 1
                }
              }
            }
          None => failures = failures + 1
        }
      }
    }
  }
  assert_eq(failures, 0)
}
