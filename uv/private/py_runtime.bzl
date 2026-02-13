"""uv_py_runtime rule (for internal use only)."""

load("//uv/private:providers.bzl", "UvPyRuntimeInfo")

PY_TOOLCHAIN = "@rules_python//python:toolchain_type"

def _uv_py_runtime_impl(ctx):
    py3_runtime = ctx.toolchains[PY_TOOLCHAIN].py3_runtime
    interpreter = py3_runtime.interpreter
    return [UvPyRuntimeInfo(
        interpreter_path = interpreter.path if interpreter else py3_runtime.interpreter_path,
        interpreter_short_path = interpreter.short_path if interpreter else py3_runtime.interpreter_path,
        files = py3_runtime.files if interpreter else depset(),
    )]

uv_py_runtime = rule(
    implementation = _uv_py_runtime_impl,
    toolchains = [PY_TOOLCHAIN],
)
