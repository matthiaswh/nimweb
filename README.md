# nimweb — one Nim stack, shared model, two backends

A minimal single-page todo app that demonstrates Nim owning the entire stack:

- **Backend**: a Nim HTTP server (C backend) that serves the page, the
  frontend JS, and a JSON REST API.
- **Frontend**: Nim compiled to **JavaScript** (`nim js`) for the browser.
- **Shared**: the todo data model **and** its business logic live in a single
  file, `src/types.nim`, compiled into **both** binaries.

## Why types.nim is special

`src/types.nim` holds:
- the `Todo` / `TodoInput` object shape,
- the JSON (de)serialization (the exact wire format),
- validation (`isValidTitle`) and normalization logic.

It imports only `std/json` and pure-Nim stdlib, so it compiles unchanged to
both the C target (server) and the JS target (frontend). The server rejects
invalid titles with the very same predicate the client uses for instant
feedback — one source of truth, no drift.

```
            src/types.nim  (shared: shape + serialization + logic)
                 │                        │
                 ▼                        ▼
      src/server.nim                src/app.nim
           │                            │
           ▼                            ▼
    nim c  (C backend)           nim js (JS backend)
           │                            │
    build/server               public/app.js (in browser)
```

## Files

| File                | Compiles to   | Role                                   |
|---------------------|---------------|----------------------------------------|
| `src/types.nim`     | C **and** JS  | shared data model + logic (both ends)  |
| `src/server.nim`    | C             | HTTP server + REST API                 |
| `src/app.nim`       | JS            | browser UI, uses shared `types`        |
| `public/index.html` | served        | the single page                         |
| `public/app.js`     | (generated)   | compiled frontend, served by server    |
| `build.sh`          | —             | builds both targets                    |

## Build & run

Requires Nim 2.x (no third-party packages).

```sh
./build.sh          # compiles public/app.js (nim js) and build/server (nim c)
./build/server      # starts on http://localhost:8080
```

Open <http://localhost:8080>. The same `types.nim` drives what you see in the
browser and what the API accepts.

## API

| Method | Path            | Body                          | Result              |
|--------|-----------------|-------------------------------|---------------------|
| GET    | `/api/todos`    | —                             | `[ {id,title,done} ]`|
| POST   | `/api/todos`    | `{"title": "...", "done": false}` | created todo (`201`) |
| PUT    | `/api/todos/:id`| `{"title": "...", "done": true}` | updated todo      |
| DELETE | `/api/todos/:id`| —                             | `204`               |

Invalid titles (`isValidTitle`) are rejected with `400 Bad Request`.