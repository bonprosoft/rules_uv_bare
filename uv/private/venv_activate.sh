#!/bin/bash
set -euo pipefail
WDIR="$(head -1 "$1")"
echo "$WDIR/.venv/bin/activate"
