# Walkthrough — how the code fits together

A guided tour of `nimweb`, a minimal todo app where one Nim codebase powers
both the web server *and* the JavaScript running in your browser. The whole
app — page, API, and frontend logic — is written in Nim.

---

## Big picture

```
      src/types.nim          ← the shared brain
     (C + JS both see this)
            │
   ┌────────┴─────────┐
   ▼                  ▼
src/server.nim     src/app.nim
   │ (nim c)          │ (nim js)
   ▼                  ▼
build/server      public/app.js
   │                   │
   ▼                   ▼
  HTTP server      browser (in runs index.html)
```

- **Server** is built with the C backend (`nim c`) and becomes `build/server`.
- **Frontend** is built with the JavaScript backend (`nim js`) and becomes
  `public/app.js`, which the page loads.
- **`src/types.nim`** is imported by *both*. It is written using only
  backend-agnostic Nim (`std/json`, `std/strutils`), so the same source
  compiles for the C server and for the browser.

That last point is the whole point: the *data shape* (the `Todo` object) and
the *logic* (validation) are defined **once**, and both the server and the
browser run that identical Nim code.

---

## The four Nim source files

### 1. `src/types.nim` — the shared model & logic

Everything here has `*` in front of its name, which exports it to whatever
module imports it. Both `server.nim` and `app.nim` do `import types`.

```nim
type
  Todo* = object
    id*: int
    title*: string
    done*: bool

  TodoInput* = object
    title*: string
    done*: bool
```

`Todo` is the persisted shape (it gets an `id`). `TodoInput` is the shape the
*client sends* when creating or updating — no `id`, since the server assigns
that. Keeping them separate means both ends agree on exactly what the wire
expects.

**Serialization** lives here too, so the JSON format is defined once:

```nim
proc toJson*(t: Todo): JsonNode =
  result = %* {"id": t.id, "title": t.title, "done": t.done}

proc toTodo*(node: JsonNode): Todo = ...   # JSON → Todo
```

The server uses `toJson` to build responses; the browser uses `toTodo` to
parse them. Same code, two ends.

**Logic** is shared as well — here is the single validation rule:

```nim
proc isValidTitle*(title: string): bool =
  title.len in 1 .. 140

proc normalize*(t: TodoInput): TodoInput =
  result.title = t.title.strip
  result.done  = t.done
```

The server rejects bad titles with it, and the browser uses the *same* window
to show instant feedback. There is no second copy to get out of sync.

> Why does `types.nim` only import `std/json` and `std/strutils`?
> It must compile to the browser (JS), which has no sockets, filesystem, or
> DOM. By keeping the shared module free of server-only or browser-only
> imports, the exact same source compiles on both targets.

---

### 2. `src/server.nim` — the backend (C target)

The server uses Nim's `std/asynchttpserver`. It does three jobs:

1. **Serves the page and the frontend JS** from `public/`:

   ```nim
   proc serveStatic(req: Request, path: string) {.async, gcsafe.} =
     case path
     of "/", "/index.html":
       await req.respond(Http200, readFile(assetPath("index.html")), ...)
     of "/app.js":
       await req.respond(Http200, readFile(assetPath("app.js")), ...)
   ```

   So the Nim binary alone can host the entire single-page app.

2. **Runs the REST API** by dispatching on method + path:

   ```nim
   proc handleApi(req, store): tuple[code: HttpCode, body: string] =
     case req.reqMethod
     of HttpGet:   # → list all todos
     of HttpPost:  # → create a todo
     of HttpPut:   # → update a todo by id
     of HttpDelete:# → delete a todo by id
   ```

   Notice `handleApi` is **not** marked `async`. It is a pure function that
   computes `(statusCode, body)` and returns it. The async request callback
   then does the single `await req.respond(...)`. Keeping the request logic
   synchronous makes the ordinary `try/except` error handling work cleanly.

3. **Keeps an in-memory `Store`** — the list of `Todo` objects plus a
   counter for assigning ids:

   ```nim
   type Store = ref object
     todos: seq[Todo]
     nextId: int
   ```

   It seeds two todos on startup so the page isn't empty.

Because `server.nim` does `import types`, all of the above manipulate the
`Todo` type and call the shared `toJson`/`isValidTitle`/`normalize`. The API
shape and the validation are *defined* in `types.nim`, not duplicated here.

---

### 3. `src/app.nim` — the frontend (JS target)

The browser side is also Nim, compiled to JavaScript. It does `import types`,
so it uses the *same* `Todo` type and the *same* serializers.

**Talking to the server.** The page needs `fetch`, but to stay dependency-free
we bind the browser's `XMLHttpRequest` with a tiny FFI wrapper:

```nim
type XHR {.importc: "XMLHttpRequest", nodecl.} = object
proc newXHR(): XHR {.importjs: "new XMLHttpRequest()".}
proc open(x: XHR, reqMeth, url: cstring, isAsync: bool) {.importjs: "#.open(#,#,#)".}
# ...status, responseText, send
```

`importc`/`importjs` tell Nim "call the browser's built-in object, don't
generate one." Then a small `api()` helper wraps GET/POST/PUT/DELETE calls.

**Keeping a local, authoritative copy.** The page stores the todos it fetched
so interactions always know the full, current data:

```nim
var currentTodos: seq[Todo]
```

`reload()` gets `GET /api/todos`, runs each item through the **shared**
`toTodo`, and keeps it in `currentTodos` before handing it to `render()`.

**Rendering.** `render(todos)` builds the `<li>` rows: a checkbox, a title
span, and a delete button, setting `data-id` on each so clicks can be traced
back to a todo.

**Interactions (event delegation).** One `click` listener on the whole list
figures out what was clicked:

```nim
if target.textContent == "✕":
  remove(id)                       # DELETE /api/todos/:id
elif target.type == "checkbox":
  toggle(id, target.checked)       # the box already flipped → new state
else:
  toggle(id, not <stored>.done)    # clicking the text flips stored state
```

`toggle`/`remove` call the appropriate `api(...)` request. `toggle` re-sends
the todo's real title alongside the new `done` state — satisfying the server's
shared validation (a todo needs a valid title).

**Shared validation on the client.** `addTodo()` checks the input locally
first, using the *same* `isValidTitle` the server uses:

```nim
if not isValidTitle(title):
  setError("Title must be 1 to 140 characters.")
  return
```

So the user gets instant feedback, and the server would *also* reject the
same bad input anyway.

---

### 4. `public/index.html` — the shell

Not Nim, but tiny. It defines the static markup (`#form`, `#new-title`,
`#error`, `#list`) and loads the compiled frontend:

```html
<script src="/app.js"></script>
```

Everything dynamic (adding, toggling, deleting, re-rendering) is driven by
`app.js` — the compiled Nim. The server serves this file at `/`.

---

## A click, traced end to end

Say you tick a todo's checkbox:

1. **Browser** flips the checkbox's `checked` to its new value, then fires the
   `click` event.
2. **`src/app.nim`** `onListClick` sees it's a checkbox, reads
   `target.checked` (the *new* state), looks up the todo, and calls
   `toggle(id, newDone)`.
3. `toggle` builds the request body using `%* {"title": ..., "done": ...}`
   and calls `api("PUT", "/api/todos/3", body)`.
4. **Server** (`src/server.nim`) `handleApi` matches `PUT`, parses the JSON
   into a `TodoInput` (shared type), calls `updateTodo` which validates via
   `isValidTitle`, stores the change, and returns the updated
   `Todo.toJson`.
5. `handleApi` returns `(200, json)`, the async callback sends it.
6. Back on the page, `toggle` finishes, calls `reload()`, which fetches the
   list again through the *shared* `toTodo`, and `render()` draws the updated
   row — the checkbox now reflects the new server state.

The same `Todo` type, the same serializers, and the same validation rule were
used at every step on both ends.

---

## Building it

`build.sh` runs the two compiler commands:

```sh
nim js -o:public/app.js src/app.nim     # frontend → browser JS
nim c  -o:build/server  src/server.nim  # backend  → native binary
```

Note both compilations pull in the same `src/types.nim`. Run
`./build/server`, open `http://localhost:8080`, and the single compiled Nim
server serves everything.

---

## Why this design

- **One source of truth.** Add a field to `Todo`, and both the API and the
  browser UI inherit it on the next build — nothing drifts.
- **Shared rules.** Change `isValidTitle`, and both client feedback and server
  enforcement update together.
- **Nim owns the stack.** No separate JS toolchain in the app; the JS is
  generated from the same Nim that wrote the server.