"""Lazy bazel_env - tools are compiled on-demand when first invoked.

Unlike the standard bazel_env which builds all tools upfront, this version
creates lightweight wrapper scripts that invoke `bazel run` for the actual
target only when the tool is called.

This makes `bazel run //tools:bazel_env` nearly instant, at the cost of
a small delay on first invocation of each tool.
"""

load("@bazel_skylib//rules:write_file.bzl", "write_file")

# Make variable expansion (based on bazel_env.bzl)
def _expand_make_variables(expression, vars):
    """Expands Make variables like $(FOO) in expression using vars dict.

    Args:
        expression: String potentially containing $(VAR) patterns
        vars: Dict mapping variable names to their values

    Returns:
        Tuple of (expanded_string, dict_of_used_vars)
    """
    idx = 0
    last_make_var_end = 0
    result = []
    n = len(expression)
    vars_used = {}
    for _ in range(n):
        if idx >= n:
            break
        if expression[idx] != "$":
            idx += 1
            continue

        idx += 1

        # $$ is escaped $
        if idx < n and expression[idx] == "$":
            idx += 1
            result.append(expression[last_make_var_end:idx - 1])
            last_make_var_end = idx
        elif idx < n and expression[idx] == "(":
            make_var_start = idx
            make_var_end = make_var_start
            for j in range(idx + 1, n):
                if expression[j] == ")":
                    make_var_end = j
                    break

            if make_var_start != make_var_end:
                result.append(expression[last_make_var_end:make_var_start - 1])
                make_var = expression[make_var_start + 1:make_var_end]

                if " " in make_var:
                    fail("location expansion such as '$(rlocationpath ...)' is not supported: $({})".format(make_var))
                exp = vars.get(make_var)
                if exp == None:
                    fail("variable $({}) is not defined".format(make_var))
                vars_used[make_var] = True
                result.append(exp)

                idx = make_var_end + 1
                last_make_var_end = idx

    if last_make_var_end < n:
        result.append(expression[last_make_var_end:n])

    return "".join(result), vars_used

def _rlocation_path(ctx, file):
    """Returns the rlocation path for a file."""
    if file.short_path.startswith("../"):
        return file.short_path[3:]
    else:
        return ctx.workspace_name + "/" + file.short_path

def _heuristic_rlocation_path(ctx, path):
    """Converts a path to an rlocation path using heuristics."""
    if path.startswith("bazel-out/"):
        # Skip over bazel-out/<cfg>/bin.
        path = "/".join(path.split("/")[3:])

    if path.startswith("external/"):
        return path.removeprefix("external/")
    elif path.startswith("../"):
        return path[3:]
    elif path.startswith("/"):
        return path
    elif not path.startswith(ctx.workspace_name + "/"):
        return ctx.workspace_name + "/" + path
    else:
        return path

# Provider to extract toolchain info via aspect
_ToolchainInfo = provider(fields = ["files", "label", "variables"])

def _extract_toolchain_info_impl(target, _ctx):
    """Aspect implementation to extract toolchain info."""
    return [
        _ToolchainInfo(
            files = target[DefaultInfo].files,
            label = target.label,
            variables = target[platform_common.TemplateVariableInfo].variables if platform_common.TemplateVariableInfo in target else {},
        ),
    ]

_extract_toolchain_info = aspect(
    implementation = _extract_toolchain_info_impl,
)

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

# Eager tool rule - for tools defined via Make variables (resolved from toolchains)
def _eager_tool_impl(ctx):
    """Implementation for a tool resolved from toolchain Make variables."""
    out = ctx.actions.declare_file(ctx.label.name)

    # Collect all Make variables from toolchains
    vars = {
        k: v
        for toolchain in ctx.attr.toolchain_targets
        for k, v in toolchain[_ToolchainInfo].variables.items()
    }

    # Expand Make variables in the path
    raw_path, used_vars = _expand_make_variables(ctx.attr.path, vars)
    rlocation_path = _heuristic_rlocation_path(ctx, raw_path)

    # Collect runfiles from used toolchains
    transitive_files = []
    for toolchain in ctx.attr.toolchain_targets:
        for key in toolchain[_ToolchainInfo].variables.keys():
            if key in used_vars:
                transitive_files.append(toolchain[_ToolchainInfo].files)
    runfiles = ctx.runfiles(transitive_files = depset(transitive = transitive_files))

    ctx.actions.expand_template(
        template = ctx.file._launcher,
        output = out,
        is_executable = True,
        substitutions = {
            "{{tool_name}}": ctx.attr.tool_name,
            "{{rlocation_path}}": rlocation_path,
            "{{bazel_env_label}}": ctx.attr.bazel_env_label,
        },
    )

    return [
        DefaultInfo(
            executable = out,
            runfiles = runfiles,
        ),
    ]

_eager_tool = rule(
    implementation = _eager_tool_impl,
    cfg = _flip_output_dir,
    attrs = {
        "tool_name": attr.string(mandatory = True),
        "path": attr.string(mandatory = True),
        "bazel_env_label": attr.string(mandatory = True),
        "toolchain_targets": attr.label_list(
            cfg = _flip_output_dir,
            aspects = [_extract_toolchain_info],
        ),
        "_launcher": attr.label(
            allow_single_file = True,
            default = Label("//:eager_launcher.sh.tpl"),
        ),
        "_allowlist_function_transition": attr.label(
            default = "@bazel_tools//tools/allowlists/function_transition_allowlist",
        ),
    },
    executable = True,
)

# Toolchain symlink rule - creates a symlink to the toolchain's repository
def _toolchain_symlink_impl(ctx):
    """Creates a symlink to the toolchain's repository root."""
    toolchain_name = ctx.label.name.rpartition("/")[-1]

    toolchain_info = ctx.attr.target[0][_ToolchainInfo]
    repos = {file.owner.workspace_root: None for file in toolchain_info.files.to_list()}
    if not repos:
        fail(
            "toolchain target",
            toolchain_info.label,
            "for '{}' has no files".format(toolchain_name),
        )
    if len(repos) > 1:
        fail(
            "toolchain target",
            toolchain_info.label,
            "for '{}' has files from different repositories: {}".format(
                toolchain_name,
                ", ".join(repos.keys()),
            ),
        )
    single_repo = repos.keys()[0]

    # Calculate relative path up to output base
    up_to_output_base_segments = ctx.label.name.count("/")
    up_to_output_base_segments += ctx.label.package.count("/") + 1 if ctx.label.package else 0
    up_to_output_base_segments += ctx.bin_dir.path.count("/") + 1
    up_to_output_base_segments += 2  # execroot/<workspace_name>

    out = ctx.actions.declare_symlink(ctx.label.name)
    ctx.actions.symlink(output = out, target_path = up_to_output_base_segments * "../" + single_repo)

    return [
        DefaultInfo(files = depset([out])),
    ]

_toolchain_symlink = rule(
    implementation = _toolchain_symlink_impl,
    cfg = _flip_output_dir,
    attrs = {
        "target": attr.label(
            cfg = _flip_output_dir,
            aspects = [_extract_toolchain_info],
        ),
        "_allowlist_function_transition": attr.label(
            default = "@bazel_tools//tools/allowlists/function_transition_allowlist",
        ),
    },
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

    # Get toolchain info
    toolchain_names = [t.basename for t in ctx.files.toolchain_symlinks]
    toolchains_list = "\n".join(["  * " + name for name in sorted(toolchain_names)])
    has_toolchains = "True" if toolchain_names else "False"

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
            "{{has_toolchains}}": has_toolchains,
            "{{toolchains}}": toolchains_list,
        },
    )

    # Include both tool wrappers and toolchain symlinks in output
    all_files = ctx.files.tool_wrappers + ctx.files.toolchain_symlinks

    # Force runfiles to be created for eager tools by running a dummy action
    if ctx.attr.eager_tool_targets:
        implicit_out = ctx.actions.declare_file(ctx.label.name + "_all_tools")
        tools = [tool[DefaultInfo].files_to_run for tool in ctx.attr.eager_tool_targets]
        ctx.actions.run_shell(
            outputs = [implicit_out],
            inputs = depset(all_files),
            tools = tools,
            command = 'touch "$1"',
            arguments = [implicit_out.path],
            # Run locally to force runfiles directories to be created
            execution_requirements = {
                "no-cache": "",
                "no-remote": "",
                "no-sandbox": "",
            },
        )
        all_files = all_files + [implicit_out]

    return [
        DefaultInfo(
            executable = status_script,
            files = depset(all_files),
            runfiles = ctx.runfiles(files = all_files),
        ),
    ]

_lazy_bazel_env_rule = rule(
    implementation = _lazy_bazel_env_impl,
    cfg = _flip_output_dir,
    attrs = {
        "tool_wrappers": attr.label_list(allow_files = True),
        "toolchain_symlinks": attr.label_list(allow_files = True),
        "eager_tool_targets": attr.label_list(),
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
            If a target is provided, a lazy wrapper is created that invokes
            `bazel run` on first use.
            If a path with Make variables (e.g., "$(NODE_PATH)") is provided,
            an eager wrapper is created that resolves the path from toolchains.
        toolchains: A dictionary mapping toolchain names to their targets.
            The name is used as the basename of the toolchain directory in the
            `toolchains` directory. The directory is a symlink to the repository
            root of the (single) repository containing the toolchain.
            Make variables from these toolchains are available for use in tools.
        **kwargs: Additional arguments passed to the main rule.
    """
    tool_wrappers = []
    toolchain_symlink_targets = []
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

    # Create toolchain symlinks
    toolchain_info_targets = {}
    for toolchain_name, toolchain in toolchains.items():
        if not toolchain_name:
            fail("empty toolchain names are not allowed")

        toolchain_target_name = name + "/toolchains/" + toolchain_name
        toolchain_symlink_targets.append(toolchain_target_name)
        toolchain_info_targets[toolchain_name] = toolchain

        _toolchain_symlink(
            name = toolchain_target_name,
            target = toolchain,
            visibility = ["//visibility:private"],
            tags = ["manual"],
        )

    eager_tool_targets = []

    for tool_name, tool_target in tools.items():
        if not tool_name:
            fail("empty tool names are not allowed")
        if tool_name in _FORBIDDEN_TOOL_NAMES:
            fail("tool name '{}' is forbidden".format(tool_name))

        wrapper_name = name + "/bin/" + tool_name
        is_str = type(tool_target) == type("")

        if is_str and "$" in tool_target:
            # Tool with Make variables - use eager resolution from toolchains
            _eager_tool(
                name = wrapper_name,
                tool_name = tool_name,
                path = tool_target,
                bazel_env_label = label,
                toolchain_targets = toolchain_info_targets.values(),
                visibility = ["//visibility:private"],
                tags = ["manual"],
            )
            eager_tool_targets.append(wrapper_name)
        elif is_str and tool_target.startswith("/") and not tool_target.startswith("//"):
            fail("absolute paths are not supported, got '{}' for tool '{}'".format(tool_target, tool_name))
        else:
            # Regular target - use lazy wrapper
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
        toolchain_symlinks = toolchain_symlink_targets,
        eager_tool_targets = eager_tool_targets,
        **kwargs
    )
