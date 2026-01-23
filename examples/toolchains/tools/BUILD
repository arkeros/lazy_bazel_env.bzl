load("@lazy_bazel_env.bzl//:defs.bzl", "lazy_bazel_env")

lazy_bazel_env(
    name = "dev",
    toolchains = {
        "jq": "@jq_toolchains//:resolved_toolchain",
    },
    tools = {
        "jq": "$(JQ_BIN)",
    },
)
