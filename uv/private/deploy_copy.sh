#!/bin/bash
set -euo pipefail

DEPLOY_DIR="$1"
shift

if [ $# -eq 0 ]; then
    echo "Usage: bazel run <target> -- /path/to/output" >&2
    exit 1
fi

OUTPUT_DIR="$1"
if [ -n "${BUILD_WORKING_DIRECTORY:-}" ]; then
    case "$OUTPUT_DIR" in
        /*) ;;
        *) OUTPUT_DIR="$BUILD_WORKING_DIRECTORY/$OUTPUT_DIR" ;;
    esac
fi

mkdir -p "$OUTPUT_DIR"
cp -RPp "$DEPLOY_DIR"/* "$OUTPUT_DIR/"
# Bazel action outputs are read-only (555/444)
# Restore owner-write so the deployed tree behaves like a normal directory.
chmod -R u+w "$OUTPUT_DIR"
echo "Deployed to $OUTPUT_DIR"
