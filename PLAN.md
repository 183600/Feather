下面给你一套**“可以落地实现”的 MoonBit 后端 Web 框架方案**（偏 Gin/Express 风格），底层严格基于 `moonbitlang/async/http` 的 **`@http.run_server` + `@http.ServerConnection`** 来跑服务器、读请求、写响应。核心目标是：**路由 + 中间件 + Context + 统一响应封装 + 可靠的连接内请求循环**。 

---

## 0. 你要依赖的底层能力（框架“地基”）

从官方的 HTTP 文件服务器示例可以确认，`moonbitlang/async/http` 至少提供这些关键 API： 

- `@http.run_server(addr, fn(conn, peer_addr) { ... })`：监听并为每个连接启动处理逻辑（并发处理连接）。 
- `@http.ServerConnection`：
  - `conn.read_request()`：读取一个请求（同一连接可循环读多个请求，支持 keep-alive 的典型形态）。 
  - `conn.skip_request_body()`：跳过请求体（示例里处理 GET 时用它确保后续请求能继续被解析）。 
  - `conn.send_response(code, reason, extra_headers=...)`：发送响应头。 
  - `conn.write(str)`：写响应体（字符串）。 
  - `conn.write_reader(file)`：把文件/reader 流式写出（适合大文件）。 
  - `conn.end_response()`：结束响应。 

另外，MoonBit async 的语义要牢记：**`async fn` 默认会抛错（包括取消）**，错误/取消要设计好传播与兜底。 

> 备注：MoonBit 2025-12 的更新里还提到 HTTP server API 有改进：回调可以“按请求”更直接地处理而无需手动管连接；但你现在要做框架，仍建议用“连接循环”模型兜底最通用。 

---

## 1. 框架的目录/模块划分（建议）

把框架拆成这些包（一个 MoonBit module 下多个 package 都行）：

- `miniweb/http`：Request/Response/Status/Headers 的轻量封装（面向业务）
- `miniweb/router`：路由表 + 匹配算法（Trie）
- `miniweb/middleware`：中间件组合器
- `miniweb/server`：对接 `@http.run_server`，实现连接循环、异常兜底、日志、超时等
- `miniweb/extras`：静态文件、JSON、CORS、日志、panic-recover、request-id 等可选能力

---

## 2. 核心抽象：Handler / Middleware / Context

### 2.1 Handler 类型（最贴近 `ServerConnection`）

建议让 handler 直接拿到 `ctx`，而 `ctx` 内部握着 `conn`，这样响应可以流式写，跟底层一致：

- `Handler = async (Ctx) -> Unit`
- `Middleware = (Handler) -> Handler`

这样中间件本质是“函数包函数”，类似 Koa/Express。

### 2.2 Context（一次请求一个 Context）

`Ctx` 至少要包含：

- `conn : @http.ServerConnection`
- `req : @http.Request`（底层 request 原样保留，减少猜测/映射成本） 
- `params : Map[String, String]`（路由参数）
- `state : Map[String, Json]` 或 `Map[String, Any]`（跨中间件共享；若没有 Any，就用 Json/字符串/自定义联合类型）
- 一些快捷方法：`text/json/file/status(...)`

> 注意：示例里可以直接访问 `request.meth`、`request.path`，所以你的路由匹配至少依赖这两个字段。 

---

## 3. 路由：Trie（支持静态段 / :param / *wildcard）

### 3.1 你需要支持的最小路由能力

- 精确匹配：`/users`
- 参数匹配：`/users/:id`
- 通配：`/static/*path`（用于静态文件或反向代理）

### 3.2 数据结构（示意）

- 每个 HTTP 方法维护一棵 Trie（或方法->root map）
- TrieNode：
  - `static_children : Map[String, TrieNode]`
  - `param_child : TrieNode?`（记录 param 名，例如 `id`）
  - `wildcard_child : TrieNode?`（记录 wildcard 名，例如 `path`）
  - `handler : Handler?`

匹配优先级建议：**静态 > param > wildcard**（符合多数框架直觉）。

---

## 4. Server 侧：连接循环（框架最关键的“骨架”）

官方示例的核心是：

- 对每个连接 `for { ... }` 循环
- 每轮 `conn.read_request()`
- 不需要的 body 用 `conn.skip_request_body()`
- `conn.send_response` + `conn.write` + `conn.end_response` 

你的框架也应该这样做，只是把“处理逻辑”替换成“路由分发 + 中间件链”。

### 4.1 伪代码骨架（可直接照着写）

> 下面代码是“方案级骨架”，具体类型名/语法细节你按实际 MoonBit 包结构微调即可。

```mbt
// miniweb/server.mbt
pub type Handler = async (Ctx) -> Unit
pub type Middleware = (Handler) -> Handler

pub struct App {
  router : Router
  middlewares : Array[Middleware]
}

pub async fn App::serve(self : App, addr : @socket.Addr) -> Unit {
  @http.run_server(addr, fn(conn, _peer) {
    handle_connection(self, conn)
  })
}

async fn handle_connection(app : App, conn : @http.ServerConnection) -> Unit {
  for {
    let req = conn.read_request()
    // 关键点：不管业务读不读 body，最终必须“消耗/丢弃”它，
    // 否则同一连接上的下一次 read_request 可能无法继续正常工作。
    // 官方示例在处理 GET 时明确调用 skip_request_body。 
    defer conn.skip_request_body()

    try {
      let (handler_opt, params) = app.router.match(req.meth, req.path)
      match handler_opt {
        None => default_404(conn)
        Some(handler) => {
          let ctx = Ctx::new(conn, req, params)
          let h = apply_middleware(app.middlewares, handler)
          h(ctx)
        }
      }
    } catch {
      err => {
        // 这里建议：区分“取消错误”和普通错误，取消要继续向上抛，别吞掉。
        // MoonBit async 默认可抛错（取消也是通过抛错实现的一类）。 
        internal_500(conn, err)
      }
    }
  }
}

fn apply_middleware(mws : Array[Middleware], last : Handler) -> Handler {
  let mut h = last
  // 反向包裹：mw1(mw2(mw3(handler)))
  for i = mws.length() - 1; i >= 0; i = i - 1 {
    h = mws
  }
  h
}
```

---

## 5. Response 封装：把 `send_response/write/end_response` 做成“业务友好 API”

你至少需要三类输出：

1. `text`
2. `json`
3. `file/stream`（用 `write_reader`）

官方示例中，写文件是：

- `conn.send_response(200, "OK", extra_headers={ "Content-Type": content_type })`
- `conn.write_reader(file)`
- `conn.end_response()` 

### 5.1 建议实现：`miniweb/http/response.mbt`

```mbt
pub fn send_text(
  conn : @http.ServerConnection,
  code : Int,
  reason : String,
  body : String,
  headers? : Map[String, String]
) -> Unit {
  let extra = headers.unwrap_or({ "Content-Type": "text/plain; charset=utf-8" })
  conn.send_response(code, reason, extra_headers=extra)
  conn.write(body)
  conn.end_response()
}

pub fn send_json(
  conn : @http.ServerConnection,
  code : Int,
  reason : String,
  json : Json
) -> Unit {
  conn.send_response(code, reason, extra_headers={
    "Content-Type": "application/json; charset=utf-8"
  })
  conn.write(json.stringify())
  conn.end_response()
}

pub async fn send_file(
  conn : @http.ServerConnection,
  file : @fs.File,
  content_type : String
) -> Unit {
  conn.send_response(200, "OK", extra_headers={ "Content-Type": content_type })
  conn.write_reader(file) // 流式输出大文件 
  conn.end_response()
}
```

> 上面用到的 `send_response/write/end_response/write_reader` 都是示例里确凿存在的调用方式。 

---

## 6. 中间件：建议先实现 4 个“最值回票价”的

### 6.1 Recover（把异常变 500）

- 业务 handler 抛错 => 500
- 取消错误（比如超时取消）=> 不要吞（否则会造成“看似成功但任务实际应停止”的诡异行为）

MoonBit async 的取消/错误语义你要尊重它：`async fn` 默认可抛错。 

### 6.2 Logging（请求日志）

在进入 handler 前记录 start；handler 后记录 status、耗时（耗时可用 `@async.now()` 一类；你也可以自己计时）。

### 6.3 Timeout（每个请求超时）

可以用 `@async.with_timeout(...)` 把 handler 包起来（structured concurrency / task group 能把取消正确传播下去）。 

### 6.4 CORS（简单版）

预检 OPTIONS 直接返回；其余请求追加 `Access-Control-*` 头。

---

## 7. 请求体（Body）怎么设计：务实做法

你已经能确定 **“不读 body 时必须 skip”**。   
但“如何读 body”的具体 API 在你给我的材料里没直接出现，所以我建议框架第一版这样做：

- **框架层不强行抽象 body 读取**（避免猜 API）
- 只做两件事：
  1. 在请求处理结束 `defer conn.skip_request_body()`，确保连接可继续复用。 
  2. 给业务留一个“逃生口”：`ctx.conn` 暴露出来，业务若需要读取 body，就直接用 `moonbitlang/async/http` 提供的 body 读取能力（以你本地 moondoc/IDE 类型提示为准）。

等你确认了 `@http` 对请求体的正式 API（例如是否提供 `read_request_body()` / `body_reader` / `req.body` 之类），再把它封成：

- `ctx.body_bytes(limit~)`
- `ctx.body_text(limit~, charset~)`
- `ctx.json[T]()`（基于 `@json.from_json`）

---

## 8. 一个最小用例：Hello + JSON + 静态文件（框架对外长相）

你最终希望业务代码像这样：

```mbt
async fn main {
  let app = App::new()
    ..use(mw_recover())
    ..use(mw_logger())
    ..get("/hello", fn(ctx) { ctx.text(200, "OK", "hello") })
    ..get("/api/ping", fn(ctx) { ctx.json(200, "OK", { "ok": true }) })
    ..get("/static/*path", serve_static("./public"))

  app.serve(@socket.Addr::parse("[::]:8000"))
}
```

底层真正写回去的动作仍然是示例里的三连：`send_response + write + end_response` 或 `write_reader`。 

---

## 9. 后续增强路线（做成“真框架”的关键点）

按优先级从高到低：

1. **稳定的 body 读取抽象**（一旦你确认了 `@http` 的 body API，就把 JSON/form/multipart 做起来）
2. **更强路由**：路由分组、路由命名、反向生成 URL
3. **更好错误模型**：`HttpError(status, message, payload)`；统一错误响应（JSON problem details）
4. **连接级/请求级资源管理**：比如在 `Ctx` 里提供 `defer` 栈（请求结束自动执行清理）
5. **WebSocket**：`moonbitlang/async` 已经有 websocket 包（可以把 upgrade 流程接进去做实时 API）。 

---

### 结论

这套方案的关键点是：**不要试图绕开 `@http.ServerConnection` 的“连接循环”模型**，而是顺着它做：  
- 每连接一个循环 `read_request()` → 路由 → 中间件 → handler → `end_response()`  
- 不读 body 必须 `skip_request_body()` 保证 keep-alive 下一轮还能读到请求   
- 响应只封装写法，不改变底层流式能力（`write_reader` 是你做静态文件/大文件的核心优势）   
