test "Router::new creates empty router" {
  let router = Router::new()
  assert_eq!(router.routes.is_empty(), true)
}

test "Router::add_route adds static route" {
  let router = Router::new()
  let handler : Handler = fn(ctx) { }
  
  router.add_route("GET", "/users", handler)
  
  let (matched_handler, params) = router.match("GET", "/users")
  assert_ne!(matched_handler, None)
  assert_eq!(params.is_empty(), true)
}

test "Router::add_route adds param route" {
  let router = Router::new()
  let handler : Handler = fn(ctx) { }
  
  router.add_route("GET", "/users/:id", handler)
  
  let (matched_handler, params) = router.match("GET", "/users/123")
  assert_ne!(matched_handler, None)
  assert_eq!(params["id"], "123")
}

test "Router::add_route adds wildcard route" {
  let router = Router::new()
  let handler : Handler = fn(ctx) { }
  
  router.add_route("GET", "/static/*path", handler)
  
  let (matched_handler, params) = router.match("GET", "/static/css/style.css")
  assert_ne!(matched_handler, None)
  assert_eq!(params["path"], "css/style.css")
}

test "Router::match returns None for non-existent route" {
  let router = Router::new()
  let handler : Handler = fn(ctx) { }
  
  router.add_route("GET", "/users", handler)
  
  let (matched_handler, params) = router.match("GET", "/posts")
  assert_eq!(matched_handler, None)
}

test "Router::match respects method distinction" {
  let router = Router::new()
  let get_handler : Handler = fn(ctx) { }
  let post_handler : Handler = fn(ctx) { }
  
  router.add_route("GET", "/users", get_handler)
  router.add_route("POST", "/users", post_handler)
  
  let (get_matched, _) = router.match("GET", "/users")
  let (post_matched, _) = router.match("POST", "/users")
  let (put_matched, _) = router.match("PUT", "/users")
  
  assert_ne!(get_matched, None)
  assert_ne!(post_matched, None)
  assert_eq!(put_matched, None)
}

test "parse_path correctly splits paths" {
  let parts1 = parse_path("/users")
  assert_eq!(parts1.length(), 1)
  assert_eq!(parts1[0], "users")
  
  let parts2 = parse_path("/users/123/posts")
  assert_eq!(parts2.length(), 3)
  assert_eq!(parts2[0], "users")
  assert_eq!(parts2[1], "123")
  assert_eq!(parts2[2], "posts")
  
  let parts3 = parse_path("/")
  assert_eq!(parts3.length(), 0)
}
