"""uv_py_deploy rule and macro."""

load("@rules_shell//shell:sh_binary.bzl", "sh_binary")

def uv_py_deploy(name, workspace, **kwargs):
    """Copies the ``.deploy`` build artifact to a user-specified directory.

    Args:
        name: target name.
        workspace: uv_py_workspace target.
        **kwargs: additional arguments forwarded to ``sh_binary``.
    """
    kwargs["tags"] = ["manual"] + kwargs.get("tags", [])
    sh_binary(
        name = name,
        srcs = [Label("@rules_uv_bare//uv/private:deploy_copy.sh")],
        args = ["$(rootpath " + workspace + ".deploy)"],
        data = [workspace + ".deploy"],
        **kwargs
    )
