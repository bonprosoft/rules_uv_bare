"""uv_py_wheel rule and macro."""

load("//uv/private:providers.bzl", "UvPyPackageInfo", "UvPyRuntimeInfo")

def _uv_py_wheel_impl(ctx):
    pkg_info = ctx.attr.package[UvPyPackageInfo]
    wheel_dir = ctx.actions.declare_directory(ctx.attr.name + "_whl")
    target_py_runtime = ctx.attr._target_py_runtime[UvPyRuntimeInfo]

    config = {
        "pyproject_path": pkg_info.pyproject.path,
        "output_dir": wheel_dir.path,
        "uv_path": ctx.executable._uv.path,
        "python_path": target_py_runtime.interpreter_path,
    }
    config_file = ctx.actions.declare_file(ctx.attr.name + ".config.json")
    ctx.actions.write(output = config_file, content = json.encode(config))

    ctx.actions.run(
        executable = ctx.executable._wheel_tool,
        arguments = ["--config", config_file.path],
        outputs = [wheel_dir],
        inputs = depset(
            direct = [pkg_info.pyproject, config_file],
            transitive = [pkg_info.srcs, pkg_info.data, target_py_runtime.files],
        ),
        tools = [ctx.executable._wheel_tool, ctx.executable._uv],
        execution_requirements = {"local": "1"},
    )
    return [DefaultInfo(files = depset([wheel_dir]))]

_uv_py_wheel_rule = rule(
    implementation = _uv_py_wheel_impl,
    attrs = {
        "package": attr.label(providers = [UvPyPackageInfo], mandatory = True),
        "_target_py_runtime": attr.label(
            default = Label("@rules_uv_bare//uv/private:py_runtime"),
            providers = [UvPyRuntimeInfo],
        ),
        "_wheel_tool": attr.label(
            default = Label("@rules_uv_bare//uv/private:wheel_tool"),
            executable = True,
            cfg = "exec",
        ),
        "_uv": attr.label(
            default = Label("@multitool//tools/uv"),
            executable = True,
            cfg = "exec",
        ),
    },
)

def uv_py_wheel(name, package, visibility = ["//visibility:public"]):
    """Builds a .whl from a uv_py_package target.

    **Example**

    ```bzl
    uv_py_wheel(
        name = "wheel",
        package = ":my_package",
    )
    ```

    Args:
        name: target name.
        package: uv_py_package target to build.
        visibility: Bazel visibility.
    """
    _uv_py_wheel_rule(
        name = name,
        package = package,
        visibility = visibility,
    )
