#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"

# Build the JS frontend from shared Nim + app logic.
nim js -o:public/app.js src/app.nim

# Build the C backend server (serves index.html, app.js and the API).
mkdir -p build
nim c -o:build/server src/server.nim

echo
echo "Build complete."
echo "  frontend: public/app.js (nim js, imports shared src/types.nim)"
echo "  server:   build/server      (nim c,  imports shared src/types.nim)"
echo
echo "Run it with:  ./build/server"
echo "Then open:    http://localhost:8080"