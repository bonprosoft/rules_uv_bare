"""uv_py_deploy rule and macro."""

load("//uv/private:providers.bzl", "UvPyManifestInfo")

def _uv_py_deploy_rule_impl(ctx):
    info = ctx.attr.manifest[UvPyManifestInfo]

    deploy_config = {
        "uv_short_path": ctx.executable._uv.short_path,
        "target_platform": ctx.attr.target_platform,
        "python_version": ctx.attr.python_version,
    }
    config_file = ctx.actions.declare_file(ctx.attr.name + ".config.json")
    ctx.actions.write(output = config_file, content = json.encode(deploy_config))

    rf = "$0.runfiles/" + ctx.workspace_name + "/"
    tool_rf = rf + ctx.executable._workspace_tool.short_path

    exec_line = 'exec "{tool}" --manifest "{manifest}" --config "{config}" deploy --runfiles-dir "{rf}" "$@"'.format(
        tool = tool_rf,
        manifest = rf + info.manifest_file.short_path,
        config = rf + config_file.short_path,
        rf = rf,
    )

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

    return [DefaultInfo(executable = script, runfiles = runfiles)]

_uv_py_deploy_rule = rule(
    implementation = _uv_py_deploy_rule_impl,
    executable = True,
    attrs = {
        "manifest": attr.label(mandatory = True, providers = [UvPyManifestInfo]),
        "target_platform": attr.string(default = ""),
        "python_version": attr.string(mandatory = True),
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
    },
)

def uv_py_deploy(name, workspace, python_version, target_platform = ""):
    """Creates a deployment directory.

    **Usage**

    ```shell
    bazel run //:target -- /path/to/output
    ```

    For cross-platform packaging, use ``select()`` on ``target_platform``:

    ```bzl
    uv_py_deploy(
        name = "deploy",
        workspace = ":ws",
        python_version = "3.12",
        target_platform = select({
            "//:linux_x86_64": "x86_64-manylinux2014",
            "//:linux_aarch64": "aarch64-manylinux2014",
        }),
    )
    ```

    Args:
        name: target name.
        workspace: uv_py_workspace target.
        python_version: Target Python version (e.g. "3.12").
        target_platform: uv platform string (e.g. "x86_64-manylinux2014"),
            typically from ``select({...})``. Empty string means host.
    """
    _uv_py_deploy_rule(
        name = name,
        manifest = workspace + ".manifest",
        python_version = python_version,
        target_platform = target_platform,
    )
