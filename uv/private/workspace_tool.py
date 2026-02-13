"""Workspace tool for rules_uv_bare."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import pathlib
import shutil
import subprocess
import sys
import tempfile
from typing import TypedDict


class PackageEntry(TypedDict):
    name: str
    pyproject_path: str
    pyproject_short_path: str


class WheelVariant(TypedDict):
    path: str
    short_path: str
    marker: str


class WheelEntry(TypedDict):
    name: str
    frozen: bool
    variants: list[WheelVariant]


class SharedManifest(TypedDict):
    ws_name: str
    python_requires: str
    lock_path: str
    lock_short_path: str
    packages: list[PackageEntry]
    wheels: list[WheelEntry]
    dependency_groups: dict[str, list[str]] | None
    extra_pyproject_content: str
    environments: list[str]


class BuildConfig(TypedDict):
    wdir_path: str
    root_file_path: str
    root_rel: str
    uv_sync_args: list[str]
    python_interpreter_path: str
    uv_path: str


class ExecConfig(TypedDict):
    exec_python_interpreter_short_path: str
    uv_short_path: str


class DeployConfig(TypedDict):
    uv_short_path: str
    target_platform: str
    python_version: str


class _WheelFileEntry(TypedDict):
    filename: str
    marker: str


def _resolve_output_dir(output_dir: str) -> str:
    # Resolve relative output_dir against user's working directory
    bwd = os.environ.get("BUILD_WORKING_DIRECTORY")
    if bwd and not os.path.isabs(output_dir):
        output_dir = os.path.join(bwd, output_dir)
    return output_dir


def _get_uv_cache_dir_args() -> list[str]:
    if not os.environ.get("UV_CACHE_DIR"):
        return ["--cache-dir", "/tmp/bazel-uv-cache"]
    # Use UV_CACHE_DIR provided by the user
    return []


def _generate_pyproject(
    ws_name: str,
    pkg_names: list[str],
    wheels: dict[str, list[_WheelFileEntry]],
    python_requires: str = "",
    dependency_groups: dict[str, list[str]] | None = None,
    extra_content: str = "",
    environments: list[str] | None = None,
) -> str:
    project_names = [n.replace("_", "-") for n in pkg_names]
    members_toml = ", ".join(f'".source/{n}"' for n in pkg_names)
    deps_parts = [f'"{p}"' for p in project_names]
    for name in wheels:
        deps_parts.append(f'"{name}"')
    deps_toml = ", ".join(deps_parts)
    sources_lines = [f"{p} = {{ workspace = true }}" for p in project_names]
    for name, variant_list in wheels.items():
        if len(variant_list) == 1 and not variant_list[0]["marker"]:
            # Simple format: single variant with no marker
            sources_lines.append(
                f'{name} = {{ path = ".wheels/{variant_list[0]["filename"]}" }}'
            )
        else:
            # List-with-markers format
            entries = []
            for v in variant_list:
                if v["marker"]:
                    entries.append(
                        f'  {{ path = ".wheels/{v["filename"]}", marker = "{v["marker"]}" }}'
                    )
                else:
                    entries.append(f'  {{ path = ".wheels/{v["filename"]}" }}')
            sources_lines.append(f"{name} = [")
            sources_lines.append(",\n".join(entries))
            sources_lines.append("]")
    sources_toml = "\n".join(sources_lines)

    lines = [
        "[project]",
        f'name = "{ws_name}"',
        'version = "0.0.0"',
    ]
    if python_requires:
        lines.append(f'requires-python = "{python_requires}"')

    lines.append(f"dependencies = [{deps_toml}]\n")

    if dependency_groups:
        lines.append("[dependency-groups]")
        for group_name, group_deps in dependency_groups.items():
            group_deps_toml = ", ".join(f'"{d}"' for d in group_deps)
            lines.append(f"{group_name} = [{group_deps_toml}]")
        lines.append("")

    markers = environments or []

    uv_section_lines = ["[tool.uv]", "package = false"]
    if markers:
        env_entries = ", ".join(f'"{m}"' for m in markers)
        uv_section_lines.append(f"environments = [{env_entries}]")

    lines += [
        "[tool.uv.workspace]",
        f"members = [{members_toml}]",
        "",
        *uv_section_lines,
        "",
        "[tool.uv.sources]",
        sources_toml,
    ]

    if extra_content:
        lines += ["", extra_content]

    return "\n".join(lines) + "\n"


def _create_package_symlinks(
    wdir: pathlib.Path,
    packages: list[PackageEntry],
    runfiles_dir: str | None = None,
) -> None:
    source_dir = wdir / ".source"
    source_dir.mkdir(parents=True, exist_ok=True)
    for pkg in packages:
        if runfiles_dir:
            pyproject_path = pathlib.Path(
                os.path.join(runfiles_dir, pkg["pyproject_short_path"])
            ).resolve()
        else:
            pyproject_path = pathlib.Path(pkg["pyproject_path"]).resolve()
        pkg_dir = pyproject_path.parent
        link = source_dir / pkg["name"]
        link.unlink(missing_ok=True)
        link.symlink_to(pkg_dir)


def _setup_wheels(
    wdir: pathlib.Path,
    wheels: list[WheelEntry],
    runfiles_dir: str | None = None,
    copy_wheel: bool = False,
) -> dict[str, list[_WheelFileEntry]]:
    if not wheels:
        return {}
    wheels_dir = wdir / ".wheels"
    wheels_dir.mkdir(parents=True, exist_ok=True)
    result: dict[str, list[_WheelFileEntry]] = {}
    for w in wheels:
        variant_entries: list[_WheelFileEntry] = []
        for v in w["variants"]:
            if runfiles_dir:
                src = pathlib.Path(os.path.join(runfiles_dir, v["short_path"]))
            else:
                src = pathlib.Path(v["path"]).resolve()
            filename = src.name
            dest = wheels_dir / filename
            if dest.is_symlink() or dest.exists():
                dest.unlink()
            if copy_wheel:
                shutil.copy2(str(src), str(dest))
            else:
                dest.symlink_to(src.resolve())
            variant_entries.append({"filename": filename, "marker": v["marker"]})
        result[w["name"]] = variant_entries
    return result


def _setup_workspace_dir(
    wdir: pathlib.Path,
    manifest: SharedManifest,
    runfiles_dir: str | None = None,
    copy_wheel: bool = False,
) -> dict[str, list[_WheelFileEntry]]:
    _create_package_symlinks(wdir, manifest["packages"], runfiles_dir=runfiles_dir)
    wheel_entries = _setup_wheels(
        wdir,
        manifest["wheels"],
        runfiles_dir=runfiles_dir,
        copy_wheel=copy_wheel,
    )

    pkg_names = [p["name"] for p in manifest["packages"]]
    pyproject_content = _generate_pyproject(
        ws_name=manifest["ws_name"],
        pkg_names=pkg_names,
        wheels=wheel_entries,
        python_requires=manifest["python_requires"],
        dependency_groups=manifest["dependency_groups"],
        extra_content=manifest["extra_pyproject_content"],
        environments=manifest["environments"],
    )
    (wdir / "pyproject.toml").write_text(pyproject_content)
    return wheel_entries


def cmd_build(manifest: SharedManifest, config: BuildConfig) -> None:
    uv_path = config["uv_path"]
    lock_path = pathlib.Path(manifest["lock_path"]).resolve()
    root_rel = config["root_rel"]
    root_dir = (lock_path.parent / root_rel).resolve()
    wdir = pathlib.Path(config["wdir_path"]).resolve()

    wheel_entries = _setup_workspace_dir(wdir, manifest)
    shutil.copy2(str(lock_path), str(wdir / "uv.lock"))

    python_path = config["python_interpreter_path"]

    # Collect unfrozen wheels whose hash has actually changed
    unfrozen_names = []
    lock_text = (wdir / "uv.lock").read_text()
    for w in manifest["wheels"]:
        if w["frozen"]:
            continue
        name = w["name"]
        if name not in wheel_entries:
            continue
        for variant in wheel_entries[name]:
            current_hash = hashlib.sha256(
                (wdir / ".wheels" / variant["filename"]).read_bytes()
            ).hexdigest()
            if f"sha256:{current_hash}" not in lock_text:
                unfrozen_names.append(name)
                break

    # Re-lock only wheels with changed hashes
    if unfrozen_names:
        print(
            f"WARNING: lock file is out of date for: {', '.join(unfrozen_names)}. "
            f"Consider updating uv.lock.",
            flush=True,
        )
        uv_lock_cmd = [uv_path, "lock", "--project", str(wdir)]
        for name in unfrozen_names:
            uv_lock_cmd += ["--upgrade-package", name]
        uv_lock_cmd += _get_uv_cache_dir_args()
        if python_path:
            uv_lock_cmd += ["--python", python_path]
        subprocess.run(uv_lock_cmd, check=True)

    uv_sync_args = config["uv_sync_args"]
    uv_cmd = [uv_path, "sync", "--frozen", "--all-groups", "--project", str(wdir)]
    uv_cmd += _get_uv_cache_dir_args()
    if python_path:
        uv_cmd += ["--python", python_path]
    uv_cmd += uv_sync_args
    subprocess.run(uv_cmd, check=True)

    # Remove .source/ symlinks.
    # Otherwise, Bazel would rebuild every time if any file in the directory that the symlinks point to is changed, regardless of ``srcs``, ``data`` attributes specified in ``uv_py_package``, because of the tree artifact mechanism.
    # The symlinks are only needed during `uv sync`; the installed venv uses .pth files that point directly to the source tree, not through .source/.
    source_dir = wdir / ".source"
    if source_dir.exists():
        shutil.rmtree(str(source_dir))

    venv_python = str(wdir / ".venv" / "bin" / "python")
    result = subprocess.run(
        [
            venv_python,
            "-c",
            "import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}')",
        ],
        capture_output=True,
        text=True,
        check=True,
    )
    python_version = result.stdout.strip()

    root_file_path = pathlib.Path(config["root_file_path"])
    lines = [str(wdir), str(root_dir), python_version]
    root_file_path.write_text("\n".join(lines) + "\n")


def cmd_lock(manifest: SharedManifest, config: ExecConfig, runfiles_dir: str) -> None:
    uv_path = os.path.join(runfiles_dir, config["uv_short_path"])
    lock_real = pathlib.Path(
        os.path.join(runfiles_dir, manifest["lock_short_path"])
    ).resolve()

    with tempfile.TemporaryDirectory() as tmpdir:
        wdir = pathlib.Path(tmpdir)

        _setup_workspace_dir(wdir, manifest, runfiles_dir=runfiles_dir)

        had_old_lock = False
        if lock_real.exists() and lock_real.stat().st_size > 0:
            shutil.copy2(str(lock_real), str(wdir / "uv.lock"))
            had_old_lock = True

        python_short_path = config["exec_python_interpreter_short_path"]
        python_path = (
            os.path.join(runfiles_dir, python_short_path) if python_short_path else ""
        )
        uv_lock_cmd = [uv_path, "lock"]
        # Without --upgrade-package, uv skips re-resolving wheels whose version
        # hasn't changed, so content hash changes (e.g. rebuilt native wheels)
        # are not reflected to uv.lock.
        # https://github.com/astral-sh/uv/blob/8c8a90306b70f03bc8388a99fae0aba984ad685c/crates/uv-resolver/src/lock/mod.rs#L1654
        for w in manifest["wheels"]:
            uv_lock_cmd += ["--upgrade-package", w["name"]]
        if python_path:
            uv_lock_cmd += ["--python", python_path]
        result = subprocess.run(uv_lock_cmd, cwd=str(wdir))
        if result.returncode != 0 and had_old_lock:
            (wdir / "uv.lock").unlink(missing_ok=True)
            print("Retrying uv lock without existing lock file...")
            subprocess.run(uv_lock_cmd, cwd=str(wdir), check=True)
        elif result.returncode != 0:
            sys.exit(result.returncode)

        shutil.copy2(str(wdir / "uv.lock"), str(lock_real))
        print(f"Wrote {lock_real}")


def cmd_export(
    manifest: SharedManifest,
    config: ExecConfig,
    runfiles_dir: str,
    output_dir: str,
) -> None:
    out = pathlib.Path(_resolve_output_dir(output_dir))
    out.mkdir(parents=True, exist_ok=True)

    _setup_workspace_dir(out, manifest, runfiles_dir=runfiles_dir, copy_wheel=True)

    lock_src = pathlib.Path(
        os.path.join(runfiles_dir, manifest["lock_short_path"])
    ).resolve()
    shutil.copy2(str(lock_src), str(out / "uv.lock"))

    print(f"Exported workspace to {out}")


def cmd_deploy(
    manifest: SharedManifest,
    config: DeployConfig,
    runfiles_dir: str,
    output_dir: str,
) -> None:
    out = pathlib.Path(_resolve_output_dir(output_dir))
    out.mkdir(parents=True, exist_ok=True)

    uv_path = os.path.join(runfiles_dir, config["uv_short_path"])

    with tempfile.TemporaryDirectory() as tmpdir:
        wdir = pathlib.Path(tmpdir)
        _setup_workspace_dir(wdir, manifest, runfiles_dir=runfiles_dir)

        lock_src = pathlib.Path(
            os.path.join(runfiles_dir, manifest["lock_short_path"])
        ).resolve()
        shutil.copy2(str(lock_src), str(wdir / "uv.lock"))

        # Export lock file to requirements.txt
        requirements_txt = wdir / "requirements.txt"
        export_cmd = [
            uv_path,
            "export",
            "--frozen",
            "--all-groups",
            "--no-hashes",
            "--no-header",
            "--no-editable",
            "--project",
            str(wdir),
            "--output-file",
            str(requirements_txt),
        ]
        subprocess.run(export_cmd, cwd=wdir, check=True)

        # Install packages into output directory
        install_cmd = [
            uv_path,
            "pip",
            "install",
            "-r",
            str(requirements_txt),
            "--prefix",
            str(out),
        ]
        python_version = config["python_version"]
        if python_version:
            install_cmd += ["--python", python_version]
        target_platform = config["target_platform"]
        if target_platform:
            install_cmd += ["--python-platform", target_platform]

        subprocess.run(install_cmd, cwd=wdir, check=True)

    print(f"Deployed to {out}")


def main() -> None:
    parser = argparse.ArgumentParser(description="rules_uv_bare workspace tool")
    parser.add_argument(
        "--manifest",
        type=pathlib.Path,
        required=True,
        help="Path to workspace manifest",
    )
    parser.add_argument(
        "--config",
        type=pathlib.Path,
        required=True,
        help="Path to verb-specific config",
    )
    subparsers = parser.add_subparsers(dest="command", required=True)

    subparsers.add_parser("build", help="Build workspace venv")

    lock_parser = subparsers.add_parser("lock", help="Update uv.lock")
    lock_parser.add_argument(
        "--runfiles-dir",
        required=True,
        help="Runfiles base directory for resolving paths",
    )

    export_parser = subparsers.add_parser(
        "export",
        help="Export portable workspace directory",
    )
    export_parser.add_argument(
        "--runfiles-dir",
        required=True,
        help="Runfiles base directory for resolving paths",
    )
    export_parser.add_argument(
        "output_dir",
        help="Output directory for the exported workspace",
    )

    deploy_parser = subparsers.add_parser("deploy", help="Deploy workspace packages")
    deploy_parser.add_argument(
        "--runfiles-dir",
        required=True,
        help="Runfiles base directory for resolving paths",
    )
    deploy_parser.add_argument(
        "output_dir",
        help="Output directory for deployment",
    )

    args = parser.parse_args()

    with args.manifest.open("r") as f:
        manifest = json.load(f)
    with args.config.open("r") as f:
        config = json.load(f)

    if args.command == "build":
        cmd_build(manifest, config)
    elif args.command == "lock":
        cmd_lock(manifest, config, args.runfiles_dir)
    elif args.command == "export":
        cmd_export(manifest, config, args.runfiles_dir, args.output_dir)
    elif args.command == "deploy":
        cmd_deploy(manifest, config, args.runfiles_dir, args.output_dir)


if __name__ == "__main__":
    main()
