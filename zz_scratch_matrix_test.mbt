///|
fn zz_matrix_wildcard_encode(value : String) -> String {
  let builder = StringBuilder::new()
  let view = value.view()
  let mut start = 0
  for i = 0; i < view.length(); i = i + 1 {
    if view[i] == '/' {
      builder.write_string(@feather.url_encode(view[start:i].to_owned()))
      builder.write_char('/')
      start = i + 1
    }
  }
  if start < view.length() {
    builder.write_string(@feather.url_encode(view[start:].to_owned()))
  }
  builder.to_string()
}

///|
test "zz-roundtrip-matrix" {
  let values = ["", "a", "a b", "a/b", "%", "+", "a+b", "中", "a#b", "..", "."]
  let cases = [
    ("param", "/p/:v"),
    ("param2", "/a/:x/b/:y"),
    ("wild", "/w/*rest"),
    ("pwild", "/u/:id/*rest"),
  ]
  for case in cases {
    let (name, path) = case
    let router = @feather.create_router()
    router.add_named_route(name, "GET", path, fn(_ctx) { () })
    let names : Array[String] = []
    for seg in path.view().split("/") {
      if seg.has_prefix(":") || seg.has_prefix("*") {
        names.push(seg[1:].to_owned())
      }
    }
    for value in values {
      let params : Map[String, String] = Map([])
      for pname in names {
        params.set(pname, value)
      }
      let url = router.url_for(name, params~)
      if value == "" && path.contains(":") {
        assert_eq(url, None)
        continue
      }
      let url = url.unwrap()
      match router.route("GET", url) {
        @feather.RouteFound(route) =>
          for pname in names {
            let got = route.params.get(pname).unwrap_or("<missing>")
            let is_wild = path.has_suffix("*" + names[names.length() - 1])
            let want = if is_wild && pname == names[names.length() - 1] {
              zz_matrix_wildcard_encode(value)
            } else {
              @feather.url_encode(value)
            }
            assert_eq(got, want)
          }
        _ => abort("no route for \{name} value=\{value} url=\{url}")
      }
    }
  }
}
