# Env Provider Example

Demonstrates custom `UvBuildEnvInfo` providers that inject environment variables into `uv sync`, which is typically required for native builds (e.g., C extensions via CC toolchain, Rust/Cargo packages).

## How it works

`uv_py_workspace` accepts an `env_providers` attribute, which is a list of targets that return `UvBuildEnvInfo`.
Each provider supplies environment variables that are merged and passed to `uv sync`.

## Usage

```sh
# Generate / update the lock file
bazel run //:ws.lock

# Run the application
bazel run //:run

# Run tests
bazel test //:test
```
