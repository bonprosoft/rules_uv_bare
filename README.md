# rules\_uv\_bare

Bazel rules for Python projects using [uv](https://docs.astral.sh/uv/) as the package manager.
Keep your Python packaging in the Python ecosystem (`pyproject.toml` + uv) and bridge it into Bazel with a minimal effort.
The rules also map naturally to uv's workspace feature, giving a fast and incremental installs.

This approach trades away some of Bazel’s core strengths — hermetic/sandboxed builds, remote execution, and fine-grained `deps` tracking — but in return allows the project to integrate seamlessly with the standard Python ecosystem.

## Why rules\_uv\_bare?

Suppose that you have a uv workspace with two packages:

```
├── pyproject.toml  # uv workspace root
├── my_package_a
│   ├── pyproject.toml
│   └── ...
├── my_package_b
│   ├── pyproject.toml
│   └── ...
...
```

With the standard `rules_python` approach, you need to write a `BUILD.bazel` file for every package to describe its build information and metadata, such as `srcs`, `data`, `deps`, and so on.
In particular, dependency information ends up duplicated in two places (`pyproject.toml` *and* BUILD files) and keeping them in sync is left to you.

There is also no built-in counterpart to uv's workspace concept; third-party packages are pinned in `MODULE.bazel` and every target must explicitly declare the dependencies it needs.

Here is what a typical `rules_python` setup looks like:

```python
# my_package_a/BUILD.bazel
py_library(
    name = "my_package_a",
    imports = ["."],
    srcs = glob(["my_package_a/**/*.py"]),
    deps = [
        "@pip//pydantic",
    ],
)

# my_package_b/BUILD.bazel
py_library(
    name = "my_package_b",
    imports = ["."],
    srcs = glob(["my_package_b/**/*.py"]),
    deps = [
        "@pip//numpy",
        "//my_package_a",
    ],
)

# MODULE.bazel
pip = use_extension("@rules_python//python/extensions:pip.bzl", "pip")
pip.parse(
    hub_name = "pip",
    python_version = "3.12",
    requirements_lock = "//:requirements.txt",
)
use_repo(pip, "pip")
```

With `rules_uv_bare`, the BUILD files shrink to bare declarations:

```python
# my_package_a/BUILD.bazel
uv_py_package(name = "my_package_a")

# my_package_b/BUILD.bazel
uv_py_package(name = "my_package_b")

# BUILD.bazel
uv_py_workspace(
    name = "workspace",
    members = ["//my_package_a", "//my_package_b"],
    lock = "uv.lock",
)
```

Most of dependency metadata stays in `pyproject.toml`, which serves as the single source of truth already understood by most of the Python ecosystem.
You can still declare explicit `deps` if you need Bazel features like `bazel cquery`.

Features:

- **Seamless Python ecosystem integration**: Most Python metadata such as dependencies stays in the standard `pyproject.toml` format.
  No need to mirror them into Bazel targets or maintain a separate lock-file translation layer.
- **Multi-package workspaces**: Maps naturally to uv's workspace concept.
  Multiple Python packages share a single lock file and virtualenv, with inter-package dependencies declared via standard `[tool.uv.sources]`.
  You can also define more than one workspaces with different third-party dependencies in the same Bazel module, and packages can belong to multiple workspaces.

## Quick Start

### 1. Add the module dependency

In your `MODULE.bazel`:

```python
bazel_dep(name = "rules_uv_bare", version = "0.0.1")
```

### 2. Declare a Python package

Each Python package has its own `pyproject.toml` and `BUILD.bazel`:

```toml
# my_package/pyproject.toml
[project]
name = "my-package"
version = "0.0.1"
requires-python = ">=3.12"
dependencies = ["numpy>=1.26,<3"]

[project.scripts]
my-app = "my_package:main"
```

```python
# my_package/BUILD.bazel
load("@rules_uv_bare//uv:defs.bzl", "uv_py_package")

uv_py_package(name = "my_package")
```

### 3. Create a workspace

A workspace groups packages together and manages their shared virtualenv:

```python
# BUILD.bazel
load("@rules_uv_bare//uv:defs.bzl", "uv_py_entrypoint", "uv_py_lock", "uv_py_test", "uv_py_workspace")

uv_py_workspace(
    name = "my_workspace",
    members = ["//my_package"],
    lock = "uv.lock",
    deploy_uv_python = "cpython-3.12",
)

uv_py_lock(
    name = "my_workspace.lock",
    workspace = ":my_workspace",
)

uv_py_entrypoint(
    name = "run",
    workspace = ":my_workspace",
    cmd = ["my-app"],
)

uv_py_test(
    name = "test",
    workspace = ":my_workspace",
    cmd = ["pytest", "tests/"],
)
```

### 4. Generate the lock file

```bash
bazel run //:my_workspace.lock
```

### 5. Build and test

```bash
# Run in development environment (faster)
bazel run //:run
bazel test //:test

# Build self-contained deploy (slower)
bazel build //:my_workspace.deploy
bazel run //:run.deploy
```

The `.deploy` target bundles a [python-build-standalone](https://github.com/astral-sh/python-build-standalone) interpreter matching `deploy_uv_python`.
The build artifact is fully self-contained and does not require Python on the target host.

`.deploy` sub-targets (`<workspace>.deploy`, `<entrypoint>.deploy`, and any `uv_py_deploy` target) are tagged `manual`, so `bazel build //...` skips them.

## Rules Reference

See [docs/rules.md](docs/rules.md) for the full API reference (generated by [Stardoc](https://github.com/bazelbuild/stardoc)).

## Examples

### Multi-Package Workspaces

Packages within a workspace can depend on each other using uv's workspace sources in their `pyproject.toml`:

```toml
# pkg_b/pyproject.toml
[project]
name = "pkg-b"
dependencies = ["pkg-a"]
```

```python
# pkg_a/BUILD.bazel
uv_py_package(name = "pkg_a")
# pkg_b/BUILD.bazel
uv_py_package(name = "pkg_b")
# BUILD.bazel
uv_py_workspace(
    name = "ws",
    # pkg_b depends on pkg_a; both are in the same workspace so uv resolves it automatically.
    members = ["//pkg_a", "//pkg_b"],
    lock = "uv.lock",
)
```

Optionally, you can declare explicit `deps` in BUILD files to expose the dependency graph to Bazel.

```python
# pkg_a/BUILD.bazel
uv_py_package(name = "pkg_a")
# pkg_b/BUILD.bazel
# Declare that pkg_b has a dependency to pkg_a
uv_py_package(name = "pkg_b", deps = ["//pkg_a"])

# BUILD.bazel
uv_py_workspace(
    name = "ws",
    members = ["//pkg_b"],   # pkg_a is also included automatically
    lock = "uv.lock",
)
```

## rules\_python Integration

Build a `.whl` from your target:

```python
load("@rules_python//python:packaging.bzl", "py_wheel")

py_wheel(
    name = "my_ext_wheel",
    package = ":my_ext_lib",
)
```

Import the wheel:

```python
uv_py_import_wheel(
    name = "my_ext",
    src = ":my_ext_wheel",
)
```

Pass the wheel to a package (via `wheel_deps`) or directly to the workspace (via `wheels`):

```python
# Option A: via uv_py_package (collected transitively)
uv_py_package(
    name = "my_package",
    wheel_deps = [":my_ext"],
)
uv_py_workspace(
    name = "ws",
    members = [":my_package"],
    lock = "uv.lock",
)

# Option B: directly on workspace
uv_py_workspace(
    name = "ws",
    members = [":my_package"],
    wheels = [":my_ext"],
    lock = "uv.lock",
)
```

See `examples/import_from_rules_python/` for more details.

## Native build / cross-platform deployment

You can find examples for native build / cross-platform deployment:

- `examples/native/`: first-party native wheel (nanobind) + third-party source build
- `examples/native_cross/`: same as `native` with cross-platform `target_platforms`
- `examples/env_provider/`: custom `UvBuildEnvInfo` providers

### First-party native packages

If your Python package requires native compilation (C/C++ extensions), it can be integrated by building a wheel and importing it into the workspace by `uv_py_import_wheel` rule.

### Third-party native packages

When third-party Python packages need native compilation, the build tools must be available during `uv sync`.
The `env_providers` attribute on `uv_py_workspace` allows you to forward toolchains as environment variables.

For example, a built-in `uv_cc_env` rule resolves the Bazel CC toolchain and provides `CC`, `CXX`, `AR`, `LD`, and `PATH`:

```python
load("@rules_uv_bare//uv/cc:defs.bzl", "uv_cc_env")

uv_cc_env(name = "cc_env")

uv_py_workspace(
    name = "ws",
    env_providers = [":cc_env"],
    # ...
)
```

You can write custom providers by returning `UvBuildEnvInfo` from a rule (see `examples/env_provider/` for a Cargo/Rust example).
You can also directly pass `env` attribute to override environment variables statically.

### Multi-platform lock file

When `target_platforms` is passed to `uv_py_workspace`, it creates a single unified `uv.lock` covering all listed platforms (i.e., the same way as uv).
Internally, it uses Bazel split transitions to build each wheel once per target platform, and writes marker-qualified `[tool.uv.sources]` entries (e.g. `platform_machine == 'x86_64'`) so that uv picks the correct wheel for each platform from one lock file.

### Cross-compilation deploy

The `.deploy` target supports cross-compilation.
It bundles a [python-build-standalone](https://github.com/astral-sh/python-build-standalone) interpreter for the target platform, so the output is fully self-contained.

`deploy_uv_python` is required.
Its value is a uv Python install key (the same key format `uv python list <key>` accepts).
Cross-compile is detected automatically by comparing the resolved entry's `(os, arch)` to the host.

```python
uv_py_workspace(
    name = "ws",
    env_providers = [":cc_env"],
    deploy_uv_python = select({
        ":is_linux_x86_64": "cpython-3.12-linux-x86_64-gnu",
        ":is_linux_aarch64": "cpython-3.12-linux-aarch64-gnu",
        ":is_darwin_aarch64": "cpython-3.12-macos-aarch64-none",
    }),
    deploy_build_deps = ["setuptools", "wheel", "uv-build>=0.7"],
    # ...
)
```

For the native (no cross-compile) case, a short key without `-<os>-<arch>-<libc>` works:

```python
deploy_uv_python = "cpython-3.12",
```

| Attribute | Purpose | Example value |
|-----------|---------|---------------|
| `deploy_uv_python` | uv python install key for the `.deploy` target. Both native and cross-compile. | `"cpython-3.12"`, `"cpython-3.12-linux-aarch64-gnu"` |
| `deploy_manylinux` | Optional manylinux baseline override for Linux+gnu cross-compile. Default `manylinux2014` (glibc 2.17). | `"manylinux_2_28"` |
| `deploy_build_deps` | Build backends to pre-install | `["setuptools", "wheel"]` |

### The `$$EXEC_ROOT$$` path marker

Custom `UvBuildEnvInfo` providers that expose file paths (e.g., compiler tools, sysroot headers) should mark exec-root-relative paths with `to_exec_root_path()` so they get resolved at runtime:

```python
load("@rules_uv_bare//uv:defs.bzl", "EXEC_ROOT_MARKER", "UvBuildEnvInfo", "to_exec_root_path")

# In your custom provider rule:
env["CC"] = to_exec_root_path(cc_path)                  # marks if relative; no-op if absolute
env["MY_TOOL"] = to_exec_root_path("/usr/bin/my_tool")  # already absolute: returned as-is
# For values that embed a path inside a larger string, use EXEC_ROOT_MARKER directly:
env["CFLAGS"] = "-isystem " + EXEC_ROOT_MARKER + include_dir + " -O2"
```

**Why this is needed:**
When `uv sync` builds Python packages from source, build tools such as setuptools change the working directory to a temporary build directory.
Bazel-provided paths are relative to the exec root, so they no longer resolve from that new directory.
The marker is replaced with the absolute exec root at runtime, which makes the paths work regardless of the current directory.

The built-in `uv_cc_env` rule handles this automatically.
You only need to use the marker when writing custom providers.
See `examples/env_provider/cargo_uv_env.bzl` for an example.

## Advanced Examples

### Private PyPI registries

```python
uv_py_workspace(
    name = "ws",
    members = ["//my_package"],
    lock = "uv.lock",
    extra_pyproject_content = """
[[tool.uv.index]]
url = "https://private.pypi.org/simple"

[[tool.uv.index]]
url = "https://pypi.org/simple"
""",
)
```

### Custom tool configuration

```python
uv_py_workspace(
    name = "ws",
    members = ["//my_package"],
    lock = "uv.lock",
    extra_pyproject_content = """
[tool.pytest.ini_options]
testpaths = ["tests"]
addopts = "-v"
""",
)
```

### Custom dependency groups

```python
uv_py_workspace(
    name = "ws",
    members = ["//my_package"],
    lock = "uv.lock",
    dependency_groups = {
        "test": ["pytest>=8.0", "pytest-cov"],
        "lint": ["ruff>=0.4"],
    },
)
```
