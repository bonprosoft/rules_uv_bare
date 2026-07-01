"""Providers for rules_uv_bare."""

UvPyPackageInfo = provider(
    "Package info",
    fields = {
        "label_name": "Bazel label",
        "python_package_name": "Python package name",
        "pyproject": "The pyproject.toml File",
        "srcs": "Depset of source files",
        "data": "Depset of data files",
        "transitive_packages": "List of structs(**UvPyPackageInfo) including self",
        "transitive_wheels": "List of structs(**UvPyWheelInfo) including self",
    },
)

UvPyWheelInfo = provider(
    "Wheel info",
    fields = {
        "label_name": "Bazel label",
        "wheel": ".whl File",
        "python_package_name": "Python package name",
        "frozen": "If false, the hash is recomputed at build time",
    },
)

UvBuildEnvInfo = provider(
    "Environment variables and toolchain files to forward to uv sync and wheel builds.",
    fields = {
        "env": "Dict of environment variable name to value",
        "files": "Depset of files required by the environment (e.g. CC toolchain sysroot, runtime libs)",
    },
)

UvPyManifestInfo = provider(
    "uv workspace manifest Info (for internal use only)",
    fields = {
        "manifest_file": "JSON file for manifest",
        "lock_file": "uv.lock File",
        "wheel_files": "List of wheel File objects",
        "pyproject_inputs": "List of pyproject.toml File objects",
        "src_files": "Depset of source files",
        "data_files": "Depset of data files",
        "member_files": "Depset of all package files (pyproject + srcs + data) for direct and transitive members",
        "host_python": "uv python key for the host interpreter",
    },
)
