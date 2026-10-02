## types.nim
## Shared data model + logic for the todo app.
##
## This module is the single source of truth for the Todo shape and the
## business logic. It is compiled to BOTH backends from the same source:
##   * server.nim (C target) `import types`
##   * app.nim    (JS target) `import types`
##
## It therefore only uses `std/json` and backend-agnostic Nim. No DOM, no
## sockets, no filesystem — keeping it portable to the JavaScript target.

import std/[json, strutils]

type
  Todo* = object
    id*: int
    title*: string
    done*: bool

  TodoInput* = object
    ## Payload shape accepted when creating or updating a todo.
    ## (Kept distinct from Todo so the client and server agree on the wire.)
    title*: string
    done*: bool

# ---------------------------------------------------------------------------
# Serialization — shared by both, so the exact JSON shape is defined once.
# ---------------------------------------------------------------------------

proc toJson*(t: Todo): JsonNode =
  result = %* {
    "id":    t.id,
    "title": t.title,
    "done":  t.done,
  }

proc toJson*(todos: seq[Todo]): JsonNode =
  result = newJArray()
  for t in todos:
    result.add(t.toJson)

proc toTodo*(node: JsonNode): Todo =
  ## Parse a Todo from JSON. Uses safe field access; missing/invalid fields
  ## throw JsonKindError / JsonNodeError exactly like the JS side would if it
  ## used the same procs.
  result.id    = node["id"].getInt
  result.title = node["title"].getStr
  result.done  = node["done"].getBool

proc toTodoInput*(node: JsonNode): TodoInput =
  result.title = node["title"].getStr
  result.done  = node["done"].getBool

# ---------------------------------------------------------------------------
# Business logic — shared, so both ends always agree (e.g. validation).
# ---------------------------------------------------------------------------

proc isValidTitle*(title: string): bool =
  ## Shared validation rule. Both server (rejects bad input) and client
  ## (gives immediate feedback) use the exact same predicate.
  title.len in 1 .. 140

proc normalize*(t: TodoInput): TodoInput =
  ## Sanitize input exactly the same way on both ends.
  result.title = t.title.strip
  result.done  = t.done