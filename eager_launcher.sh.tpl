#!/usr/bin/env bash
# Eager launcher for {{tool_name}}
# This tool is resolved from toolchain Make variables at build time.

set -euo pipefail

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

case "${BASH_SOURCE[0]}" in
  /*) own_path="${BASH_SOURCE[0]}" ;;
  *) own_path="$PWD/${BASH_SOURCE[0]}" ;;
esac
own_dir="$(dirname "$own_path")"
own_name="$(basename "$own_path")"

# Check if tool is still in the bazel_env
if ! grep -q -F "$own_name" "$own_dir/_all_tools.txt"; then
  echo "ERROR: $own_name has been removed from bazel_env, run 'bazel run {{bazel_env_label}}' to remove it from PATH." >&2
  exit 1
fi

workspace_path="$(_bazel__get_workspace_path)"

# Set up an environment similar to 'bazel run'
export RUNFILES_DIR="${own_path}.runfiles"
export RUNFILES="${RUNFILES_DIR}"
export JAVA_RUNFILES="${RUNFILES_DIR}"
export PYTHON_RUNFILES="${RUNFILES_DIR}"
export JS_BINARY__NO_CD_BINDIR=1
export BAZEL_BINDIR='.'

BUILD_WORKING_DIRECTORY="$(pwd)"
export BUILD_WORKING_DIRECTORY

BUILD_WORKSPACE_DIRECTORY="$workspace_path"
export BUILD_WORKSPACE_DIRECTORY

# Resolve the tool path
case "{{rlocation_path}}" in
  /*) bin_path="{{rlocation_path}}" ;;
  *) bin_path="$RUNFILES_DIR/{{rlocation_path}}" ;;
esac

exec "$bin_path" "$@"
