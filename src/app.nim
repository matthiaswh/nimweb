## app.nim
## The browser frontend. Compiled to JavaScript with the JS backend
## (`nim js`). It imports the exact same `types` module as the server, so the
## Todo shape, JSON (de)serialization and the validation rules are literally
## shared between the C backend and this JS client.

import std/[dom, json, strutils]
import types

const Api = "/api/todos"

# ---------------------------------------------------------------------------
# Minimal XMLHttpRequest binding (browser side only).
# ---------------------------------------------------------------------------
type XHR {.importc: "XMLHttpRequest", nodecl.} = object
proc newXHR(): XHR {.importjs: "new XMLHttpRequest()".}
proc open(x: XHR, reqMeth, url: cstring, isAsync: bool) {.importjs: "#.open(#,#,#)".}
proc setRequestHeader(x: XHR, k, v: cstring) {.importjs: "#.setRequestHeader(#,#)".}
proc send(x: XHR, body: cstring) {.importjs: "#.send(#)".}
proc status(x: XHR): int {.importjs: "#.status".}
proc responseText(x: XHR): cstring {.importjs: "#.responseText".}

# ---------------------------------------------------------------------------
# DOM element helpers
# ---------------------------------------------------------------------------
proc byId(id: cstring): Element = document.getElementById(id)

var listEl, errorEl, titleInput: Element
var currentTodos: seq[Todo]      # local copy so we always have the full,
                                  # authoritative Todo data (incl. title)

proc setError(msg: string) =
  errorEl.textContent = msg

# ---------------------------------------------------------------------------
# API helper — synchronous XHR for a simple, reliable demo.
# Returns a JsonNode or raises on non-2xx / bad JSON.
# ---------------------------------------------------------------------------
proc api(reqMeth, url: string, body = ""): JsonNode =
  let x = newXHR()
  x.open(reqMeth, url, false)
  x.setRequestHeader("Content-Type", "application/json")
  x.send(cstring body)
  let code = x.status
  if code < 200 or code > 299:
    raise newException(CatchableError,
      "HTTP " & $code & ": " & $responseText(x))
  if responseText(x).len == 0:
    return newJNull()
  parseJson($responseText(x))

# ---------------------------------------------------------------------------
# Rendering — builds the todo list DOM from the shared seq[Todo].
# ---------------------------------------------------------------------------
proc render(todos: seq[Todo]) =
  listEl.innerHTML = ""
  for t in todos:
    let li = document.createElement("li")
    if t.done:
      li.setAttribute("class", "done")

    let cb = document.createElement("input")
    cb.setAttribute("type", "checkbox")
    cb.checked = t.done
    cb.setAttribute("data-id", $t.id)

    let span = document.createElement("span")
    span.className = "title"
    span.textContent = t.title
    span.setAttribute("data-id", $t.id)

    let del = document.createElement("button")
    del.textContent = "✕"
    del.setAttribute("data-id", $t.id)

    li.appendChild(cb)
    li.appendChild(span)
    li.appendChild(del)
    listEl.appendChild(li)

# ---------------------------------------------------------------------------
# Actions
# ---------------------------------------------------------------------------
proc reload() =
  try:
    let res = api("GET", Api)
    currentTodos = @[]
    for n in res.items:
      currentTodos.add(n.toTodo)
    render(currentTodos)
    setError("")
  except CatchableError as e:
    setError("Load failed: " & e.msg)

proc addTodo() =
  let title = $titleInput.value
  # Shared validation logic from types.nim — identical to the server rule.
  if not isValidTitle(title):
    setError("Title must be 1 to 140 characters.")
    return
  let payload = %* {"title": title, "done": false}
  try:
    discard api("POST", Api, $payload)
    titleInput.value = ""
    setError("")
    reload()
  except CatchableError as e:
    setError("Could not add todo: " & e.msg)

proc toggle(id: int, done: bool) =
  # The shared Todo model requires a valid title on every update, so send the
  # existing todo's real title together with the new done state.
  var title = ""
  for t in currentTodos:
    if t.id == id:
      # The title already passed validation, so this is safe to re-send.
      title = t.title
      break
  let payload = %* {"title": title, "done": done}
  try:
    discard api("PUT", Api & "/" & $id, $payload)
    reload()
  except CatchableError as e:
    setError("Toggle failed: " & e.msg)

proc remove(id: int) =
  try:
    discard api("DELETE", Api & "/" & $id)
    reload()
  except CatchableError as e:
    setError("Delete failed: " & e.msg)

# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------
proc main() =
  listEl     = byId("list")
  errorEl    = byId("error")
  titleInput = byId("new-title")

  let form = document.getElementById("form")
  form.onsubmit = proc(ev: Event) {.closure.} =
    addTodo()
    ev.preventDefault()

  proc onListClick(ev: Event) =
    let target = Element(ev.target)
    let id = parseInt($target.getAttribute("data-id"))
    if target.textContent == "✕":
      remove(id)
    else:
      # The browser flips the checkbox's checked property before the click
      # event fires, so for a checkbox click target.checked is already the
      # NEW state. For any other click we flip the stored todo instead.
      var newDone: bool
      if target.getAttribute("type") == "checkbox":
        newDone = target.checked
      else:
        for t in currentTodos:
          if t.id == id:
            newDone = not t.done
            break
      toggle(id, newDone)

  listEl.addEventListener("click", onListClick)
  reload()

main()