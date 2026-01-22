load("@bazel_skylib//:bzl_library.bzl", "bzl_library")
load("@gazelle//:def.bzl", "gazelle_test")

# Prefer generated BUILD files to be called BUILD over BUILD.bazel
# gazelle:build_file_name BUILD,BUILD.bazel
# gazelle:prefix github.com/arkeros/lazy_bazel_env.bzl
# gazelle:exclude bazel-lazy_bazel_env.bzl

gazelle_test(
    name = "gazelle.check",
    size = "small",
    gazelle = "//tools:gazelle_bin",
    workspace = "//:BUILD",
)

bzl_library(
    name = "defs",
    srcs = ["defs.bzl"],
    visibility = ["//visibility:public"],
    deps = ["@bazel_skylib//rules:write_file"],
)

exports_files([
    "lazy_launcher.sh.tpl",
    "lazy_status.sh.tpl",
    "multitool.lock.json",
    "go.mod",
])
