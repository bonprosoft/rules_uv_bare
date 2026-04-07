# Native Extension Example

Demonstrates two ways of working with native libraries in a uv workspace:

1. **First-party native wheel**: A nanobind C++ extension compiled into a `.so`, packaged as a `py_wheel`, and imported via `uv_py_import_wheel`.
2. **Third-party source build**: A package from PyPI requiring compilation from source. The Bazel CC toolchain is forwarded through `uv_cc_env` and `env_providers`.

## Structure

- `native_lib/`: C++ extension (`_ext.cpp`) built with `nanobind_extension`, wrapped by `py_library` + `py_wheel`, bridged via `uv_py_import_wheel`.
- `app/`: A `uv_py_package` that depends on `native_lib` through `wheel_deps` and `msgpack` from PyPI.

The `uv_cc_env` rule resolves the Bazel CC toolchain and passes them to `uv sync` via `env_providers`, so that `msgpack` can be compiled from source.

## Usage

```sh
# Generate / update the lock file
bazel run //:ws.lock

# Run the application
bazel run //:run

# Run tests
bazel test //:test

# Build the native wheel directly
bazel build //native_lib:wheel
```
