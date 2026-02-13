"""uv_py_lock and uv_py_export macros."""

load("//uv/private:providers.bzl", "UvPyManifestInfo", "UvPyRuntimeInfo")

def _uv_py_workspace_exec_impl(ctx):
    info = ctx.attr.manifest[UvPyManifestInfo]
    exec_py_runtime = ctx.attr._exec_py_runtime[UvPyRuntimeInfo]

    exec_config = {
        "exec_python_interpreter_short_path": exec_py_runtime.interpreter_short_path,
        "uv_short_path": ctx.executable._uv.short_path,
    }
    config_file = ctx.actions.declare_file(ctx.attr.name + ".config.json")
    ctx.actions.write(output = config_file, content = json.encode(exec_config))

    rf = "$0.runfiles/" + ctx.workspace_name + "/"
    tool_rf = rf + ctx.executable._workspace_tool.short_path

    exec_line = 'exec "{tool}" --manifest "{shared}" --config "{config_file}" {subcmd} --runfiles-dir "{rf}"'.format(
        tool = tool_rf,
        subcmd = ctx.attr.subcommand,
        shared = rf + info.manifest_file.short_path,
        config_file = rf + config_file.short_path,
        rf = rf,
    )
    if ctx.attr.extra_script_args:
        exec_line += " " + ctx.attr.extra_script_args

    script = ctx.actions.declare_file(ctx.attr.name + ".sh")
    ctx.actions.write(
        output = script,
        content = "#!/bin/bash\nset -euo pipefail\n" + exec_line + "\n",
        is_executable = True,
    )

    runfiles = ctx.runfiles(
        files = [info.lock_file, info.manifest_file, config_file] + info.wheel_files,
        transitive_files = info.member_files,
    )
    runfiles = runfiles.merge(ctx.attr._workspace_tool[DefaultInfo].default_runfiles)
    runfiles = runfiles.merge(ctx.attr._uv[DefaultInfo].default_runfiles)
    runfiles = runfiles.merge(ctx.runfiles(transitive_files = exec_py_runtime.files))

    return [DefaultInfo(executable = script, runfiles = runfiles)]

uv_py_workspace_exec_rule = rule(
    implementation = _uv_py_workspace_exec_impl,
    executable = True,
    attrs = {
        "manifest": attr.label(mandatory = True, providers = [UvPyManifestInfo]),
        "subcommand": attr.string(mandatory = True),
        "extra_script_args": attr.string(default = ""),
        "_workspace_tool": attr.label(
            default = Label("@rules_uv_bare//uv/private:workspace_tool"),
            executable = True,
            cfg = "exec",
        ),
        "_uv": attr.label(
            default = Label("@multitool//tools/uv"),
            executable = True,
            cfg = "exec",
        ),
        # Python interpreter for the exec platform.
        # We cannot use toolchains = [PY_TOOLCHAIN] here because Bazel would resolve it
        # in the target configuration.
        # The helper rule resolves the toolchain normally, and cfg = "exec" forces
        # resolution on the host platform.
        "_exec_py_runtime": attr.label(
            default = Label("@rules_uv_bare//uv/private:py_runtime"),
            cfg = "exec",
            providers = [UvPyRuntimeInfo],
        ),
    },
)

def uv_py_lock(name, workspace, visibility = ["//visibility:public"]):
    """Updates ``uv.lock`` in-place via ``bazel run``.

    **Example**

    ```bzl
    uv_py_lock(
        name = "ws.lock",
        workspace = ":ws",
    )
    ```

    Args:
        name: target name.
        workspace: the ``uv_py_workspace`` target to lock.
        visibility: Bazel visibility.
    """
    uv_py_workspace_exec_rule(
        name = name,
        manifest = workspace + ".manifest",
        subcommand = "lock",
        visibility = visibility,
    )

def uv_py_export(name, workspace, visibility = ["//visibility:public"]):
    """Exports a portable workspace directory via ``bazel run``.

    **Example**

    ```bzl
    uv_py_export(
        name = "ws.export",
        workspace = ":ws",
    )
    ```

    Args:
        name: target name.
        workspace: the ``uv_py_workspace`` target to export from.
        visibility: Bazel visibility.
    """
    uv_py_workspace_exec_rule(
        name = name,
        manifest = workspace + ".manifest",
        subcommand = "export",
        extra_script_args = '"$@"',
        visibility = visibility,
    )
