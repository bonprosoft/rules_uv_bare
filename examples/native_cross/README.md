# Native Cross-Compilation Example

Demonstrates cross-compiling a native C++ extension (nanobind) for Linux x86\_64 and Linux/macOS aarch64.

## How it works

When `target_platforms` is set, `uv_py_workspace` internally creates split transitions to build each wheel once per target platform.
Then it generates marker-qualified `[tool.uv.sources]` entries (e.g. `platform_machine == 'x86_64'`) so that uv picks the correct wheel.
This allows uv to produce a single unified `uv.lock` covering all listed platforms.

```python
uv_py_workspace(
    name = "ws",
    members = ["//app"],
    wheels = ["//native_lib:native_lib_uv"],
    lock = "uv.lock",
    target_platforms = {
        ":linux_x86_64": "platform_machine == 'x86_64' and sys_platform == 'linux'",
        ":linux_aarch64": "platform_machine == 'aarch64' and sys_platform == 'linux'",
    },
    target_compatible_with = ["@platforms//os:linux"],
)
```

You can also use `target_compatible_with` to skip targets.

## Limitation

Because `uv sync` runs locally, the workspace target and its subtargets (`.run`, `.activate`) require the host to match the target platform.
Other rules, such as `uv_py_lock`, `uv_py_export`, and `uv_py_deploy`, would work on any platform.

Also, non-universal wheels (i.e., wheels that have platform-specific tags) must be specified directly in the `wheels` attribute of `uv_py_workspace`, even if they are already transitive dependencies of a `uv_py_package`.

## Usage

Generate the lock file:

```bash
bazel run //:ws.lock
```

Cross-compile the wheel for Linux x86\_64:

```bash
bazel build --config=linux_x86_64 //native_lib:wheel
```

Cross-compile the wheel for Linux aarch64:

```bash
bazel build --config=linux_aarch64 //native_lib:wheel
```

Build the full workspace (requires a matching Linux host):

```bash
bazel build --config=linux_x86_64 //:ws
bazel build --config=linux_aarch64 //:ws
```

Deploy for a target platform (works from any host):

```bash
bazel run --config=linux_x86_64 //:deploy -- /tmp/deploy_x86_64
bazel run --config=linux_aarch64 //:deploy -- /tmp/deploy_aarch64
```
