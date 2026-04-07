"""CC toolchain environment provider for uv_py_workspace."""

load("@rules_cc//cc:action_names.bzl", "ACTION_NAMES")
load("@rules_cc//cc:find_cc_toolchain.bzl", "find_cc_toolchain", "use_cc_toolchain")
load("@rules_cc//cc/common:cc_common.bzl", "cc_common")
load("//uv/private:providers.bzl", "UvBuildEnvInfo")

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

    env["CC"] = cc
    env["CXX"] = cxx
    env["AR"] = ar
    env["LD"] = ld

    # Derive PATH from tool directories if the toolchain didn't provide one.
    # This ensures tools like `as` (assembler) are resolvable even with
    # system toolchains that don't configure PATH in their env.
    if "PATH" not in env:
        dirs = {}
        for tool in [cc, cxx, ar, ld]:
            idx = tool.rfind("/")
            if idx >= 0:
                dirs[tool[:idx]] = True
        env["PATH"] = ":".join(dirs.keys())

    return [UvBuildEnvInfo(env = env)]

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
