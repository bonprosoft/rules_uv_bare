"""Custom UvBuildEnvInfo provider for Rust/Cargo packages.

Resolves the CC toolchain's linker and sets CARGO_TARGET_<triple>_LINKER
so maturin/cargo can find it when building Rust-based Python packages
(e.g., eclipse-zenoh).
"""

load("@rules_cc//cc:action_names.bzl", "ACTION_NAMES")
load("@rules_cc//cc:find_cc_toolchain.bzl", "find_cc_toolchain", "use_cc_toolchain")
load("@rules_cc//cc/common:cc_common.bzl", "cc_common")
load("@rules_uv_bare//uv:defs.bzl", "UvBuildEnvInfo")

def _cargo_uv_env_impl(ctx):
    cc_toolchain = find_cc_toolchain(ctx)
    feature_configuration = cc_common.configure_features(
        ctx = ctx,
        cc_toolchain = cc_toolchain,
    )

    linker = cc_common.get_tool_for_action(
        feature_configuration = feature_configuration,
        action_name = ACTION_NAMES.cpp_link_executable,
    )

    # Map the target triple to the Cargo env var name.
    # Cargo expects: CARGO_TARGET_<TRIPLE_UPPERCASE_UNDERSCORED>_LINKER
    triple = ctx.attr.cargo_target_triple
    key = "CARGO_TARGET_" + triple.upper().replace("-", "_") + "_LINKER"

    return [UvBuildEnvInfo(env = {key: linker})]

cargo_uv_env = rule(
    implementation = _cargo_uv_env_impl,
    attrs = {
        "cargo_target_triple": attr.string(default = "x86_64-unknown-linux-gnu"),
        "_cc_toolchain": attr.label(
            default = "@bazel_tools//tools/cpp:current_cc_toolchain",
        ),
    },
    toolchains = use_cc_toolchain(),
    fragments = ["cpp"],
)
