///|
test "filename* escapes RFC 5987 separators" {
  let ctx = @feather.create_context()
  ctx.attachment("报告's*star.txt")
  assert_eq(
    ctx.response.headers.get("Content-Disposition"),
    Some("attachment; filename=\"__'s*star.txt\"; filename*=UTF-8''%E6%8A%A5%E5%91%8A%27s%2Astar.txt"),
  )
}
