load("@gazelle//:go_tools.bzl", "GO_TOOLS")
load("@lazy_bazel_env.bzl//:defs.bzl", "lazy_bazel_env")

lazy_bazel_env(
    name = "dev",
    tools = {
        "go": "@rules_go//go",
        "gazelle": "//:gazelle",
    } | GO_TOOLS,  # GO_TOOLS is populated when go_deps has dependencies
)
