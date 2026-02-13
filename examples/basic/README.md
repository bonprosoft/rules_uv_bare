# Basic Example

Demonstrates the basic features of `rules_uv_bare`.

## Structure

- `lib/`: A simple library package exposing `add(a, b)`
- `app/`: An application package that depends on `lib` and `click`, and loads `data/config.json`

## Usage

```sh
# Generate or update the lock file
bazel run //:ws.lock

# Run the application
bazel run //:run

# Run tests
bazel test //:test

# Build a wheel for the lib package
bazel build //lib:wheel

# Run a command in the workspace (similar to `uv run`)
bazel run //:ws.run -- python3 -c "import lib; print(lib.add(2, 3))"

# Activate the virtualenv shell (similar to `source .venv/bin/activate`)
source "$(bazel run //:ws.activate)"

# Export the uv workspace layout to /tmp/workspace
bazel run //:ws.export -- /tmp/workspace

# Deploy the install directory layout to /tmp/deploy
bazel run //:deploy -- /tmp/deploy
```
