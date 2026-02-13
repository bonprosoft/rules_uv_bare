"""uv_py_import_wheel rule."""

load("//uv/private:providers.bzl", "UvPyWheelInfo")

def _uv_py_import_wheel_impl(ctx):
    whl = ctx.file.src
    pkg_name = ctx.attr.python_package_name
    if not pkg_name:
        # Infer from wheel filename: {name}-{ver}(-...)*.whl
        basename = whl.basename
        pkg_name = basename.split("-")[0]

    # Normalize _ to -
    pkg_name = pkg_name.replace("_", "-")

    return [
        UvPyWheelInfo(
            label_name = str(ctx.label),
            wheel = whl,
            python_package_name = pkg_name,
            frozen = ctx.attr.frozen,
        ),
        DefaultInfo(files = depset([whl])),
    ]

uv_py_import_wheel = rule(
    doc = """Imports a pre-built .whl file for use in a uv workspace.

The wheel is registered as a ``[tool.uv.sources]`` in the generated pyproject.toml.
Use ``wheel_deps`` on ``uv_py_package`` or ``wheels`` on ``uv_py_workspace`` to include it.

**Example**

```bzl
uv_py_import_wheel(
    name = "my_ext",
    src = ":my_ext_wheel",
)
```
""",
    implementation = _uv_py_import_wheel_impl,
    attrs = {
        "src": attr.label(
            allow_single_file = [".whl"],
            mandatory = True,
            doc = "The .whl file to import.",
        ),
        "python_package_name": attr.string(
            default = "",
            doc = "Python package name override. " +
                  "Inferred from the wheel filename if not set. " +
                  "Underscores are normalized to hyphens.",
        ),
        "frozen": attr.bool(
            default = True,
            doc = "If False, the wheel hash is recomputed every build. " +
                  "Use when the wheel is built by Bazel and changes frequently.",
        ),
    },
)
