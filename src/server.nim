## server.nim
## The todo backend. Owns the whole stack:
##   * serves the single-page index.html and the browser app.js
##   * serves the JSON REST API
##
## Built with the C backend. The data model & logic come from the shared
## `types` module — the exact same source the frontend compiles from.

import std/[asynchttpserver, asyncdispatch, json, strutils, os, net]
import types

const HttpPort = 8080

type
  Store = ref object
    todos: seq[Todo]
    nextId: int

# The SPA assets (index.html, app.js) live in `public/` and are served from
# disk on each request. The Nim binary still owns & serves the whole page.
proc assetPath(rel: string): string =
  currentSourcePath().parentDir / ".." / "public" / rel

proc newStore(): Store =
  new(result)
  result.nextId = 1

proc addTodo(s: Store, inp: TodoInput): Todo =
  let i = inp.normalize
  if not isValidTitle(i.title):
    raise newException(ValueError,
      "invalid title: must be 1..140 chars, got '" & i.title & "'")
  result = Todo(id: s.nextId, title: i.title, done: i.done)
  s.todos.add(result)
  inc s.nextId

proc updateTodo(s: Store, id: int, inp: TodoInput): Todo =
  let i = inp.normalize
  if not isValidTitle(i.title):
    raise newException(ValueError,
      "invalid title: must be 1..140 chars, got '" & i.title & "'")
  for t in s.todos.mitems:
    if t.id == id:
      t.title = i.title
      t.done  = i.done
      return t
  raise newException(KeyError, "todo not found: " & $id)

proc errorNode(msg: string): JsonNode =
  %* {"error": msg}

proc handleApi(req: Request, store: Store): tuple[code: HttpCode, body: string] =
  ## Pure synchronous request handling — regular try/except works cleanly.
  ## (Returns the response; the async wrapper does the single send.)
  let path = req.url.path
  let reqMeth = req.reqMethod

  result = (Http404, $errorNode("not found"))

  try:
    case reqMeth
    of HttpGet:
      if path == "/api/todos":
        result = (Http200, $(store.todos.toJson))
    of HttpPost:
      if path == "/api/todos":
        let saved = store.addTodo(parseJson(req.body).toTodoInput)
        result = (Http201, $(saved.toJson))
    of HttpPut:
      let idPart = path.strip(chars = {'/'})
      if idPart.startsWith("api/todos/"):
        let id = parseInt(idPart["api/todos/".len .. ^1])
        let saved = store.updateTodo(id, parseJson(req.body).toTodoInput)
        result = (Http200, $(saved.toJson))
    of HttpDelete:
      let idPart = path.strip(chars = {'/'})
      if idPart.startsWith("api/todos/"):
        let id = parseInt(idPart["api/todos/".len .. ^1])
        var found = -1
        for idx, t in store.todos:
          if t.id == id:
            found = idx
            break
        if found >= 0:
          store.todos.delete(found)
          result = (Http204, "")
    else:
      result = (Http405, $errorNode("method not allowed"))
  except ValueError:
    result = (Http400, $errorNode("bad request: " & getCurrentExceptionMsg()))
  except KeyError:
    result = (Http404, $errorNode("not found"))

proc serveStatic(req: Request, path: string) {.async, gcsafe.} =
  case path
  of "/", "/index.html":
    let headers = newHttpHeaders([("Content-Type", "text/html")])
    await req.respond(Http200, readFile(assetPath("index.html")), headers)
  of "/app.js":
    let headers = newHttpHeaders([("Content-Type", "application/javascript")])
    await req.respond(Http200, readFile(assetPath("app.js")), headers)
  else:
    await req.respond(Http404, $errorNode("not found"))

proc main() {.async.} =
  let store = newStore()
  # a couple of seed todos so the page isn't empty on first load
  discard store.addTodo(TodoInput(title: "Welcome — this reads from the shared Nim model", done: false))
  discard store.addTodo(TodoInput(title: "Compile the frontend from the same types.nim", done: true))

  let server = newAsyncHttpServer()

  proc cb(req: Request) {.async, gcsafe.} =
    if req.url.path.startsWith("/api/"):
      let r = handleApi(req, store)
      if r.body.len > 0:
        let h = newHttpHeaders([("Content-Type", "application/json")])
        await req.respond(r.code, r.body, h)
      else:
        await req.respond(r.code, "")
    else:
      await serveStatic(req, req.url.path)

  echo "nimweb todo server listening on http://localhost:" & $HttpPort
  await server.serve(Port(HttpPort), cb, "127.0.0.1")

when isMainModule:
  waitFor main()