load("@bazel_skylib//:bzl_library.bzl", "bzl_library")

# Prefer generated BUILD files to be called BUILD over BUILD.bazel
# gazelle:build_file_name BUILD,BUILD.bazel
# gazelle:prefix github.com/arkeros/lazy_bazel_env.bzl
# gazelle:exclude bazel-lazy_bazel_env.bzl

bzl_library(
    name = "defs",
    srcs = ["defs.bzl"],
    visibility = ["//visibility:public"],
    deps = ["@bazel_skylib//rules:write_file"],
)

exports_files([
    "eager_launcher.sh.tpl",
    "lazy_launcher.sh.tpl",
    "lazy_status.sh.tpl",
    "multitool.lock.json",
    "go.mod",
])

exports_files(
    ["BUILD"],
    visibility = ["//test:__pkg__"],
)
