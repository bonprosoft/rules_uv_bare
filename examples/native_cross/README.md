# Native Cross-Compilation Example

Demonstrates cross-compiling a native C++ extension (nanobind) for Linux x86\_64 and Linux/macOS aarch64, plus building a third-party C extension from source using `build_env_deps`.

## How it works

### Multi-platform lock file (`platform_markers`)

When `platform_markers` is set, `uv_py_workspace` internally creates split transitions to build each wheel once per target platform.
Then it generates marker-qualified `[tool.uv.sources]` entries (e.g. `platform_machine == 'x86_64'`) so that uv picks the correct wheel.
This allows uv to produce a single unified `uv.lock` covering all listed platforms.

### Cross-compilation bundle (`bundle_target_platform`)

The `.bundle` target produces a relocatable venv for a target architecture.
When packages need to be built from source for a different architecture, pass the target platform suffix via `bundle_target_platform` and list host-platform build backends in `bundle_build_deps`:

- `bundle_target_platform`: platform suffix `{os}-{arch}-{libc}` appended to `host_python`.
- `bundle_manylinux`: optional manylinux baseline override for Linux+gnu (default `manylinux2014`).
- `bundle_build_deps`: build backends to pre-install (host-platform).

In the cross-compile case, the `.bundle` action installs the packages listed in `bundle_build_deps` into a side venv (host-platform) and exposes them via `PYTHONPATH` and `PATH`.
`uv sync` is then run with `--no-build-isolation` so that source builds use those host-platform build backends instead of trying to install target-platform ones, which would not be executable on the host.

The `uv_cc_env` rule provides CC toolchain flags (`CFLAGS`, `LDFLAGS`, etc.) with `$$EXEC_ROOT$$/` markers on exec-root-relative paths.
These markers are resolved to absolute paths at runtime, which is necessary because setuptools changes the working directory when building extensions.

```python
uv_cc_env(name = "cc_env")

uv_py_workspace(
    name = "ws",
    build_env_deps = [":cc_env"],
    members = ["//app"],
    wheels = ["//native_lib"],
    lock = "uv.lock",
    platform_markers = {
        ":linux_x86_64": "platform_machine == 'x86_64' and sys_platform == 'linux'",
        ":linux_aarch64": "platform_machine == 'aarch64' and sys_platform == 'linux'",
        ":darwin_aarch64": "platform_machine == 'arm64' and sys_platform == 'darwin'",
    },
    host_python = "cpython-3.12",
    bundle_target_platform = select({
        ":is_linux_x86_64": "linux-x86_64-gnu",
        ":is_linux_aarch64": "linux-aarch64-gnu",
        ":is_darwin_aarch64": "macos-aarch64-none",
    }),
    bundle_build_deps = ["setuptools", "wheel", "uv-build>=0.7.19,<0.8"],
)
```

## Limitation

The dev workspace target and its subtargets (`.run`, `.activate`) work only when the host and target platforms match; they run `uv sync` locally and produce host-platform artifacts.
The `.bundle` target cross-compiles by downloading a standalone Python for the requested target key, so it works as long as `uv python list <key>` resolves (i.e., python-build-standalone ships a build for that target).

Non-universal wheels (i.e., wheels that have platform-specific tags) must be specified directly in the `wheels` attribute of `uv_py_workspace`, even if they are already transitive dependencies of a `uv_py_package`.

## Usage

Generate the lock file:

```bash
bazel run //:ws.lock
```

Run the application (host platform):

```bash
bazel run //:run
```

Build the deploy venv for a target platform:

```bash
bazel build --platforms=//:linux_x86_64 //:ws.bundle
bazel build --platforms=//:linux_aarch64 //:ws.bundle
bazel build --platforms=//:darwin_aarch64 //:ws.bundle
```

Verify the cross-compiled output:

```bash
file bazel-bin/ws.bundle_dir/lib/python3.12/site-packages/msgpack/*.so
# ELF 64-bit LSB shared object, x86-64         (linux_x86_64)
# ELF 64-bit LSB shared object, ARM aarch64    (linux_aarch64)
# Mach-O 64-bit bundle arm64                   (darwin_aarch64)
```
