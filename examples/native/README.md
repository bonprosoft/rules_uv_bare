# Native Extension Example

Demonstrates a nanobind C++ extension compiled into a `.so`, packaged as a `py_wheel`, and imported into a uv workspace via `uv_py_import_wheel`.

## Structure

- `native_lib/`: C++ extension (`_ext.cpp`) built with `nanobind_extension`, wrapped by `py_library` + `py_wheel`, bridged via `uv_py_import_wheel`.
- `app/`: A `uv_py_package` that depends on `native_lib` through `wheel_deps`

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
