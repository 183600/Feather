///|
test "cache control honors backslash escapes in quoted arguments" {
  // The escaped quote must not close the quoted-string: the comma after it is
  // still inside the argument, so `no-store` there is not a directive.
  assert_false(
    cache_control_has_directive(
      "foo=\"a\\\", no-store, b\"".view(),
      "no-store".view(),
    ),
  )
  // The closing quote after the escaped one does end the argument, so the
  // comma after it separates a real directive.
  assert_true(
    cache_control_has_directive(
      "x=\"a\\\", b\", no-store".view(),
      "no-store".view(),
    ),
  )
}

///|
test "cache control directive matching around plain quoted arguments" {
  assert_true(cache_control_has_directive("no-store".view(), "no-store".view()))
  assert_true(
    cache_control_has_directive("max-age=0, no-store".view(), "no-store".view()),
  )
  assert_true(
    cache_control_has_directive("foo=\"a,b\", no-store".view(), "no-store".view()),
  )
  assert_false(
    cache_control_has_directive("foo=\"no-store\"".view(), "no-store".view()),
  )
  assert_false(
    cache_control_has_directive("private=\"no-store\"".view(), "no-store".view()),
  )
  assert_false(
    cache_control_has_directive("no-storex".view(), "no-store".view()),
  )
  assert_true(
    cache_control_has_directive("no-store=\"x\"".view(), "no-store".view()),
  )
}
