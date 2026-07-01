"""UV env var defaults for actions that run uv."""

DEFAULT_UV_CACHE_DIR = "/tmp/bazel-uv-cache"

def with_uv_env_defaults(env):
    """Fill in UV_CACHE_DIR / UV_PYTHON_INSTALL_DIR defaults, keeping them aligned."""
    result = dict(env)
    result.setdefault("UV_CACHE_DIR", DEFAULT_UV_CACHE_DIR)
    result.setdefault("UV_PYTHON_INSTALL_DIR", result["UV_CACHE_DIR"] + "/python")
    return result
