"""Workspace tool for rules_uv_bare."""

# /// script
# requires-python = ">=3.9"
# ///

from __future__ import annotations

import argparse
import dataclasses
import hashlib
import json
import os
import pathlib
import shutil
import subprocess
import sys
import tempfile
from typing import TypedDict

_EXEC_ROOT_MARKER = "$$EXEC_ROOT$$/"


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


class Manifest(TypedDict):
    ws_name: str
    host_python: str
    python_requires: str
    lock_path: str
    lock_short_path: str
    packages: list[PackageEntry]
    wheels: list[WheelEntry]
    dependency_groups: dict[str, list[str]]
    extra_pyproject_content: str
    environments: list[str]


class BuildConfig(TypedDict):
    wdir_path: str
    root_file_path: str
    uv_path: str


class RunfilesConfig(TypedDict):
    uv_short_path: str


class DeployConfig(TypedDict):
    deploy_dir_path: str
    uv_path: str
    deploy_target_platform: str
    manylinux: str
    build_deps: list[str]
    bundle_python: bool


@dataclasses.dataclass(frozen=True)
class ResolvedPython:
    key: str
    implementation: str
    major: int
    minor: int
    os: str
    arch: str
    libc: str

    @property
    def version(self) -> str:
        return f"{self.major}.{self.minor}"


class _WheelFileEntry(TypedDict):
    filename: str
    marker: str


def _resolve_output_dir(output_dir: str) -> str:
    # Resolve relative output_dir against user's working directory
    build_working_dir = os.environ.get("BUILD_WORKING_DIRECTORY")
    if build_working_dir and not os.path.isabs(output_dir):
        output_dir = os.path.join(build_working_dir, output_dir)
    return output_dir


def _resolve_exec_root_markers() -> None:
    exec_root = os.getcwd()
    for key, value in list(os.environ.items()):
        if _EXEC_ROOT_MARKER in value:
            os.environ[key] = value.replace(_EXEC_ROOT_MARKER, exec_root + "/")


# NOTE: Bazel sets UV_CACHE_DIR via uv_env.bzl. This is just fallback for direct invocation.
UV_CACHE_DIR = os.environ.get("UV_CACHE_DIR") or "/tmp/bazel-uv-cache"


def _generate_pyproject(
    ws_name: str,
    pkg_names: list[str],
    wheels: dict[str, list[_WheelFileEntry]],
    python_requires: str = "",
    dependency_groups: dict[str, list[str]] | None = None,
    extra_content: str = "",
    environments: list[str] | None = None,
) -> str:
    # WARNING: Do not use table.
    # If `extra_content` defines the same table (e.g., `[tool.uv]`), an error would occur.
    project_names = [n.replace("_", "-") for n in pkg_names]
    members_toml = ", ".join(f'".source/{n}"' for n in pkg_names)
    deps_parts = [f'"{p}"' for p in project_names]
    for name in wheels:
        deps_parts.append(f'"{name}"')
    deps_toml = ", ".join(deps_parts)
    sources_lines = [
        f"tool.uv.sources.{p} = {{ workspace = true }}" for p in project_names
    ]
    for name, variant_list in wheels.items():
        if len(variant_list) == 1 and not variant_list[0]["marker"]:
            # Simple format: single variant with no marker
            sources_lines.append(
                f'tool.uv.sources.{name} = {{ path = ".wheels/{variant_list[0]["filename"]}" }}'
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
            sources_lines.append(f"tool.uv.sources.{name} = [")
            sources_lines.append(",\n".join(entries))
            sources_lines.append("]")
    sources_toml = "\n".join(sources_lines)

    lines = ["tool.uv.package = false"]
    if environments:
        env_entries = ", ".join(f'"{m}"' for m in environments)
        lines.append(f"tool.uv.environments = [{env_entries}]")

    lines += [
        "",
        f'project.name = "{ws_name}"',
        'project.version = "0.0.0"',
    ]
    if python_requires:
        lines.append(f'project.requires-python = "{python_requires}"')

    lines.append(f"project.dependencies = [{deps_toml}]\n")

    if dependency_groups:
        for group_name, group_deps in dependency_groups.items():
            group_deps_toml = ", ".join(f'"{d}"' for d in group_deps)
            lines.append(f"dependency-groups.{group_name} = [{group_deps_toml}]")
        lines.append("")

    lines += [
        f"tool.uv.workspace.members = [{members_toml}]",
        "",
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
            dest.unlink(missing_ok=True)
            if copy_wheel:
                shutil.copy2(str(src), str(dest))
            else:
                dest.symlink_to(src.resolve())
            variant_entries.append({"filename": filename, "marker": v["marker"]})
        result[w["name"]] = variant_entries
    return result


def _setup_workspace_dir(
    wdir: pathlib.Path,
    manifest: Manifest,
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


def _relock_unfrozen_wheels(
    wdir: pathlib.Path,
    manifest: Manifest,
    wheel_entries: dict[str, list[_WheelFileEntry]],
    uv_path: str,
    python_path: str,
) -> None:
    # Unfrozen wheels (``uv_py_import_wheel(frozen = False, ...)``) are rebuilt by Bazel,
    # so their content hash can change. Otherwise, ``uv sync --frozen`` would reject the mismatch.
    unfrozen_names: list[str] = []
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

    if not unfrozen_names:
        return

    print(
        f"WARNING: lock file is out of date for: {', '.join(unfrozen_names)}. "
        f"Consider updating uv.lock.",
        flush=True,
    )
    uv_lock_cmd = [uv_path, "lock", "--project", str(wdir)]
    for name in unfrozen_names:
        uv_lock_cmd += ["--upgrade-package", name]
    if python_path:
        uv_lock_cmd += ["--python", python_path]
    subprocess.check_call(uv_lock_cmd)


def cmd_build(manifest: Manifest, config: BuildConfig) -> None:
    uv_path = config["uv_path"]
    lock_path = pathlib.Path(manifest["lock_path"]).resolve()
    wdir = pathlib.Path(config["wdir_path"]).resolve()

    wheel_entries = _setup_workspace_dir(wdir, manifest)
    shutil.copy2(str(lock_path), str(wdir / "uv.lock"))

    python_path = _install_managed_python(uv_path, manifest["host_python"])

    _relock_unfrozen_wheels(wdir, manifest, wheel_entries, uv_path, python_path)

    uv_cmd = [uv_path, "sync", "--frozen", "--all-groups", "--project", str(wdir)]
    uv_cmd += ["--python", python_path]
    subprocess.check_call(uv_cmd)

    # Remove .source/ symlinks.
    # Otherwise, Bazel would rebuild every time if any file in the directory that the symlinks point to is changed, regardless of ``srcs``, ``data`` attributes specified in ``uv_py_package``, because of the tree artifact mechanism.
    # The symlinks are only needed during `uv sync`; the installed venv uses .pth files that point directly to the source tree, not through .source/.
    source_dir = wdir / ".source"
    if source_dir.exists():
        shutil.rmtree(str(source_dir))

    pathlib.Path(config["root_file_path"]).write_text(f"{wdir}\n")


def cmd_lock(manifest: Manifest, config: RunfilesConfig, runfiles_dir: str) -> None:
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

        python_path = _install_managed_python(uv_path, manifest["host_python"])
        uv_lock_cmd = [uv_path, "lock"]
        # Without --upgrade-package, uv skips re-resolving wheels whose version
        # hasn't changed, so content hash changes (e.g. rebuilt native wheels)
        # are not reflected to uv.lock.
        # https://github.com/astral-sh/uv/blob/8c8a90306b70f03bc8388a99fae0aba984ad685c/crates/uv-resolver/src/lock/mod.rs#L1654
        for w in manifest["wheels"]:
            uv_lock_cmd += ["--upgrade-package", w["name"]]
        uv_lock_cmd += ["--python", python_path]
        result = subprocess.run(uv_lock_cmd, cwd=str(wdir))
        if result.returncode != 0 and had_old_lock:
            (wdir / "uv.lock").unlink(missing_ok=True)
            print("Retrying uv lock without existing lock file...")
            subprocess.check_call(uv_lock_cmd, cwd=str(wdir))
        elif result.returncode != 0:
            sys.exit(result.returncode)

        shutil.copy2(str(wdir / "uv.lock"), str(lock_real))
        print(f"Wrote {lock_real}")


def cmd_export(
    manifest: Manifest,
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


def _create_relocatable_venv(
    uv_path: str,
    deploy_dir: pathlib.Path,
    python_path: str,
) -> None:
    cmd = [
        uv_path,
        "venv",
        "--relocatable",
        "--allow-existing",
        "--python",
        python_path,
        str(deploy_dir),
    ]
    subprocess.check_call(cmd)


def _setup_build_tools_venv(
    uv_path: str,
    build_venv: pathlib.Path,
    build_deps: list[str],
    python_path: str,
) -> tuple[str, str]:
    # Create a host-platform build-tools venv. Returns (site_packages, bin).
    venv_cmd = [uv_path, "venv", "--python", python_path, str(build_venv)]
    subprocess.check_call(venv_cmd)

    build_python = str(build_venv / "bin" / "python")
    install_cmd = [uv_path, "pip", "install", "--python", build_python]
    install_cmd += sorted(build_deps)
    subprocess.check_call(install_cmd)

    site_packages = subprocess.check_output(
        [build_python, "-c", "import site; print(site.getsitepackages()[0])"],
        text=True,
    ).strip()
    return site_packages, str(build_venv / "bin")


def _resolve_uv_python(uv_path: str, key: str) -> ResolvedPython:
    assert key
    entries = json.loads(
        subprocess.check_output(
            [uv_path, "python", "list", "--output-format", "json", key],
            text=True,
        )
    )
    if not entries:
        raise SystemExit(
            f"uv python list did not return any entry for {key!r}. "
            f"Pass a key like 'cpython-3.12' or 'cpython-3.12-linux-aarch64-gnu'."
        )
    entry = entries[0]

    return ResolvedPython(
        key=entry["key"],
        implementation=entry["implementation"],
        major=int(entry["version_parts"]["major"]),
        minor=int(entry["version_parts"]["minor"]),
        os=entry["os"],
        arch=entry["arch"],
        libc=entry["libc"],
    )


def _uv_python_platform_for_target(target: ResolvedPython, manylinux: str) -> str:
    # Return uv's --python-platform string for a cross-compile target.
    if target.os == "linux" and target.libc == "gnu":
        baseline = manylinux or "manylinux2014"
        return f"{target.arch}-{baseline}"
    if target.os == "linux" and target.libc == "musl":
        return f"{target.arch}-unknown-linux-musl"
    if target.os == "macos":
        return f"{target.arch}-apple-darwin"
    raise SystemExit(
        f"Unsupported cross-compile target {target.key!r}: os={target.os} libc={target.libc}"
    )


def _install_managed_python(uv_path: str, key: str) -> str:
    # Install a uv-managed Python idempotently and return its interpreter path.
    subprocess.check_call([uv_path, "python", "install", "--no-bin", key])
    out = subprocess.check_output([uv_path, "python", "find", key], text=True)
    return str(pathlib.Path(out.strip()).resolve())


def _install_python(
    uv_path: str,
    install_dir: pathlib.Path,
    resolved_key: str,
) -> pathlib.Path:
    # `resolved_key` must be the canonical key from _resolve_uv_python so it
    # matches the on-disk install-dir name.
    cmd = [uv_path, "python", "install", "--no-bin", "-i", str(install_dir), resolved_key]
    subprocess.check_call(cmd)

    # Drop shorthand symlinks (e.g. "cpython-3.12" -> full-key dir) so the
    # deploy artifact stays minimal.
    for d in install_dir.iterdir():
        if d.is_symlink():
            d.unlink()

    python_bin = install_dir / resolved_key / "bin" / "python3"
    if not python_bin.exists():
        raise RuntimeError(f"No Python installation found at {python_bin}")
    return python_bin


def _read_target_sysconfig(
    host_python_bin: pathlib.Path,
    target_python_prefix: pathlib.Path,
    minor: int,
    keys: list[str],
) -> dict[str, str]:
    lib_dir = target_python_prefix / "lib" / f"python3.{minor}"
    candidates = sorted(lib_dir.glob("_sysconfigdata*.py"))
    if not candidates:
        return {}
    script = (
        "import importlib.util, json, sys\n"
        f"spec = importlib.util.spec_from_file_location('_scd', {str(candidates[0])!r})\n"
        "mod = importlib.util.module_from_spec(spec)\n"
        "spec.loader.exec_module(mod)\n"
        f"json.dump({{k: mod.build_time_vars.get(k, '') for k in {keys!r}}}, sys.stdout)\n"
    )
    return json.loads(
        subprocess.check_output([str(host_python_bin), "-c", script], text=True)
    )


def _clear_python_links(bin_dir: pathlib.Path) -> None:
    for p in bin_dir.glob("python*"):
        if p.is_symlink() or p.is_file():
            p.unlink()


def _link_python_aliases(bin_dir: pathlib.Path, minor: int) -> None:
    (bin_dir / "python").symlink_to("python3")
    (bin_dir / f"python3.{minor}").symlink_to("python3")


def _link_bundled_python(
    deploy_dir: pathlib.Path,
    installed_key: str,
    minor: int,
) -> None:
    assert (deploy_dir / "python").is_dir()

    bin_dir = deploy_dir / "bin"
    _clear_python_links(bin_dir)
    rel = pathlib.Path("..") / "python" / installed_key / "bin" / f"python3.{minor}"
    (bin_dir / "python3").symlink_to(rel)
    _link_python_aliases(bin_dir, minor)


def _install_host_python_shim(deploy_dir: pathlib.Path, minor: int) -> None:
    # Without a bundled interpreter, uv's relocatable-venv python links point at
    # a temp dir about to be deleted. Replace them with a shim that finds a host
    # python3 at runtime, so the deploy artifact has no dangling symlinks.
    bin_dir = deploy_dir / "bin"
    _clear_python_links(bin_dir)
    shim_path = bin_dir / "python3"
    shim_path.write_text(
        rf"""#!/bin/bash
# Auto-generated by rules_uv_bare for deploy_bundle_python=False.
# Finds a host Python on PATH, preferring python3.{minor} for ABI match with
# the compiled extension modules in this venv. Uses `exec -a` so argv[0]
# points into the deploy bin/, which is how Python locates pyvenv.cfg and
# activates the relocatable venv.
set -eu

if command -v realpath >/dev/null 2>&1; then
    resolve() {{ realpath "$1"; }}
else
    # Should be good on mac 12.3+.
    resolve() {{ readlink -f "$1"; }}
fi

self="$(resolve "$0")"

find_interpreter() {{
    for candidate in $(which -a "$1" 2>/dev/null); do
        [ -x "$candidate" ] || continue
        real="$(resolve "$candidate" 2>/dev/null)" || continue
        if [ "$real" != "$self" ]; then
            printf '%s\n' "$candidate"
            return 0
        fi
    done
    return 1
}}

run() {{
    local py="$1"
    shift
    local py_resolved python_home
    py_resolved="$(resolve "$py")"
    python_home="$(dirname "$(dirname "$py_resolved")")"
    export PYTHONHOME="$python_home"
    exec -a "$self" "$py" "$@"
}}

if py="$(find_interpreter "python3.{minor}")"; then run "$py" "$@"; fi
if py="$(find_interpreter "python3")"; then run "$py" "$@"; fi

echo "no host python3.{minor} or python3 found on PATH (excluding $(dirname "$self"))" >&2
exit 127
"""
    )
    shim_path.chmod(0o755)

    _link_python_aliases(bin_dir, minor)


def _configure_build_env(
    uv_path: str,
    wdir: pathlib.Path,
    host_python_bin: pathlib.Path,
    target_python_bin: pathlib.Path,
    target: ResolvedPython,
    is_cross: bool,
    build_deps: list[str],
) -> dict[str, str]:
    # Build env for uv sync. Adds cross-compile flags when is_cross.
    build_env = os.environ.copy()
    build_env.pop("VIRTUAL_ENV", None)
    build_env["UV_NO_MANAGED_PYTHON"] = "1"

    if not is_cross:
        return build_env

    target_python_prefix = target_python_bin.parents[1]
    cc = build_env.get("CC", "cc")

    sysconfig = _read_target_sysconfig(
        host_python_bin,
        target_python_prefix,
        target.minor,
        ["LDSHARED", "CCSHARED", "MACOSX_DEPLOYMENT_TARGET", "EXT_SUFFIX"],
    )

    macosx_dt = sysconfig.get("MACOSX_DEPLOYMENT_TARGET", "")
    if target.os == "macos":
        # Python's platform string uses "arm64" where uv/Bazel use "aarch64".
        platform_arch = "arm64" if target.arch == "aarch64" else target.arch
        # macOS host platform needs the deployment-target version from sysconfig.
        host_platform = (
            f"macosx-{macosx_dt}-{platform_arch}"
            if macosx_dt
            else f"macosx-11.0-{platform_arch}"
        )
    else:
        host_platform = f"{target.os}-{target.arch}"
    build_env["_PYTHON_HOST_PLATFORM"] = host_platform

    ext_suffix = sysconfig.get("EXT_SUFFIX", "")
    if ext_suffix:
        build_env["SETUPTOOLS_EXT_SUFFIX"] = ext_suffix

    # Replace LDSHARED's compiler (first token) with our CC while keeping
    # target-specific linker flags (e.g. -bundle on macOS, -shared on Linux).
    target_ldshared = sysconfig.get("LDSHARED", "")
    if target_ldshared and " " in target_ldshared:
        build_env["LDSHARED"] = f"{cc} {target_ldshared.split(maxsplit=1)[1]}"
    else:
        build_env["LDSHARED"] = f"{cc} -shared"

    build_env["ARCHFLAGS"] = ""
    if macosx_dt:
        build_env["MACOSX_DEPLOYMENT_TARGET"] = macosx_dt

    # On macOS, -mmacosx-version-min is appended AFTER the toolchain's flags
    # so it overrides the toolchain default.
    include_path = target_python_prefix / "include" / f"python3.{target.minor}"
    if include_path.is_dir():
        ccshared = sysconfig.get("CCSHARED", "")
        prefix = " ".join(filter(None, [f"-I{include_path}", ccshared]))
        suffix = f"-mmacosx-version-min={macosx_dt}" if macosx_dt else ""
        for var in ("CFLAGS", "CXXFLAGS"):
            existing = build_env.get(var, "")
            build_env[var] = " ".join(filter(None, [prefix, existing, suffix]))
        if suffix:
            existing_ld = build_env.get("LDFLAGS", "")
            build_env["LDFLAGS"] = f"{existing_ld} {suffix}".strip()

    if build_deps:
        site_packages, bin_dir = _setup_build_tools_venv(
            uv_path, wdir / ".build_venv", build_deps, str(host_python_bin)
        )
        existing = build_env.get("PYTHONPATH", "")
        build_env["PYTHONPATH"] = site_packages + (":" + existing if existing else "")
        build_env["PATH"] = bin_dir + ":" + build_env.get("PATH", "")

    return build_env


def _prime_uv_interpreter_cache(
    uv_path: str, deploy_dir: pathlib.Path, platform_cache: str
) -> None:
    """Pre-populate uv's interpreter-info cache so the upcoming `uv sync` can skip the probe.

    Motivation: the cross-compile path below runs `uv sync` with
    `_PYTHON_HOST_PLATFORM=<target>` in the environment.
    That env var leaks into uv's interpreter probe (`get_interpreter_info.py`),
    where `sysconfig.get_platform()` returns it verbatim.
    When the target is `linux-*` and the host is macOS, the probe enters its glibc/musl detection branch and fails with:

        error: Can't use Python at `<deploy_dir/bin/python3>`
          Caused by: Could not detect a glibc or a musl libc (while running on Linux)

    Therefore, we prime uv's cache BEFORE the sync with a trivial `uv pip list` run
    without `_PYTHON_HOST_PLATFORM`, so the upcoming sync with `_PYTHON_HOST_PLATFORM`
    hits the cached entry and skips the probe entirely.

    Note that prime and sync must target the SAME executable.
    uv picks `bin/python3` over `bin/python` on non windows environment, regardless of what we
    pass via `--python`.
    https://github.com/astral-sh/uv/blob/45bf2f9ea6131c90f85678e7b393f7be97e19239/crates/uv-python/src/virtualenv.rs#L217-L229
    """

    subprocess.run(
        [
            uv_path,
            "pip",
            "list",
            "--python",
            str(deploy_dir / "bin" / "python3"),
            "--cache-dir",
            platform_cache,
        ],
        capture_output=True,
    )


def cmd_deploy(manifest: Manifest, config: DeployConfig) -> None:
    uv_path = str(pathlib.Path(config["uv_path"]).resolve())
    # deploy_dir must be absolute since uv resolves UV_PROJECT_ENVIRONMENT
    # relative to --project.
    deploy_dir = pathlib.Path(config["deploy_dir_path"]).resolve()
    lock_path = pathlib.Path(manifest["lock_path"])

    if not manifest["host_python"]:
        raise SystemExit(
            "uv python key is empty. Set host_python on uv_py_workspace "
            '(e.g. host_python = "cpython-3.12").'
        )

    host = _resolve_uv_python(uv_path, manifest["host_python"])
    target = host
    is_cross = False

    deploy_target_platform = config["deploy_target_platform"]
    if deploy_target_platform:
        target_key = f"{host.implementation}-{host.version}-{deploy_target_platform}"
        target = _resolve_uv_python(uv_path, target_key)
        is_cross = (host.os, host.arch) != (target.os, target.arch)

    bundle_python = config["bundle_python"]

    with tempfile.TemporaryDirectory() as tmpdir:
        wdir = pathlib.Path(tmpdir)
        wheel_entries = _setup_workspace_dir(wdir, manifest)
        shutil.copy2(str(lock_path), str(wdir / "uv.lock"))

        if bundle_python:
            target_python_bin = _install_python(
                uv_path, deploy_dir / "python", target.key
            )
        else:
            # Install the target interpreter into the temp dir.
            # Even if `bundle_python` is False, the target python is needed to read sysconfig data.
            target_python_bin = _install_python(
                uv_path, wdir / ".target_python", target.key
            )

        # WARNING: host_python_bin must be a NON-managed interpreter. Creating the
        # venv with a uv-managed interpreter would make `uv sync` remove deploy_dir.
        # Non-cross: the bundled interpreter is host-runnable and non-managed.
        host_python_bin = target_python_bin.resolve()

        if is_cross:
            # Cross-compile: the target interpreter can't run on the host, so
            # install a host-arch interpreter into a temp, non-managed dir.
            host_python_bin = _install_python(
                uv_path, wdir / ".host_python", host.key
            ).resolve()

        _relock_unfrozen_wheels(
            wdir, manifest, wheel_entries, uv_path, str(host_python_bin)
        )
        build_env = _configure_build_env(
            uv_path,
            wdir,
            host_python_bin,
            target_python_bin,
            target,
            is_cross,
            config["build_deps"],
        )

        # Create venv into deploy_dir with **host_python_bin**.
        _create_relocatable_venv(uv_path, deploy_dir, str(host_python_bin))

        build_env["UV_PROJECT_ENVIRONMENT"] = str(deploy_dir)
        sync_cmd = [
            str(uv_path),
            "sync",
            "--frozen",
            "--no-editable",
            "--all-groups",
            # WARNING: Use `python3` rather than `python`.
            # See comments at `_prime_uv_interpreter_cache`.
            "--python",
            str(deploy_dir / "bin" / "python3"),
            "--project",
            str(wdir),
        ]
        if is_cross:
            uv_python_platform = _uv_python_platform_for_target(target, config["manylinux"])
            sync_cmd += ["--python-platform", uv_python_platform]
            # Build isolation would install target-platform build tools (e.g.
            # uv-build for aarch64) and try to execute them on the host. Use
            # the host-arch .build_venv via PYTHONPATH in build_env instead.
            sync_cmd += ["--no-build-isolation"]
            # Isolate the cross-compile cache from the host cache: same
            # (host_python, target_platform) key would map to different wheels.
            platform_cache = f"{UV_CACHE_DIR}/{uv_python_platform}"
            sync_cmd += ["--cache-dir", platform_cache]
            _prime_uv_interpreter_cache(uv_path, deploy_dir, platform_cache)

        subprocess.check_call(sync_cmd, env=build_env)

        if bundle_python:
            python_dir_name = target_python_bin.parents[1].name
            _link_bundled_python(deploy_dir, python_dir_name, target.minor)
        else:
            _install_host_python_shim(deploy_dir, target.minor)


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

    subparsers.add_parser("deploy", help="Build self-contained deployment")

    args = parser.parse_args()

    # Cache uv-managed Pythons next to the uv cache.
    # Allows install to be idempotent across actions and `uv python find` to locate the result.
    os.environ.setdefault("UV_CACHE_DIR", UV_CACHE_DIR)
    os.environ.setdefault("UV_PYTHON_INSTALL_DIR", f"{UV_CACHE_DIR}/python")

    # Replace $$EXEC_ROOT$$/ markers in env vars set by Bazel so subprocesses see absolute paths.
    _resolve_exec_root_markers()

    with args.manifest.open("r") as f:
        manifest = json.load(f)
    with args.config.open("r") as f:
        config = json.load(f)

    if args.command == "build":
        cmd_build(manifest, config)
    elif args.command == "lock":
        cmd_lock(manifest, config, args.runfiles_dir)
    elif args.command == "export":
        cmd_export(manifest, args.runfiles_dir, args.output_dir)
    elif args.command == "deploy":
        cmd_deploy(manifest, config)


if __name__ == "__main__":
    main()
