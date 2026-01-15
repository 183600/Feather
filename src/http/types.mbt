pub struct Ctx {
  conn : @http.ServerConnection
  req : @http.Request
  params : Map[String, String]
  state : Map[String, String]
}

pub fn Ctx::new(
  conn : @http.ServerConnection,
  req : @http.Request,
  params : Map[String, String]
) -> Ctx {
  { conn, req, params, state: Map::new() }
}

pub fn Ctx::text(
  self : Ctx,
  code : Int,
  reason : String,
  body : String
) -> Unit {
  self.conn.send_response(code, reason, extra_headers={
    "Content-Type": "text/plain; charset=utf-8"
  })
  self.conn.write(body)
  self.conn.end_response()
}

pub fn Ctx::json(
  self : Ctx,
  code : Int,
  reason : String,
  json : Json
) -> Unit {
  self.conn.send_response(code, reason, extra_headers={
    "Content-Type": "application/json; charset=utf-8"
  })
  self.conn.write(json.stringify())
  self.conn.end_response()
}

pub fn Ctx::status(self : Ctx, code : Int, reason : String) -> Unit {
  self.conn.send_response(code, reason, extra_headers={})
  self.conn.end_response()
}
