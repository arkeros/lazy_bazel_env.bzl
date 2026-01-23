#!/usr/bin/env bash
# Lazy launcher for {{tool_name}}
# This script invokes `bazel run` for the actual tool on-demand.

set -euo pipefail

# Save original working directory for tools that need it
ORIGINAL_PWD="$PWD"

# Find workspace root
_bazel__get_workspace_path() {
  local workspace=$PWD
  while true; do
    if [ -f "${workspace}/WORKSPACE" ] || \
       [ -f "${workspace}/WORKSPACE.bazel" ] || \
       [ -f "${workspace}/MODULE.bazel" ] || \
       [ -f "${workspace}/REPO.bazel" ]; then
      break
    elif [ -z "$workspace" ] || [ "$workspace" = "/" ]; then
      workspace=$PWD
      break;
    fi
    workspace=${workspace%/*}
  done
  echo "$workspace"
}

workspace_path="$(_bazel__get_workspace_path)"
cd "$workspace_path"

# Use bazelisk if available, otherwise fall back to bazel
if command -v bazelisk &> /dev/null; then
  BAZEL_CMD="bazelisk"
else
  BAZEL_CMD="${BAZEL:-bazel}"
fi

# Run the actual tool target, passing through all arguments
# Use --run_under to cd to the original directory so tools see the correct PWD
# Set BAZEL_BINDIR=. for aspect_rules_js js_binary targets
exec "$BAZEL_CMD" run --tool_tag=lazy_bazel_env:{{tool_name}} --run_under="export BAZEL_BINDIR=. JS_BINARY__NO_CD_BINDIR=1 && cd '$ORIGINAL_PWD' &&" {{tool_target}} -- "$@"
