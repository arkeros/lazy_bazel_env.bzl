# Examples

Each subdirectory is a standalone Bazel workspace demonstrating different use cases.

## Setup

Each example includes a `.envrc` file for direnv integration. After building, run `direnv allow` to add tools to your PATH.

## basic

Minimal example with `buildifier` from `buildifier_prebuilt`.

```bash
cd basic
bazel run //tools:dev
direnv allow
buildifier --version
```

## go

Go development environment with `go` and `gazelle`.

```bash
cd go
bazel run //tools:dev
direnv allow
go version
gazelle --help
```

## multitool

Uses `rules_multitool` to manage external tool binaries (e.g., `kubectl`).

```bash
cd multitool
bazel run //tools:dev
direnv allow
kubectl version --client
```
