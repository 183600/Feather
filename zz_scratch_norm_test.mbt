///|
test "zz-nested-group-prefixes-normalize" {
  let app = @feather.App::new()
  let api = app.group("//api").group("v2//users")
  ignore(api.route_named("u", "GET", "/:id", fn(ctx) { ctx.text(200, "u") }))
  assert_eq(app.url_for("u", params={ "id": "9" }), Some("/api/v2/users/9"))
  let response = app.respond({
    method: "GET",
    path: "//api/v2/users/9",
    headers: Map([]),
    body: "",
  })
  assert_eq(response.status, 200)
  assert_eq(response.body, "u")
  let static = @feather.App::new().static_files("//", "/srv/www")
  assert_eq(static.static_file_for("/a.txt"), Some("/srv/www/a.txt"))
  assert_eq(static.static_file_for("/"), Some("/srv/www/index.html"))
}
