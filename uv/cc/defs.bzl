"""CC toolchain integration for rules_uv_bare.

Requires ``bazel_dep(name = "rules_cc", ...)`` in your MODULE.bazel.

Provides:
  - uv_cc_env: resolves the Bazel CC toolchain and provides environment
    variables (CC, CXX, AR, LD, PATH) for uv_py_workspace via UvBuildEnvInfo.
"""

load("//uv/cc/private:cc_env.bzl", _uv_cc_env = "uv_cc_env")

uv_cc_env = _uv_cc_env
