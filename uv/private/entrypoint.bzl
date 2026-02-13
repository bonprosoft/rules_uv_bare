"""uv_py_entrypoint and uv_py_test macros."""

def _uv_py_venv_target(rule_fn, name, workspace, cmd, **kwargs):
    if type(cmd) != "list":
        fail("cmd must be a list of strings. Got: " + type(cmd))
    cmd_parts = cmd
    args = ["$(rootpath " + workspace + ")"] + cmd_parts
    rule_fn(
        name = name,
        srcs = [Label("@rules_uv_bare//uv/private:venv_run.sh")],
        args = args,
        data = [workspace],
        **kwargs
    )

def uv_py_entrypoint(name, workspace, cmd, **kwargs):
    """Runs a command in the workspace venv.

    **Example**
    ```bzl
    uv_py_entrypoint(
        name = "run_app",
        workspace = ":my_workspace",
        cmd = ["python", "-m", "my_app"],
    )
    ```

    Args:
        name: target name.
        workspace: uv_py_workspace target.
        cmd: command as a list of strings (e.g. ``["python", "script.py"]``).
        **kwargs: additional arguments forwarded to ``sh_binary``.
    """
    _uv_py_venv_target(native.sh_binary, name, workspace, cmd, **kwargs)

def uv_py_test(name, workspace, cmd, **kwargs):
    """Runs a command in the workspace venv as a test.

    **Example**
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
        **kwargs: additional arguments forwarded to ``sh_test``.
    """
    tags = kwargs.pop("tags", []) + ["local"]
    _uv_py_venv_target(native.sh_test, name, workspace, cmd, tags = tags, **kwargs)
