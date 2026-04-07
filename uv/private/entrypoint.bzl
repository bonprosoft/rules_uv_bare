"""uv_py_entrypoint and uv_py_test rules."""

def _shell_double_quote(s):
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"').replace("`", "\\`") + '"'

def _uv_py_venv_target_impl(ctx):
    root_file = ctx.attr.workspace[DefaultInfo].files.to_list()[0]

    # Wrap each element with double-quote so $(rlocation ...) will be expanded.
    cmd_str = " ".join([_shell_double_quote(c) for c in ctx.attr.cmd])

    rlocation_root_file = ctx.workspace_name + "/" + root_file.short_path

    script = ctx.actions.declare_file(ctx.attr.name)
    ctx.actions.expand_template(
        template = ctx.file._script_template,
        output = script,
        substitutions = {
            "@@RLOCATION_ROOT_FILE@@": rlocation_root_file,
            "@@CMD@@": cmd_str,
        },
        is_executable = True,
    )

    # Collect runfiles from workspace, data, and the bash runfiles library.
    runfiles = ctx.runfiles()
    runfiles = runfiles.merge(ctx.attr.workspace[DefaultInfo].default_runfiles)
    runfiles = runfiles.merge(ctx.attr._runfiles_lib[DefaultInfo].default_runfiles)
    for d in ctx.attr.data:
        runfiles = runfiles.merge(d[DefaultInfo].default_runfiles)
        runfiles = runfiles.merge(ctx.runfiles(transitive_files = d[DefaultInfo].files))

    return [DefaultInfo(executable = script, runfiles = runfiles)]

_COMMON_ATTRS = {
    "workspace": attr.label(mandatory = True),
    "cmd": attr.string_list(mandatory = True),
    "data": attr.label_list(default = [], allow_files = True),
    "_script_template": attr.label(
        default = Label("@rules_uv_bare//uv/private:venv_entrypoint.sh.tpl"),
        allow_single_file = True,
    ),
    "_runfiles_lib": attr.label(
        default = "@rules_shell//shell/runfiles",
    ),
}

_uv_py_entrypoint_rule = rule(
    implementation = _uv_py_venv_target_impl,
    executable = True,
    attrs = _COMMON_ATTRS,
)

_uv_py_venv_test = rule(
    implementation = _uv_py_venv_target_impl,
    test = True,
    attrs = _COMMON_ATTRS,
)

def uv_py_entrypoint(name, workspace, cmd, **kwargs):
    """Runs a command in the workspace venv.

    ``cmd`` is embedded in the built binary, so both ``bazel run``
    and direct invocation (``./bazel-bin/<name>``) work.

    ``rlocation`` bash function is supported in ``cmd`` to reference data files.

    ```bzl
    uv_py_entrypoint(
        name = "run_app",
        workspace = ":my_workspace",
        cmd = ["python", "$(rlocation my_repo/app/script.py)"],
        data = ["//app:script.py"],
    )
    ```

    Args:
        name: target name.
        workspace: uv_py_workspace target.
        cmd: command as a list of strings (e.g. ``["python", "script.py"]``).
            Supports ``$(rlocation REPO/path)`` for referencing runfiles.
        **kwargs: additional arguments forwarded to the underlying rule.
    """
    _uv_py_entrypoint_rule(name = name, workspace = workspace, cmd = cmd, **kwargs)

def uv_py_test(name, workspace, cmd, **kwargs):
    """Runs a command in the workspace venv as a test.

    See ``uv_py_entrypoint`` for details on ``cmd`` and ``rlocation`` support.

    ```bzl
    uv_py_test(
        name = "test_app",
        workspace = ":my_workspace",
        cmd = ["python", "-m", "pytest", "tests/"],
    )
    ```

    Args:
        name: target name.
        workspace: uv_py_workspace target.
        cmd: command as a list of strings (e.g. ``["python", "-m", "pytest", "tests/"]``).
            Supports ``$(rlocation REPO/path)`` for referencing runfiles.
        **kwargs: additional arguments forwarded to the underlying rule.
    """
    tags = kwargs.pop("tags", []) + ["local"]
    _uv_py_venv_test(name = name, workspace = workspace, cmd = cmd, tags = tags, **kwargs)
