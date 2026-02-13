# Import from rules\_python Example

Demonstrates import from `rules_python` into a uv workspace.
A library is built with `py_library` + `py_wheel`, then imported via `uv_py_import_wheel`.

## Structure

- `lib/`: Built with `rules_python`'s `py_library` and `py_wheel`, bridged via `uv_py_import_wheel`
- `app/`: A `uv_py_package` that depends on `lib` through `wheel_deps`

## Usage

```sh
# Generate / update the lock file
bazel run //:ws.lock

# Run the application
bazel run //:run

# Run tests
bazel test //:test

# Build the rules_python wheel directly
bazel build //lib:wheel
```
