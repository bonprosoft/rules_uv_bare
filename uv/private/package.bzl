"""uv_py_package rule and macro."""

load("//uv/private:providers.bzl", "UvPyPackageInfo", "UvPyWheelInfo")

DEFAULT_PY_EXCLUDES = ["build/**", "dist/**", ".venv/**", "__pycache__/**"]

def _uv_py_package_rule_impl(ctx):
    python_package_name = ctx.attr.python_package_name or ctx.label.name

    # Normalize _ to -
    python_package_name = python_package_name.replace("_", "-")

    self_pkg = struct(
        label_name = str(ctx.label),
        python_package_name = python_package_name,
        pyproject = ctx.file.pyproject,
        srcs = depset(ctx.files.srcs),
        data = depset(ctx.files.data),
    )

    # Build transitive list.
    seen = {str(ctx.label): True}
    transitive = [self_pkg]
    for dep in ctx.attr.deps:
        for pkg in dep[UvPyPackageInfo].transitive_packages:
            if pkg.label_name not in seen:
                seen[pkg.label_name] = True
                transitive.append(pkg)

    transitive_wheels = []
    for w in ctx.attr.wheel_deps:
        whl = w[UvPyWheelInfo]
        if whl.label_name not in seen:
            seen[whl.label_name] = True
            transitive_wheels.append(struct(
                label_name = whl.label_name,
                wheel = whl.wheel,
                python_package_name = whl.python_package_name,
                frozen = whl.frozen,
            ))
    for dep in ctx.attr.deps:
        for whl in dep[UvPyPackageInfo].transitive_wheels:
            if whl.label_name not in seen:
                seen[whl.label_name] = True
                transitive_wheels.append(whl)

    return [
        UvPyPackageInfo(
            label_name = str(ctx.label),
            python_package_name = python_package_name,
            pyproject = ctx.file.pyproject,
            srcs = self_pkg.srcs,
            data = self_pkg.data,
            transitive_packages = transitive,
            transitive_wheels = transitive_wheels,
        ),
        DefaultInfo(files = depset([ctx.file.pyproject] + ctx.files.srcs + ctx.files.data)),
    ]

_uv_py_package_rule = rule(
    implementation = _uv_py_package_rule_impl,
    attrs = {
        "pyproject": attr.label(allow_single_file = [".toml"], mandatory = True),
        "srcs": attr.label_list(allow_files = [".py"]),
        "data": attr.label_list(allow_files = True),
        "deps": attr.label_list(providers = [UvPyPackageInfo]),
        "wheel_deps": attr.label_list(providers = [UvPyWheelInfo]),
        "python_package_name": attr.string(),
    },
)

def uv_py_package(
        name,
        pyproject = "pyproject.toml",
        srcs = None,
        data = None,
        deps = [],
        wheel_deps = [],
        python_package_name = None,
        visibility = ["//visibility:public"]):
    """Declares a Python package by a pyproject.toml.

    Note that ``srcs`` and ``data`` are used only for triggering a build.
    The actual build is done by ``uv`` outside of the Bazel sandbox, and these attributes are completely ignored.

    **Example**

    ```bzl
    uv_py_package(name = "my_package")
    ```

    Args:
        name: target name.
        pyproject: path to pyproject.toml (default "pyproject.toml").
        srcs: Python source files. Defaults to ``glob(["**/*.py"])`` with
            ``build/``, ``dist/``, ``.venv/``, and ``__pycache__/`` excluded.
        data: non-Python data files to include in the package (YAML, JSON,
            CSV, .pyi stubs, py.typed markers, templates, etc.).
        deps: first-party uv_py_package targets this package depends on.
            Enables automatic transitive member resolution in uv_py_workspace.
        wheel_deps: uv_py_import_wheel targets this package depends on.
            Wheels are collected transitively by uv_py_workspace.
        python_package_name: Python package name override.
            Defaults to ``name``. Underscores are normalized to hyphens.
        visibility: Bazel visibility.
    """
    if srcs == None:
        srcs = native.glob(["**/*.py"], exclude = DEFAULT_PY_EXCLUDES, allow_empty = True)
    _uv_py_package_rule(
        name = name,
        pyproject = pyproject,
        srcs = srcs,
        data = data or [],
        deps = deps,
        wheel_deps = wheel_deps,
        python_package_name = python_package_name or name,
        visibility = visibility,
    )
