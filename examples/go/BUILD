load("@gazelle//:def.bzl", "DEFAULT_LANGUAGES", "gazelle", "gazelle_binary", "gazelle_test")

# Prefer generated BUILD files to be called BUILD over BUILD.bazel
# gazelle:build_file_name BUILD,BUILD.bazel
# gazelle:prefix github.com/arkeros/lay_bazel_env.bzl/examples/go

gazelle_binary(
    name = "gazelle_bin",
    languages = DEFAULT_LANGUAGES + [
        "@bazel_skylib_gazelle_plugin//bzl",
    ],
)

gazelle(
    name = "gazelle",
    gazelle = ":gazelle_bin",
)

gazelle_test(
    name = "gazelle.check",
    size = "small",
    gazelle = ":gazelle_bin",
    workspace = "//:BUILD",
)
