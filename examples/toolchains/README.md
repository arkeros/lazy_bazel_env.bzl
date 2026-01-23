# Toolchains Example

Example using `jq` from `jq.bzl` toolchain with Make variable resolution.

## Overview

The `lazy_bazel_env` rule supports two types of tools:

1. **Lazy tools** - Regular Bazel targets that are compiled on-demand when first invoked
2. **Eager tools** - Tools resolved from toolchain Make variables (e.g., `$(JQ_BIN)`) at build time

This example shows how to expose the `jq` binary from the `jq.bzl` toolchain.

## Setup

```bash
bazel run //tools:dev
direnv allow
```

## Usage

Once set up, `jq` is available in your PATH:

```bash
jq --version
echo '{"foo": "bar"}' | jq '.foo'
```

## How It Works

- **Toolchains** are exposed as symlinks in the `toolchains/` directory, pointing to the toolchain's repository root
- **Make variable tools** like `$(JQ_BIN)` are resolved at build time using the toolchain's `TemplateVariableInfo`
- The resolved tool path is embedded in a launcher script that sets up the proper runfiles environment
