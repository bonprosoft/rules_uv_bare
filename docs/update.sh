#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
bazel build //docs:rules_doc
cp -f bazel-bin/docs/rules_generated.md docs/rules.md
echo "Done. Verify with: bazel test //docs:rules_doc_test"
