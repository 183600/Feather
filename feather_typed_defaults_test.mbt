///|
fn td_query_context(query : String) -> @feather.Context {
  @feather.Context::new({
    method: "GET",
    path: "/search?" + query,
    headers: Map([]),
    body: "",
  })
}

///|
fn td_header_context(pairs : Map[String, String]) -> @feather.Context {
  @feather.Context::new({
    method: "GET",
    path: "/",
    headers: pairs,
    body: "",
  })
}

///|
fn td_form_context(body : String, content_type : String) -> @feather.Context {
  @feather.Context::new({
    method: "POST",
    path: "/submit",
    headers: Map([("Content-Type", content_type)]),
    body,
  })
}

///|

test "param_int_default returns the parsed value and the default otherwise" {
  let app = @feather.App::new()
    .get("/item/:n", fn(ctx) {
      ctx.text(
        200,
        ctx.param_int_default("n", -1).to_string() +
        ":" +
        ctx.param_int_default("missing", 7).to_string(),
      )
    })
  let response = app.respond({
    method: "GET",
    path: "/item/42",
    headers: Map([]),
    body: "",
  })
  assert_eq(response.body, "42:7")
}

test "param_int64_default returns the parsed value and the default otherwise" {
  let app = @feather.App::new()
    .get("/item/:n", fn(ctx) {
      ctx.text(
        200,
        ctx.param_int64_default("n", 0L).to_string() +
        ":" +
        ctx.param_int64_default("missing", 9L).to_string(),
      )
    })
  let response = app.respond({
    method: "GET",
    path: "/item/42",
    headers: Map([]),
    body: "",
  })
  assert_eq(response.body, "42:9")
}

test "param_bool_default accepts true/false/1/0 and defaults otherwise" {
  let app = @feather.App::new()
    .get("/flag/:v", fn(ctx) {
      ctx.text(
        200,
        ctx.param_bool_default("v", false).to_string() +
        ":" +
        ctx.param_bool_default("missing", true).to_string(),
      )
    })
  let yes = app.respond({
    method: "GET",
    path: "/flag/true",
    headers: Map([]),
    body: "",
  })
  let no = app.respond({
    method: "GET",
    path: "/flag/0",
    headers: Map([]),
    body: "",
  })
  let missing = app.respond({
    method: "GET",
    path: "/flag/nope",
    headers: Map([]),
    body: "",
  })
  assert_eq(yes.body, "true:true")
  assert_eq(no.body, "false:true")
  assert_eq(missing.body, "false:true")
}

test "param_float_default parses finite decimals and defaults otherwise" {
  let app = @feather.App::new()
    .get("/ratio/:v", fn(ctx) {
      ctx.text(
        200,
        ctx.param_float_default("v", -1.5).to_string() +
        ":" +
        ctx.param_float_default("missing", 3.25).to_string(),
      )
    })
  let ok = app.respond({
    method: "GET",
    path: "/ratio/1.25",
    headers: Map([]),
    body: "",
  })
  let bad = app.respond({
    method: "GET",
    path: "/ratio/nan",
    headers: Map([]),
    body: "",
  })
  assert_eq(ok.body, "1.25:3.25")
  assert_eq(bad.body, "-1.5:3.25")
}

///|

test "query_int_default returns the parsed value and the default otherwise" {
  let ctx = td_query_context("n=42&bad=abc")
  assert_eq(ctx.query_int_default("n", -1), 42)
  assert_eq(ctx.query_int_default("bad", -1), -1)
  assert_eq(ctx.query_int_default("missing", -1), -1)
  assert_eq(ctx.query_int_default("", -1), -1)
}

test "query_int64_default returns the parsed value and the default otherwise" {
  let ctx = td_query_context("n=9223372036854775807&bad=abc")
  assert_eq(
    ctx.query_int64_default("n", 0L),
    9223372036854775807L,
  )
  assert_eq(ctx.query_int64_default("bad", 5L), 5L)
  assert_eq(ctx.query_int64_default("missing", 5L), 5L)
}

test "query_bool_default accepts true/false/1/0 and defaults otherwise" {
  let ctx = td_query_context("v=true&other=0&bad=yes")
  assert_true(ctx.query_bool_default("v", false))
  assert_false(ctx.query_bool_default("other", true))
  assert_false(ctx.query_bool_default("bad", false))
  assert_true(ctx.query_bool_default("missing", true))
}

test "query_float_default parses finite decimals and defaults otherwise" {
  let ctx = td_query_context("v=1.25&bad=nan&exp=-2e3")
  assert_eq(ctx.query_float_default("v", -1.5), 1.25)
  assert_eq(ctx.query_float_default("bad", -1.5), -1.5)
  assert_eq(ctx.query_float_default("exp", 0.0), -2000.0)
  assert_eq(ctx.query_float_default("missing", 3.25), 3.25)
}

///|

test "header_int_default trims whitespace and defaults otherwise" {
  let ctx = td_header_context(Map([
    ("X-Count", " 42 "),
    ("X-Bad", "12x"),
  ]))
  assert_eq(ctx.header_int_default("x-count", -1), 42)
  assert_eq(ctx.header_int_default("X-BAD", -1), -1)
  assert_eq(ctx.header_int_default("X-Missing", -1), -1)
}

test "header_int64_default returns the parsed value and the default otherwise" {
  let ctx = td_header_context(Map([
    ("X-Big", "9223372036854775807"),
    ("X-Bad", "12x"),
  ]))
  assert_eq(
    ctx.header_int64_default("X-Big", 0L),
    9223372036854775807L,
  )
  assert_eq(ctx.header_int64_default("X-Bad", 5L), 5L)
  assert_eq(ctx.header_int64_default("X-Missing", 5L), 5L)
}

test "header_bool_default accepts true/false/1/0 and defaults otherwise" {
  let ctx = td_header_context(Map([
    ("X-True", "true"),
    ("X-False", "0"),
    ("X-One", " 1 "),
    ("X-Bad", "yes"),
  ]))
  assert_true(ctx.header_bool_default("X-True", false))
  assert_true(ctx.header_bool_default("X-One", false))
  assert_false(ctx.header_bool_default("X-False", true))
  assert_true(ctx.header_bool_default("X-Bad", true))
  assert_true(ctx.header_bool_default("X-Missing", true))
}

test "header_float_default parses finite decimals and defaults otherwise" {
  let ctx = td_header_context(Map([
    ("X-Ratio", " 1.25 "),
    ("X-Exp", "-2e3"),
    ("X-Nan", "nan"),
    ("X-Bad", "1.2.3"),
  ]))
  assert_eq(ctx.header_float_default("X-Ratio", 0.0), 1.25)
  assert_eq(ctx.header_float_default("X-Exp", 0.0), -2000.0)
  assert_eq(ctx.header_float_default("X-Nan", 3.25), 3.25)
  assert_eq(ctx.header_float_default("X-Bad", 3.25), 3.25)
  assert_eq(ctx.header_float_default("X-Missing", 3.25), 3.25)
}

///|

test "form_int_default reads urlencoded fields and defaults" {
  let form = td_form_context("n=42&bad=abc", "application/x-www-form-urlencoded")
  assert_eq(form.form_int_default("n", -1), 42)
  assert_eq(form.form_int_default("bad", -1), -1)
  assert_eq(form.form_int_default("missing", -1), -1)

  let json = td_form_context("n=42", "application/json")
  assert_eq(json.form_int_default("n", -1), -1)
}

test "form_int64_default reads urlencoded fields and defaults" {
  let form = td_form_context("n=9223372036854775807", "application/x-www-form-urlencoded")
  assert_eq(
    form.form_int64_default("n", 0L),
    9223372036854775807L,
  )
  assert_eq(form.form_int64_default("missing", 5L), 5L)
}

test "form_bool_default reads urlencoded fields and defaults" {
  let form = td_form_context("v=true&other=0&bad=yes", "application/x-www-form-urlencoded")
  assert_true(form.form_bool_default("v", false))
  assert_false(form.form_bool_default("other", true))
  assert_true(form.form_bool_default("bad", true))
  assert_false(form.form_bool_default("missing", false))
}

test "form_float_default reads urlencoded fields and defaults" {
  let form = td_form_context("v=1.25&bad=nan", "application/x-www-form-urlencoded")
  assert_eq(form.form_float_default("v", -1.5), 1.25)
  assert_eq(form.form_float_default("bad", -1.5), -1.5)
  assert_eq(form.form_float_default("missing", 3.25), 3.25)
}

///|

test "typed defaults do not confuse present-empty values with absence" {
  let ctx = td_query_context("n=")
  assert_eq(ctx.query_int_default("n", -1), -1)
  assert_eq(ctx.query_bool_default("n", true), true)
  assert_eq(ctx.query_float_default("n", 0.0), 0.0)

  let form = td_form_context("n=", "application/x-www-form-urlencoded")
  assert_eq(form.form_int_default("n", -1), -1)
  assert_eq(form.form_bool_default("n", true), true)
  assert_eq(form.form_float_default("n", 0.0), 0.0)
}
