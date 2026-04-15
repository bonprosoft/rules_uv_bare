"""CC toolchain environment provider for uv_py_workspace."""

load("@rules_cc//cc:action_names.bzl", "ACTION_NAMES")
load("@rules_cc//cc:find_cc_toolchain.bzl", "find_cc_toolchain", "use_cc_toolchain")
load("@rules_cc//cc/common:cc_common.bzl", "cc_common")
load("//uv/private:markers.bzl", "EXEC_ROOT_MARKER", "to_exec_root_path")
load("//uv/private:providers.bzl", "UvBuildEnvInfo")

def _is_exec_root_relative(s):
    return s.startswith("external/") or s.startswith("bazel-out/")

def _mark_exec_root_flag(flag):
    """Add execroot marker if a flag contains relative paths."""

    # Bare path: external/... or bazel-out/...
    if _is_exec_root_relative(flag):
        return EXEC_ROOT_MARKER + flag

    # Flag with joined path: -Iexternal/..., -Lbazel-out/..., -Bbazel-out/...
    for prefix in ("-I", "-L", "-B"):
        if flag.startswith(prefix):
            rest = flag[len(prefix):]
            if _is_exec_root_relative(rest):
                return prefix + EXEC_ROOT_MARKER + rest
            return flag

    # key=value: --sysroot=path
    if "=" in flag:
        k, v = flag.split("=", 1)
        if _is_exec_root_relative(v):
            return k + "=" + EXEC_ROOT_MARKER + v

    return flag

def _uv_cc_env_impl(ctx):
    cc_toolchain = find_cc_toolchain(ctx)
    feature_configuration = cc_common.configure_features(
        ctx = ctx,
        cc_toolchain = cc_toolchain,
    )

    cc = cc_common.get_tool_for_action(
        feature_configuration = feature_configuration,
        action_name = ACTION_NAMES.c_compile,
    )
    cxx = cc_common.get_tool_for_action(
        feature_configuration = feature_configuration,
        action_name = ACTION_NAMES.cpp_compile,
    )
    ar = cc_common.get_tool_for_action(
        feature_configuration = feature_configuration,
        action_name = ACTION_NAMES.cpp_link_static_library,
    )
    ld = cc_common.get_tool_for_action(
        feature_configuration = feature_configuration,
        action_name = ACTION_NAMES.cpp_link_executable,
    )

    # Get toolchain-configured env vars.
    # Hermetic toolchains (e.g. toolchains_llvm) may provide PATH here.
    # System toolchains typically return {}.
    variables = cc_common.create_compile_variables(
        feature_configuration = feature_configuration,
        cc_toolchain = cc_toolchain,
    )
    env = dict(cc_common.get_environment_variables(
        feature_configuration = feature_configuration,
        action_name = ACTION_NAMES.c_compile,
        variables = variables,
    ))

    env["CC"] = to_exec_root_path(cc)
    env["CXX"] = to_exec_root_path(cxx)
    env["AR"] = to_exec_root_path(ar)
    env["LD"] = to_exec_root_path(ld)

    # Extract compiler flags from the toolchain (e.g. -isystem, --sysroot).
    # These are critical for cross-compilation where the toolchain provides
    # the target architecture's sysroot and system headers.
    c_flags = cc_common.get_memory_inefficient_command_line(
        feature_configuration = feature_configuration,
        action_name = ACTION_NAMES.c_compile,
        variables = variables,
    )
    cxx_flags = cc_common.get_memory_inefficient_command_line(
        feature_configuration = feature_configuration,
        action_name = ACTION_NAMES.cpp_compile,
        variables = variables,
    )

    link_variables = cc_common.create_link_variables(
        feature_configuration = feature_configuration,
        cc_toolchain = cc_toolchain,
    )
    ld_flags = cc_common.get_memory_inefficient_command_line(
        feature_configuration = feature_configuration,
        action_name = ACTION_NAMES.cpp_link_executable,
        variables = link_variables,
    )

    if c_flags:
        env["CFLAGS"] = " ".join([_mark_exec_root_flag(f) for f in c_flags])
    if cxx_flags:
        env["CXXFLAGS"] = " ".join([_mark_exec_root_flag(f) for f in cxx_flags])
    if ld_flags:
        env["LDFLAGS"] = " ".join([_mark_exec_root_flag(f) for f in ld_flags])

    # Derive PATH from tool directories if the toolchain didn't provide one.
    if "PATH" not in env:
        dirs = {}
        for tool in [cc, cxx, ar, ld]:
            idx = tool.rfind("/")
            if idx >= 0:
                dirs[to_exec_root_path(tool[:idx])] = True
        env["PATH"] = ":".join(dirs.keys())

    return [UvBuildEnvInfo(env = env, files = cc_toolchain.all_files)]

uv_cc_env = rule(
    implementation = _uv_cc_env_impl,
    attrs = {
        "_cc_toolchain": attr.label(
            default = "@bazel_tools//tools/cpp:current_cc_toolchain",
        ),
    },
    toolchains = use_cc_toolchain(),
    fragments = ["cpp"],
)
