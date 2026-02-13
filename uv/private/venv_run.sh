#!/bin/bash
set -euo pipefail
WDIR="$(head -1 "$1")"
shift

export PATH="$WDIR/.venv/bin:$PATH"
cd "${BUILD_WORKING_DIRECTORY:-$PWD}"
exec "$@"
