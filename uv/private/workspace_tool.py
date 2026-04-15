"""Workspace tool for rules_uv_bare."""

from __future__ import annotations

import argparse
import dataclasses
import hashlib
import json
import os
import pathlib
import platform
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
    python_interpreter_path: str
    uv_path: str


class ExecConfig(TypedDict):
    exec_python_interpreter_short_path: str
    uv_short_path: str


class DeployConfig(TypedDict):
    deploy_dir_path: str
    uv_path: str
    uv_python_key: str
    manylinux: str
    build_deps: list[str]
    bundle_python: bool


@dataclasses.dataclass(frozen=True)
class ResolvedPython:
    key: str
    major: int
    minor: int
    os: str
    arch: str
    libc: str
    is_cross_compile: bool

    # Defined if `is_cross_compile = True`
    uv_python_platform: str
    platform_arch: str

    @property
    def version(self) -> str:
        return f"{self.major}.{self.minor}"


class _WheelFileEntry(TypedDict):
    filename: str
    marker: str


def _resolve_output_dir(output_dir: str) -> str:
    # Resolve relative output_dir against user's working directory
    bwd = os.environ.get("BUILD_WORKING_DIRECTORY")
    if bwd and not os.path.isabs(output_dir):
        output_dir = os.path.join(bwd, output_dir)
    return output_dir


def _resolve_exec_root_markers() -> None:
    exec_root = os.getcwd()
    for key, value in list(os.environ.items()):
        if _EXEC_ROOT_MARKER in value:
            os.environ[key] = value.replace(_EXEC_ROOT_MARKER, exec_root + "/")


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

    markers = environments or []

    lines = ["tool.uv.package = false"]
    if markers:
        env_entries = ", ".join(f'"{m}"' for m in markers)
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


def _relock_unfrozen_wheels(
    wdir: pathlib.Path,
    manifest: SharedManifest,
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
    uv_lock_cmd += ["--cache-dir", UV_CACHE_DIR]
    if python_path:
        uv_lock_cmd += ["--python", python_path]
    subprocess.check_call(uv_lock_cmd)


def cmd_build(manifest: SharedManifest, config: BuildConfig) -> None:
    uv_path = config["uv_path"]
    lock_path = pathlib.Path(manifest["lock_path"]).resolve()
    wdir = pathlib.Path(config["wdir_path"]).resolve()

    wheel_entries = _setup_workspace_dir(wdir, manifest)
    shutil.copy2(str(lock_path), str(wdir / "uv.lock"))

    python_path = config["python_interpreter_path"]

    _relock_unfrozen_wheels(wdir, manifest, wheel_entries, uv_path, python_path)

    uv_cmd = [uv_path, "sync", "--frozen", "--all-groups", "--project", str(wdir)]
    uv_cmd += ["--cache-dir", UV_CACHE_DIR]
    if python_path:
        uv_cmd += ["--python", python_path]
    subprocess.check_call(uv_cmd)

    # Remove .source/ symlinks.
    # Otherwise, Bazel would rebuild every time if any file in the directory that the symlinks point to is changed, regardless of ``srcs``, ``data`` attributes specified in ``uv_py_package``, because of the tree artifact mechanism.
    # The symlinks are only needed during `uv sync`; the installed venv uses .pth files that point directly to the source tree, not through .source/.
    source_dir = wdir / ".source"
    if source_dir.exists():
        shutil.rmtree(str(source_dir))

    pathlib.Path(config["root_file_path"]).write_text(f"{wdir}\n")


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
            subprocess.check_call(uv_lock_cmd, cwd=str(wdir))
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
    cmd += ["--cache-dir", UV_CACHE_DIR]
    subprocess.check_call(cmd)


def _setup_build_tools_venv(
    uv_path: str,
    build_venv: pathlib.Path,
    build_deps: list[str],
    python_path: str,
) -> tuple[str, str]:
    # Create a host-platform build-tools venv. Returns (site_packages, bin).
    venv_cmd = [uv_path, "venv", "--python", python_path, str(build_venv)]
    venv_cmd += ["--cache-dir", UV_CACHE_DIR]
    subprocess.check_call(venv_cmd)

    build_python = str(build_venv / "bin" / "python")
    install_cmd = [uv_path, "pip", "install", "--python", build_python]
    install_cmd += sorted(build_deps) + ["--cache-dir", UV_CACHE_DIR]
    subprocess.check_call(install_cmd)

    site_packages = subprocess.check_output(
        [build_python, "-c", "import site; print(site.getsitepackages()[0])"],
        text=True,
    ).strip()
    return site_packages, str(build_venv / "bin")


def _host_os_arch() -> tuple[str, str]:
    raw_os = sys.platform
    if raw_os == "darwin":
        host_os = "macos"
    elif raw_os.startswith("linux"):
        host_os = "linux"
    else:
        host_os = raw_os

    raw_arch = platform.machine().lower()
    host_arch = {"arm64": "aarch64", "amd64": "x86_64"}.get(raw_arch, raw_arch)
    return host_os, host_arch


def _resolve_uv_python(uv_path: str, key: str, manylinux: str) -> ResolvedPython:
    if not key:
        raise SystemExit(
            "deploy_uv_python is required for the .deploy target. "
            'Set it on uv_py_workspace (e.g. deploy_uv_python = "cpython-3.12" '
            'or a cross-compile key like "cpython-3.12-linux-aarch64-gnu").'
        )

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

    major = int(entry["version_parts"]["major"])
    minor = int(entry["version_parts"]["minor"])
    target_os = entry["os"]
    target_arch = entry["arch"]
    libc = entry["libc"]

    host_os, host_arch = _host_os_arch()
    is_cross = (target_os, target_arch) != (host_os, host_arch)

    uv_python_platform = ""
    target_platform_arch = target_arch
    if is_cross:
        if target_os == "linux" and libc == "gnu":
            baseline = manylinux or "manylinux2014"
            uv_python_platform = f"{target_arch}-{baseline}"
        elif target_os == "linux" and libc == "musl":
            uv_python_platform = f"{target_arch}-unknown-linux-musl"
        elif target_os == "macos":
            uv_python_platform = f"{target_arch}-apple-darwin"
            if target_arch == "aarch64":
                target_platform_arch = "arm64"
        else:
            raise SystemExit(
                f"Unsupported cross-compile target for key {key!r}: os={target_os} libc={libc}"
            )

    return ResolvedPython(
        key=entry["key"],
        major=major,
        minor=minor,
        os=target_os,
        arch=target_arch,
        libc=libc,
        is_cross_compile=is_cross,
        uv_python_platform=uv_python_platform,
        platform_arch=target_platform_arch,
    )


def _install_python(
    uv_path: str,
    install_dir: pathlib.Path,
    key: str,
) -> pathlib.Path:
    cmd = [uv_path, "python", "install", "--no-bin", "-i", str(install_dir), key]
    cmd += ["--cache-dir", UV_CACHE_DIR]
    subprocess.check_call(cmd)

    # uv creates both the full-version install dir and a version-shorthand
    # symlink next to it; drop the symlink so the deploy artifact is minimal.
    result = None
    for d in install_dir.iterdir():
        if not d.name.startswith("cpython"):
            continue
        if d.is_symlink():
            d.unlink()
            continue
        if not d.is_dir():
            continue
        python_bin = d / "bin" / "python3"
        if python_bin.exists() or python_bin.is_symlink():
            result = python_bin
    if result:
        return result
    raise RuntimeError(f"No cpython installation found in {install_dir}")


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


def _link_bundled_python(
    deploy_dir: pathlib.Path,
    installed_key: str,
    minor: int,
) -> None:
    bin_dir = deploy_dir / "bin"
    for p in bin_dir.glob("python*"):
        if p.is_symlink() or p.is_file():
            p.unlink()

    rel = pathlib.Path("..") / "python" / installed_key / "bin" / f"python3.{minor}"
    (bin_dir / "python3").symlink_to(rel)
    (bin_dir / "python").symlink_to("python3")
    (bin_dir / f"python3.{minor}").symlink_to("python3")


def _remove_venv_python_links(deploy_dir: pathlib.Path) -> None:
    # Without a bundled interpreter, uv's relocatable-venv python symlinks
    # point at a temp-dir that is about to be deleted. Remove them so the
    # deploy artifact has no dangling symlinks; the caller is expected to
    # provide bin/python3 at runtime.
    bin_dir = deploy_dir / "bin"
    for p in bin_dir.glob("python*"):
        if p.is_symlink() or p.is_file():
            p.unlink()


def _install_host_python_shim(deploy_dir: pathlib.Path, minor: int) -> None:
    _remove_venv_python_links(deploy_dir)

    bin_dir = deploy_dir / "bin"
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

    (bin_dir / "python").symlink_to("python3")
    (bin_dir / f"python3.{minor}").symlink_to("python3")


def _configure_build_env(
    uv_path: str,
    wdir: pathlib.Path,
    host_python_bin: pathlib.Path,
    target_python_bin: pathlib.Path,
    resolved: ResolvedPython,
    build_deps: list[str],
) -> dict[str, str]:
    # Build env for uv sync.
    # Adds cross-compile flags when resolved.is_cross_compile.
    build_env = os.environ.copy()
    build_env.pop("VIRTUAL_ENV", None)
    build_env["UV_NO_MANAGED_PYTHON"] = "1"

    if not resolved.is_cross_compile:
        return build_env

    target_python_prefix = target_python_bin.parents[1]
    cc = build_env.get("CC", "cc")

    sysconfig = _read_target_sysconfig(
        host_python_bin,
        target_python_prefix,
        resolved.minor,
        ["LDSHARED", "CCSHARED", "MACOSX_DEPLOYMENT_TARGET", "EXT_SUFFIX"],
    )

    macosx_dt = sysconfig.get("MACOSX_DEPLOYMENT_TARGET", "")
    if resolved.os == "macos":
        # macOS host platform needs the deployment-target version from sysconfig.
        host_platform = (
            f"macosx-{macosx_dt}-{resolved.platform_arch}"
            if macosx_dt
            else f"macosx-11.0-{resolved.platform_arch}"
        )
    else:
        host_platform = f"{resolved.os}-{resolved.platform_arch}"
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
    include_path = target_python_prefix / "include" / f"python3.{resolved.minor}"
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


def cmd_deploy(manifest: SharedManifest, config: DeployConfig) -> None:
    uv_path = str(pathlib.Path(config["uv_path"]).resolve())
    # deploy_dir must be absolute since uv resolves UV_PROJECT_ENVIRONMENT
    # relative to --project.
    deploy_dir = pathlib.Path(config["deploy_dir_path"]).resolve()
    lock_path = pathlib.Path(manifest["lock_path"])

    resolved = _resolve_uv_python(
        uv_path,
        config["uv_python_key"],
        config["manylinux"],
    )
    target_key = resolved.key
    host_key = f"cpython-{resolved.version}"
    bundle_python = config.get("bundle_python", True)

    with tempfile.TemporaryDirectory() as tmpdir:
        wdir = pathlib.Path(tmpdir)
        wheel_entries = _setup_workspace_dir(wdir, manifest)
        shutil.copy2(str(lock_path), str(wdir / "uv.lock"))

        if bundle_python:
            target_python_bin = _install_python(
                uv_path, deploy_dir / "python", target_key
            )
        else:
            # Install the target interpreter into the temp dir.
            # Even if `bundle_python` is False, the target python is needed to read sysconfig data.
            target_python_bin = _install_python(
                uv_path, wdir / ".target_python", target_key
            )

        if not resolved.is_cross_compile:
            host_python_bin = target_python_bin.resolve()
        else:
            host_python_bin = _install_python(
                uv_path, wdir / ".host_python", host_key
            ).resolve()

        target_python_dir_name = target_python_bin.parents[1].name
        _relock_unfrozen_wheels(
            wdir, manifest, wheel_entries, uv_path, str(host_python_bin)
        )

        build_env = _configure_build_env(
            uv_path,
            wdir,
            host_python_bin,
            target_python_bin,
            resolved,
            config.get("build_deps", []),
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
        if resolved.is_cross_compile:
            uv_python_platform = resolved.uv_python_platform
            sync_cmd += ["--python-platform", uv_python_platform]
            # Build isolation would install target-platform build tools (e.g.
            # uv-build for aarch64) and try to execute them on the host. Use
            # the host-arch .build_venv via PYTHONPATH in build_env instead.
            sync_cmd += ["--no-build-isolation"]
            platform_cache = f"{UV_CACHE_DIR}/{uv_python_platform}"
            sync_cmd += ["--cache-dir", platform_cache]
            _prime_uv_interpreter_cache(uv_path, deploy_dir, platform_cache)
        else:
            sync_cmd += ["--cache-dir", UV_CACHE_DIR]

        subprocess.check_call(sync_cmd, env=build_env)

        if bundle_python:
            _link_bundled_python(deploy_dir, target_python_dir_name, resolved.minor)
        else:
            _install_host_python_shim(deploy_dir, resolved.minor)


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
        cmd_export(manifest, config, args.runfiles_dir, args.output_dir)
    elif args.command == "deploy":
        cmd_deploy(manifest, config)


if __name__ == "__main__":
    main()
