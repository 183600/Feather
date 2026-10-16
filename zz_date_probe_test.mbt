///|
fn zz_date_rand(state : Ref[Int]) -> Int {
  state.val = (state.val * 1103515245 + 12345) % 2147483647
  state.val
}

///|
test "zz-format-http-date-known-values" {
  let cases = [
    (0L, "Thu, 01 Jan 1970 00:00:00 GMT"),
    (784111777L, "Sun, 06 Nov 1994 08:49:37 GMT"),
    (951782400L, "Tue, 29 Feb 2000 00:00:00 GMT"),
    (1078012800L, "Sun, 29 Feb 2004 00:00:00 GMT"),
    (2147483647L, "Tue, 19 Jan 2038 03:14:07 GMT"),
    (-1L, "Wed, 31 Dec 1969 23:59:59 GMT"),
    (-86400L, "Wed, 31 Dec 1969 00:00:00 GMT"),
    (-2208988800L, "Mon, 01 Jan 1900 00:00:00 GMT"),
    (-62135596800L, "Mon, 01 Jan 0001 00:00:00 GMT"),
  ]
  for case in cases {
    let (seconds, expected) = case
    assert_eq(format_http_date(seconds), expected)
  }
}

///|
test "zz-date-roundtrip-fuzz" {
  let state = Ref(20261016)
  let mut failures = 0
  let check = fn(t : Int64) {
    let formatted = format_http_date(t)
    match parse_http_date(formatted) {
      Some(parsed) =>
        if parsed != t {
          failures = failures + 1
          println("date mismatch: \{t} -> \{formatted} -> \{parsed}")
        }
      None => {
        failures = failures + 1
        println("date unparsable: \{t} -> \{formatted}")
      }
    }
  }
  for i = 0; i < 3000; i = i + 1 {
    let value = zz_date_rand(state).to_int64() * 100000L +
      zz_date_rand(state).to_int64()
    check(value.abs())
  }
  assert_eq(failures, 0)
}
