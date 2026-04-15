# Env Provider Example

Demonstrates custom `UvBuildEnvInfo` providers that inject environment variables into `uv sync`, which is typically required for native builds (e.g., C extensions via CC toolchain, Rust/Cargo packages).

## How it works

`uv_py_workspace` accepts an `env_providers` attribute, which is a list of targets that return `UvBuildEnvInfo`.
Each provider supplies environment variables (and optionally toolchain files) that are merged and passed to `uv sync`.

This example uses two providers:
- `uv_cc_env` (built-in from rules\_uv\_bare): provides `CC`, `CXX`, `AR`, `LD`, `PATH`, `CFLAGS`, `CXXFLAGS`, `LDFLAGS` from the Bazel CC toolchain
- `cargo_uv_env` (custom): provides `CARGO_TARGET_<TRIPLE>_LINKER` for Rust/Cargo builds

## The `$$EXEC_ROOT$$` path marker

When writing custom providers that expose file paths (compiler tools, sysroot headers, etc.), wrap exec-root-relative paths with `to_exec_root_path()` so they get resolved at runtime:

```python
load("@rules_uv_bare//uv:defs.bzl", "UvBuildEnvInfo", "to_exec_root_path")

def _my_env_impl(ctx):
    tool_path = ctx.executable.my_tool.path  # e.g. "external/.../bin/tool"
    return [UvBuildEnvInfo(
        env = {
            "MY_TOOL": to_exec_root_path(tool_path),         # marks if relative
            "MY_FLAG": to_exec_root_path("/usr/bin/system_tool"),  # already absolute: no-op
        },
        files = depset(),
    )]
```

For env values that embed a path inside a larger string (e.g., a CFLAGS-style flag), use the `EXEC_ROOT_MARKER` constant directly: `"-isystem " + EXEC_ROOT_MARKER + include_dir`.

**Why this is needed:**
When `uv sync` builds Python packages from source, build tools such as setuptools change the working directory to a temporary build directory.
Bazel-provided paths are relative to the exec root, so they no longer resolve from that new directory.
The marker is replaced with the absolute exec root at runtime, which makes the paths work regardless of the current directory.

The built-in `uv_cc_env` rule handles this automatically.
See `cargo_uv_env.bzl` for a minimal custom-provider example.

## Usage

```sh
# Generate / update the lock file
bazel run //:ws.lock

# Run the application
bazel run //:run

# Run tests
bazel test //:test
```
