"""Lazy bazel_env - tools are compiled on-demand when first invoked.

Unlike the standard bazel_env which builds all tools upfront, this version
creates lightweight wrapper scripts that invoke `bazel run` for the actual
target only when the tool is called.

This makes `bazel run //tools:bazel_env` nearly instant, at the cost of
a small delay on first invocation of each tool.
"""

load("@bazel_skylib//rules:write_file.bzl", "write_file")

# Transition settings for stable output directory
# Only modify compilation_mode, cpu, and platform_suffix to avoid ST hash in output path
_COMPILATION_MODE_SETTING = "//command_line_option:compilation_mode"
_CPU_SETTING = "//command_line_option:cpu"
_PLATFORM_SUFFIX_SETTING = "//command_line_option:platform_suffix"

def _flip_output_dir_impl(settings, _attr):
    """Forces a stable output directory: lazy_bazel_env-opt."""
    return {
        _COMPILATION_MODE_SETTING: "opt",
        _CPU_SETTING: "lazy_bazel_env",
        _PLATFORM_SUFFIX_SETTING: "",
    }

_flip_output_dir = transition(
    implementation = _flip_output_dir_impl,
    inputs = [],
    outputs = [_COMPILATION_MODE_SETTING, _CPU_SETTING, _PLATFORM_SUFFIX_SETTING],
)

def _lazy_tool_impl(ctx):
    """Implementation for a single lazy tool wrapper."""
    out = ctx.actions.declare_file(ctx.label.name)

    ctx.actions.expand_template(
        template = ctx.file._launcher,
        output = out,
        is_executable = True,
        substitutions = {
            "{{tool_name}}": ctx.attr.tool_name,
            "{{tool_target}}": ctx.attr.tool_target,
            "{{bazel_env_label}}": ctx.attr.bazel_env_label,
        },
    )

    return [
        DefaultInfo(
            executable = out,
            runfiles = ctx.runfiles(),
        ),
    ]

_lazy_tool = rule(
    implementation = _lazy_tool_impl,
    cfg = _flip_output_dir,
    attrs = {
        "tool_name": attr.string(mandatory = True),
        "tool_target": attr.string(mandatory = True),
        "bazel_env_label": attr.string(mandatory = True),
        "_launcher": attr.label(
            allow_single_file = True,
            default = Label("//:lazy_launcher.sh.tpl"),
        ),
        "_allowlist_function_transition": attr.label(
            default = "@bazel_tools//tools/allowlists/function_transition_allowlist",
        ),
    },
    executable = True,
)

def _lazy_bazel_env_impl(ctx):
    """Implementation for the main lazy_bazel_env rule."""
    status_script = ctx.actions.declare_file(ctx.label.name + ".sh")

    all_names = [t.basename for t in ctx.files.tool_wrappers]
    tool_names = [name for name in all_names if not name.startswith("_")]
    tools_list = "\n".join(["  * " + name for name in sorted(tool_names)])

    ctx.actions.expand_template(
        template = ctx.file._status,
        output = status_script,
        is_executable = True,
        substitutions = {
            "{{name}}": ctx.label.name,
            "{{label}}": str(ctx.label).removeprefix("@@"),
            "{{bin_dir}}": ctx.files.tool_wrappers[0].dirname if ctx.files.tool_wrappers else "",
            "{{tools}}": tools_list,
            "{{tools_regex}}": "\\|".join(all_names + ["_all_tools.txt", "_bazel_env_marker"]),
        },
    )

    return [
        DefaultInfo(
            executable = status_script,
            files = depset(ctx.files.tool_wrappers),
            runfiles = ctx.runfiles(files = ctx.files.tool_wrappers),
        ),
    ]

_lazy_bazel_env_rule = rule(
    implementation = _lazy_bazel_env_impl,
    cfg = _flip_output_dir,
    attrs = {
        "tool_wrappers": attr.label_list(allow_files = True),
        "_status": attr.label(
            allow_single_file = True,
            default = Label("//:lazy_status.sh.tpl"),
        ),
        "_allowlist_function_transition": attr.label(
            default = "@bazel_tools//tools/allowlists/function_transition_allowlist",
        ),
    },
    executable = True,
)

_FORBIDDEN_TOOL_NAMES = ["direnv", "bazel", "bazelisk"]

def lazy_bazel_env(*, name, tools = {}, toolchains = {}, **kwargs):
    """Creates a lazy bazel_env where tools are compiled on-demand.

    Unlike the standard bazel_env, this version does NOT build tools upfront.
    Instead, it creates lightweight wrapper scripts that invoke `bazel run`
    for each tool on first invocation.

    Benefits:
    - `bazel run //tools:lazy_bazel_env` is nearly instant
    - Tools are only compiled when actually used
    - Great for large tool sets where you only use a few tools at a time

    Tradeoffs:
    - First invocation of each tool has a small delay for compilation
    - Wrapper scripts add a tiny overhead on each invocation

    Args:
        name: The name of the rule.
        tools: A dictionary mapping tool names to their Bazel targets.
        toolchains: Currently ignored (for API compatibility).
        **kwargs: Additional arguments passed to the main rule.
    """
    tool_wrappers = []
    label = str(native.package_relative_label(name))

    # Create marker file for PATH detection
    marker_name = name + "/bin/_bazel_env_marker_" + name
    write_file(
        name = marker_name,
        out = marker_name + ".sh",
        content = ["#!/usr/bin/env bash", "exit 0"],
        is_executable = True,
        visibility = ["//visibility:private"],
        tags = ["manual"],
    )
    tool_wrappers.append(marker_name)

    # Create all_tools file
    all_tools_file = name + "/bin/_all_tools"
    write_file(
        name = all_tools_file,
        out = all_tools_file + ".txt",
        content = [" " + " ".join(tools.keys()) + " "],
        is_executable = False,
        visibility = ["//visibility:private"],
        tags = ["manual"],
    )
    tool_wrappers.append(all_tools_file)

    for tool_name, tool_target in tools.items():
        if not tool_name:
            fail("empty tool names are not allowed")
        if tool_name in _FORBIDDEN_TOOL_NAMES:
            fail("tool name '{}' is forbidden".format(tool_name))

        # Skip Make variable expansions - those need eager resolution
        if type(tool_target) == type("") and "$" in tool_target:
            # For now, skip these - they require toolchain resolution
            continue

        wrapper_name = name + "/bin/" + tool_name
        _lazy_tool(
            name = wrapper_name,
            tool_name = tool_name,
            tool_target = str(tool_target),
            bazel_env_label = label,
            visibility = ["//visibility:private"],
            tags = ["manual"],
        )
        tool_wrappers.append(wrapper_name)

    _lazy_bazel_env_rule(
        name = name,
        tool_wrappers = tool_wrappers,
        **kwargs
    )
