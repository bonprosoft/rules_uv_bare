"""uv_py_deploy macro."""

load("@rules_shell//shell:sh_binary.bzl", "sh_binary")

def uv_py_deploy(name, workspace, **kwargs):
    """Copies the ``.bundle`` build artifact to a user-specified directory.

    Args:
        name: target name.
        workspace: uv_py_workspace target.
        **kwargs: additional arguments forwarded to ``sh_binary``.
    """

    # Forces 'manual' as this sh_binary has the expensive `<workspace>.bundle` in its `data`.
    tags = kwargs.pop("tags", [])
    if "manual" not in tags:
        tags = tags + ["manual"]
    sh_binary(
        name = name,
        srcs = [Label("@rules_uv_bare//uv/private:bundle_copy.sh")],
        args = ["$(rootpath " + workspace + ".bundle)"],
        data = [workspace + ".bundle"],
        tags = tags,
        **kwargs
    )
