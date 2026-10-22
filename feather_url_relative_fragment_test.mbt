///|
test "relative full_url drops a fragment and keeps the query" {
  let ctx = @feather.Context::new({
    method: "GET",
    path: "/items?page=2#top",
    headers: Map([]),
    body: "",
  })
  assert_eq(ctx.full_url(), "/items?page=2")
}
