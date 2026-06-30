# Native Extension Example

Demonstrates two ways of working with native code in a uv workspace:

1. **First-party native**: a nanobind C++ extension compiled into `_ext.so`,
   then staged into a single directory tree alongside `pyproject.toml`,
   `__init__.py`, and `py.typed`, and registered as a workspace member via
   `uv_py_package`. See `native_lib/BUILD.bazel` for the mechanism.

2. **Third-party source build**: `msgpack` from PyPI is compiled from source
   (`tool.uv.no-binary-package`), with the Bazel CC toolchain forwarded to
   `uv sync` through `uv_cc_env` + `env_providers`.

## Usage

```sh
# Generate / update the lock file
bazel run //:ws.lock

# Run the application
bazel run //:run

# Run tests
bazel test //:test

# Build the staged native package directly
bazel build //native_lib

# Build a self-contained deploy artifact
bazel run //:deploy -- /path/to/output
```
