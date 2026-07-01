"""uv_py_wheel rule and macro."""

load("//uv/private:providers.bzl", "UvPyManifestInfo", "UvPyPackageInfo")
load("//uv/private:uv_env.bzl", "with_uv_env_defaults")

def _uv_py_wheel_impl(ctx):
    pkg_info = ctx.attr.package[UvPyPackageInfo]
    wheel_dir = ctx.actions.declare_directory(ctx.attr.name + "_whl")

    host_python = ""
    extra_inputs = []
    if ctx.attr.manifest:
        manifest_info = ctx.attr.manifest[UvPyManifestInfo]
        host_python = manifest_info.host_python
        extra_inputs = [manifest_info.manifest_file]

    config = {
        "pyproject_path": pkg_info.pyproject.path,
        "output_dir": wheel_dir.path,
        "uv_path": ctx.executable._uv.path,
        "host_python": host_python,
    }
    config_file = ctx.actions.declare_file(ctx.attr.name + ".config.json")
    ctx.actions.write(output = config_file, content = json.encode(config))

    ctx.actions.run(
        executable = ctx.executable._uv,
        arguments = [
            "run",
            "--script",
            "--no-project",
            ctx.file._wheel_tool_py.path,
            "--config",
            config_file.path,
        ],
        outputs = [wheel_dir],
        inputs = depset(
            direct = [pkg_info.pyproject, config_file, ctx.file._wheel_tool_py] + extra_inputs,
            transitive = [pkg_info.srcs, pkg_info.data],
        ),
        tools = [ctx.executable._uv],
        env = with_uv_env_defaults({}),
        execution_requirements = {"local": "1"},
    )
    return [DefaultInfo(files = depset([wheel_dir]))]

_uv_py_wheel_rule = rule(
    implementation = _uv_py_wheel_impl,
    attrs = {
        "package": attr.label(providers = [UvPyPackageInfo], mandatory = True),
        "manifest": attr.label(providers = [UvPyManifestInfo]),
        "_wheel_tool_py": attr.label(
            default = Label("@rules_uv_bare//uv/private:wheel_tool.py"),
            allow_single_file = [".py"],
        ),
        "_uv": attr.label(
            default = Label("@multitool//tools/uv"),
            executable = True,
            cfg = "exec",
        ),
    },
)

def uv_py_wheel(name, package, workspace = None, visibility = ["//visibility:public"]):
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
        workspace: optional ``uv_py_workspace`` target. When set, the wheel is
            built with that workspace's ``host_python`` via
            ``uv build --python <path>``. When unset (default), ``uv build`` is
            run without ``--python`` and uv auto-discovers an interpreter, which is
            sufficient for pure-Python wheels. Set this when the package has a
            native extension that should pin a specific Python ABI.
        visibility: Bazel visibility.
    """
    _uv_py_wheel_rule(
        name = name,
        package = package,
        manifest = (workspace + ".manifest") if workspace else None,
        visibility = visibility,
    )
