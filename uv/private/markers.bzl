"""Exec-root path marker for env values.

When `UvBuildEnvInfo` carries a path that is exec-root-relative (e.g., a tool
from a Bazel external repo), it must be resolved to an absolute path at
runtime because tools like setuptools change the working directory when
building extensions.

Use `to_exec_root_path()` to apply the marker to a exec-root-relative path
or use `EXEC_ROOT_MARKER` directly.
"""

EXEC_ROOT_MARKER = "$$EXEC_ROOT$$/"

def to_exec_root_path(path):
    """Return `path` with the exec-root marker if it is a relative path. Absolute paths are returned as-is."""
    if not path or path.startswith("/"):
        return path
    return EXEC_ROOT_MARKER + path
