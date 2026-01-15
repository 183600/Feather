pub typealias Middleware = (Handler) -> Handler

pub fn recover() -> Middleware {
  fn(next) {
    fn(ctx) {
      try {
        next(ctx)
      } catch {
        err => {
          ctx.json(500, "Internal Server Error", {
            "error": "Internal Server Error",
            "message": err.to_string()
          })
        }
      }
    }
  }
}

pub fn logger() -> Middleware {
  fn(next) {
    fn(ctx) {
      let start = @time.now()
      println("[START] {ctx.req.meth} {ctx.req.path}")
      
      next(ctx)
      
      let duration = @time.now() - start
      println("[END] {ctx.req.meth} {ctx.req.path} - {duration}ms")
    }
  }
}

pub fn timeout(ms : Int) -> Middleware {
  fn(next) {
    fn(ctx) {
      @async.with_timeout(ms, fn() { next(ctx) }) catch {
        _ => {
          ctx.json(408, "Request Timeout", {
            "error": "Request timeout"
          })
        }
      }
    }
  }
}

pub fn cors() -> Middleware {
  fn(next) {
    fn(ctx) {
      if ctx.req.meth == "OPTIONS" {
        ctx.conn.send_response(200, "OK", extra_headers={
          "Access-Control-Allow-Origin": "*",
          "Access-Control-Allow-Methods": "GET, POST, PUT, DELETE, OPTIONS",
          "Access-Control-Allow-Headers": "Content-Type, Authorization"
        })
        ctx.conn.end_response()
      } else {
        ctx.conn.send_response(ctx.req.meth, ctx.req.path, extra_headers={
          "Access-Control-Allow-Origin": "*"
        })
        next(ctx)
      }
    }
  }
}

pub fn apply_middleware(mws : Array[Middleware], handler : Handler) -> Handler {
  let mut h = handler
  for i = mws.length() - 1; i >= 0; i = i - 1 {
    h = mws[i](h)
  }
  h
}
