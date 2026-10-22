///|
test "static directory redirect keeps query and fragment after the slash" {
  assert_eq(append_trailing_slash("/guide?tab=1"), "/guide/?tab=1")
  assert_eq(append_trailing_slash("/guide#top"), "/guide/#top")
  assert_eq(
    append_trailing_slash("/guide?tab=1#top"),
    "/guide/?tab=1#top",
  )
  assert_eq(
    append_trailing_slash("/guide#top?tab=1"),
    "/guide/#top?tab=1",
  )
  assert_eq(append_trailing_slash("/guide"), "/guide/")
}
