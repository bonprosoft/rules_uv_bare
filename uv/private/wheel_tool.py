"""Builds a .whl from a package directory using uv."""

# /// script
# requires-python = ">=3.9"
# ///

from __future__ import annotations

import argparse
import json
import os
import pathlib
import subprocess
from typing import TypedDict

# Bazel sets UV_CACHE_DIR via uv_env.bzl. This is the fallback for direct invocation.
_DEFAULT_UV_CACHE_DIR = "/tmp/bazel-uv-cache"


class WheelConfig(TypedDict):
    pyproject_path: str
    output_dir: str
    uv_path: str
    host_python: str


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--config",
        type=pathlib.Path,
        required=True,
        help="Path to config JSON",
    )
    args = parser.parse_args()

    os.environ.setdefault("UV_CACHE_DIR", _DEFAULT_UV_CACHE_DIR)
    os.environ.setdefault(
        "UV_PYTHON_INSTALL_DIR", f"{os.environ['UV_CACHE_DIR']}/python"
    )

    with args.config.open("r") as f:
        config: WheelConfig = json.load(f)

    pyproject_path = pathlib.Path(config["pyproject_path"]).resolve()
    pkg_dir = str(pyproject_path.parent)
    output_dir = config["output_dir"]
    uv_path = config["uv_path"]
    host_python = config.get("host_python", "")

    python_path = ""
    if host_python:
        subprocess.check_call([uv_path, "python", "install", "--no-bin", host_python])
        python_path = subprocess.check_output(
            [uv_path, "python", "find", host_python],
            text=True,
        ).strip()

    cmd = [uv_path, "build", "--wheel"]
    if python_path:
        cmd += ["--python", python_path]
    cmd += ["--out-dir", output_dir, pkg_dir]

    subprocess.run(cmd, check=True)


if __name__ == "__main__":
    main()
