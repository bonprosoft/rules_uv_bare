"""Builds a .whl from a package directory using uv."""

from __future__ import annotations

import argparse
import json
import os
import pathlib
import subprocess
from typing import TypedDict

_DEFAULT_UV_CACHE_DIR = "/tmp/bazel-uv-cache"


class WheelConfig(TypedDict):
    pyproject_path: str
    output_dir: str
    uv_path: str
    python_path: str | None


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--config",
        type=pathlib.Path,
        required=True,
        help="Path to config JSON",
    )
    args = parser.parse_args()

    with args.config.open("r") as f:
        config: WheelConfig = json.load(f)

    pyproject_path = pathlib.Path(config["pyproject_path"]).resolve()
    pkg_dir = str(pyproject_path.parent)
    output_dir = config["output_dir"]
    uv_path = config["uv_path"]
    python_path = config["python_path"]

    cmd = [uv_path, "build", "--wheel"]
    if not os.environ.get("UV_CACHE_DIR"):
        cmd += ["--cache-dir", _DEFAULT_UV_CACHE_DIR]
    if python_path:
        cmd += ["--python", python_path]
    cmd += ["--out-dir", output_dir, pkg_dir]

    subprocess.run(cmd, check=True)


if __name__ == "__main__":
    main()
