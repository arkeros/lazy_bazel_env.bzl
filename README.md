# lazy_bazel_env.bzl

A Bazel rule that creates a lazy development environment where tools are compiled on-demand when first invoked.

Unlike the standard `bazel_env` which builds all tools upfront, `lazy_bazel_env` creates lightweight wrapper scripts that invoke `bazel run` for the actual target only when the tool is called. This makes `bazel run //tools:lazy_bazel_env` nearly instant.

## Benefits

- `bazel run //tools:lazy_bazel_env` is nearly instant
- Tools are only compiled when actually used
- Great for large tool sets where you only use a few tools at a time
- Always up-to-date: since wrappers invoke `bazel run`, any changes to the underlying tool (source code, dependencies, etc.) are automatically detected and rebuilt on next invocation

## Tradeoffs

- First invocation of each tool has a small delay for compilation
- Wrapper scripts add a tiny overhead on each invocation

## Installation

Add to your `MODULE.bazel`:

```starlark
bazel_dep(name = "lazy_bazel_env.bzl", version = "0.0.0")
git_override(
    module_name = "lazy_bazel_env.bzl",
    remote = "https://github.com/arkeros/lazy_bazel_env.bzl.git",
    commit = "<commit>",
)
```

## Usage

In your `BUILD.bazel`:

```starlark
load("@lazy_bazel_env.bzl//:defs.bzl", "lazy_bazel_env")

lazy_bazel_env(
    name = "lazy_bazel_env",
    tools = {
        "buildifier": "@com_github_bazelbuild_buildtools//buildifier",
        "gazelle": "//:gazelle",
        "go": "@rules_go//go",
    },
)
```

Then run:

```bash
bazel run //tools:lazy_bazel_env
```

This creates wrapper scripts in `bazel-bin/tools/lazy_bazel_env/bin/` that you can add to your PATH.

## direnv Integration

The recommended way to use `lazy_bazel_env` is with [direnv](https://direnv.net/). Add to your `.envrc`:

```bash
# Use the stable output path (not bazel-bin which changes with each build config)
watch_file bazel-out/lazy_bazel_env-opt/bin/tools/lazy_bazel_env/bin
PATH_add bazel-out/lazy_bazel_env-opt/bin/tools/lazy_bazel_env/bin
if [[ ! -d bazel-out/lazy_bazel_env-opt/bin/tools/lazy_bazel_env/bin ]]; then
  log_error "ERROR[lazy_bazel_env]: Run 'bazel run //tools:lazy_bazel_env' to regenerate bin directory"
fi
```

Then run `direnv allow` to enable it.

## How It Works

1. `lazy_bazel_env` generates lightweight bash wrapper scripts for each tool
2. When you run a tool (e.g., `buildifier`), the wrapper script executes `bazel run @com_github_bazelbuild_buildtools//buildifier -- "$@"`
3. The tool is compiled on first invocation and cached by Bazel for subsequent runs
4. A transition ensures stable output paths so the bin directory location doesn't change

## License

MIT
