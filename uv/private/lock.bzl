"""uv_py_lock and uv_py_export macros."""

load("//uv/private:paths.bzl", "rlocation_key")
load("//uv/private:providers.bzl", "UvPyManifestInfo")
load("//uv/private:uv_env.bzl", "DEFAULT_UV_CACHE_DIR")

def _rf_path(short_path, workspace_name):
    return "$0.runfiles/" + rlocation_key(short_path, workspace_name)

def _uv_py_workspace_exec_impl(ctx):
    info = ctx.attr.manifest[UvPyManifestInfo]

    exec_config = {
        "uv_short_path": ctx.executable._uv.short_path,
    }
    config_file = ctx.actions.declare_file(ctx.attr.name + ".config.json")
    ctx.actions.write(output = config_file, content = json.encode(exec_config))

    ws = ctx.workspace_name
    uv_rf = _rf_path(ctx.executable._uv.short_path, ws)
    tool_rf = _rf_path(ctx.file._workspace_tool_py.short_path, ws)
    manifest_rf = _rf_path(info.manifest_file.short_path, ws)
    config_rf = _rf_path(config_file.short_path, ws)

    exec_line = 'exec "{uv}" run --script --no-project "{tool}" --manifest "{m}" --config "{c}" {subcmd} --runfiles-dir "$0.runfiles/{ws}/"'.format(
        uv = uv_rf,
        tool = tool_rf,
        m = manifest_rf,
        c = config_rf,
        subcmd = ctx.attr.subcommand,
        ws = ws,
    )
    if ctx.attr.extra_script_args:
        exec_line += " " + ctx.attr.extra_script_args

    script = ctx.actions.declare_file(ctx.attr.name + ".sh")

    # Shell-side equivalent of with_uv_env_defaults() in uv_env.bzl.
    ctx.actions.write(
        output = script,
        content = (
            "#!/bin/bash\nset -euo pipefail\n" +
            "export UV_CACHE_DIR=\"${{UV_CACHE_DIR:-{cache}}}\"\n" +
            "export UV_PYTHON_INSTALL_DIR=\"${{UV_PYTHON_INSTALL_DIR:-${{UV_CACHE_DIR}}/python}}\"\n" +
            "{exec_line}\n"
        ).format(
            cache = DEFAULT_UV_CACHE_DIR,
            exec_line = exec_line,
        ),
        is_executable = True,
    )

    runfiles = ctx.runfiles(
        files = [info.lock_file, info.manifest_file, config_file, ctx.file._workspace_tool_py] + info.wheel_files,
        transitive_files = info.member_files,
    )
    runfiles = runfiles.merge(ctx.attr._uv[DefaultInfo].default_runfiles)

    return [DefaultInfo(executable = script, runfiles = runfiles)]

_uv_py_workspace_exec_rule = rule(
    implementation = _uv_py_workspace_exec_impl,
    executable = True,
    attrs = {
        "manifest": attr.label(mandatory = True, providers = [UvPyManifestInfo]),
        "subcommand": attr.string(mandatory = True),
        "extra_script_args": attr.string(default = ""),
        "_workspace_tool_py": attr.label(
            default = Label("@rules_uv_bare//uv/private:workspace_tool.py"),
            allow_single_file = [".py"],
        ),
        "_uv": attr.label(
            default = Label("@multitool//tools/uv"),
            executable = True,
            cfg = "exec",
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
    _uv_py_workspace_exec_rule(
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
    _uv_py_workspace_exec_rule(
        name = name,
        manifest = workspace + ".manifest",
        subcommand = "export",
        extra_script_args = '"$@"',
        visibility = visibility,
    )
