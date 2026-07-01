"""Shared path helpers."""

def rlocation_key(short_path, workspace_name):
    """Return the canonical runfiles (rlocation) key for a file's short_path.

    Files in an external repository have a short_path of the form
    ``../<repo>/<path>``, whose rlocation key is ``<repo>/<path>``. For files in
    the main repo the key is ``<workspace_name>/<short_path>``.
    """
    if short_path.startswith("../"):
        return short_path[len("../"):]
    return workspace_name + "/" + short_path
