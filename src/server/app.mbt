pub struct App {
  router : Router
  middlewares : Array[Middleware]
}

pub fn App::new() -> App {
  {
    router: Router::new(),
    middlewares: Array::make(0)
  }
}

pub fn App::use(self : App, mw : Middleware) -> App {
  self.middlewares.push(mw)
  self
}

pub fn App::get(self : App, path : String, handler : Handler) -> App {
  self.router.add_route("GET", path, handler)
  self
}

pub fn App::post(self : App, path : String, handler : Handler) -> App {
  self.router.add_route("POST", path, handler)
  self
}

pub fn App::put(self : App, path : String, handler : Handler) -> App {
  self.router.add_route("PUT", path, handler)
  self
}

pub fn App::delete(self : App, path : String, handler : Handler) -> App {
  self.router.add_route("DELETE", path, handler)
  self
}

pub async fn App::serve(self : App, addr : @socket.Addr) -> Unit {
  @http.run_server(addr, fn(conn, _peer) {
    handle_connection(self, conn)
  })
}

async fn handle_connection(app : App, conn : @http.ServerConnection) -> Unit {
  for {
    let req = conn.read_request()
    defer conn.skip_request_body()
    
    try {
      let (handler_opt, params) = app.router.match(req.meth, req.path)
      match handler_opt {
        None => {
          conn.send_response(404, "Not Found", extra_headers={
            "Content-Type": "text/plain; charset=utf-8"
          })
          conn.write("404 Not Found")
          conn.end_response()
        }
        Some(handler) => {
          let ctx = Ctx::new(conn, req, params)
          let wrapped_handler = apply_middleware(app.middlewares, handler)
          wrapped_handler(ctx)
        }
      }
    } catch {
      err => {
        conn.send_response(500, "Internal Server Error", extra_headers={
          "Content-Type": "application/json; charset=utf-8"
        })
        conn.write({ "error": "Internal Server Error", "message": err.to_string() }.stringify())
        conn.end_response()
      }
    }
  }
}

fn default_404(conn : @http.ServerConnection) -> Unit {
  conn.send_response(404, "Not Found", extra_headers={
    "Content-Type": "text/plain; charset=utf-8"
  })
  conn.write("404 Not Found")
  conn.end_response()
}

fn internal_500(conn : @http.ServerConnection, err : Error) -> Unit {
  conn.send_response(500, "Internal Server Error", extra_headers={
    "Content-Type": "application/json; charset=utf-8"
  })
  conn.write({ "error": "Internal Server Error", "message": err.to_string() }.stringify())
  conn.end_response()
}
