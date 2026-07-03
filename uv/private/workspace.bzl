"""uv_py_workspace rule and macro."""

load("@platforms//host:constraints.bzl", "HOST_CONSTRAINTS")
load("@rules_shell//shell:sh_binary.bzl", "sh_binary")
load("//uv/private:providers.bzl", "UvBuildEnvInfo", "UvPyManifestInfo", "UvPyPackageInfo", "UvPyWheelInfo")
load("//uv/private:uv_env.bzl", "with_uv_env_defaults")

# Split-transition branch key used when no platform_markers are set.
_IDENTITY_KEY = "_current"

# This transition exists ONLY to build each explicitly-listed wheel once per
# entry in `platform_markers` (a label -> PEP 508 marker dict), so a single lock
# file can carry platform-specific wheels. With no platform_markers it is an
# identity no-op.
def _uv_multi_platform_transition_impl(settings, attr):
    platform_markers = attr.platform_markers
    if not platform_markers:
        return {_IDENTITY_KEY: {"//command_line_option:platforms": settings["//command_line_option:platforms"]}}
    return {
        marker: {"//command_line_option:platforms": [str(platform_label)]}
        for platform_label, marker in platform_markers.items()
    }

_uv_multi_platform_transition = transition(
    implementation = _uv_multi_platform_transition_impl,
    inputs = ["//command_line_option:platforms"],
    outputs = ["//command_line_option:platforms"],
)

def _fail_conflict(dist_name, existing, label):
    fail("dist_name '%s' is claimed by both '%s' and '%s'" % (dist_name, existing, label))

def _warn_conflict(dist_name, existing, label):
    # buildifier: disable=print
    print("WARNING: dist_name '%s' is already claimed by '%s': transitive target '%s' is ignored" % (
        dist_name,
        existing,
        label,
    ))

def _claim(dist_name, label, seen_names, seen_labels, on_conflict):
    # Register (dist_name, label).
    # Returns True if newly claimed.
    # Returns False if the label was already seen.
    # If dist_name conflicts with a different label, calls on_conflict (fail or warn) and returns False.
    if label in seen_labels:
        return False
    seen_labels[label] = True
    if dist_name in seen_names:
        on_conflict(dist_name, seen_names[dist_name], label)
        return False
    seen_names[dist_name] = label
    return True

def _collect_members_and_wheels(members_attr, split_wheels_attr, has_platform_markers):
    seen_names = {}  # dist_name -> label
    seen_labels = {}  # label -> True
    members = []
    wheels = []  # list of structs with variants
    wheel_inputs = []

    # Direct members. Conflicts are fatal.
    direct_member_labels = {m[UvPyPackageInfo].label: True for m in members_attr}
    for m in members_attr:
        for pkg in m[UvPyPackageInfo].transitive_packages:
            if pkg.label in direct_member_labels and _claim(pkg.dist_name, pkg.label, seen_names, seen_labels, _fail_conflict):
                members.append(pkg)

    # Explicitly-listed wheels (may carry per-platform variants). Conflicts fatal.
    explicit_wheel_data = {}  # dist_name -> {label, frozen, variants}
    for config_key, wheel_targets in split_wheels_attr.items():
        marker = "" if config_key == _IDENTITY_KEY else config_key
        for w in wheel_targets:
            whl = w[UvPyWheelInfo]
            data = explicit_wheel_data.setdefault(whl.dist_name, {
                "label": whl.label,
                "dist_name": whl.dist_name,
                "frozen": whl.frozen,
                "variants": [],
            })
            data["variants"].append(struct(wheel = whl.wheel, marker = marker))
    for data in explicit_wheel_data.values():
        if _claim(data["dist_name"], data["label"], seen_names, seen_labels, _fail_conflict):
            wheels.append(struct(
                label = data["label"],
                dist_name = data["dist_name"],
                frozen = data["frozen"],
                variants = data["variants"],
            ))
            wheel_inputs.extend([v.wheel for v in data["variants"]])

    # Transitive members + wheels (conflicts warn and skip).
    for member in members_attr:
        for pkg in member[UvPyPackageInfo].transitive_packages:
            if _claim(pkg.dist_name, pkg.label, seen_names, seen_labels, _warn_conflict):
                members.append(pkg)
        for whl in member[UvPyPackageInfo].transitive_wheels:
            if whl.label in seen_labels:
                continue

            # A platform-specific transitive wheel can't get the split transition,
            # so require it to be listed explicitly in 'wheels' under platform_markers.
            if has_platform_markers and not whl.wheel.basename.endswith("-none-any.whl") and whl.dist_name not in seen_names:
                fail(
                    ("Cross-platform wheel '%s' (from wheel_deps of '%s') has a platform-specific " +
                     "filename but is not listed in 'wheels' of uv_py_workspace. When using " +
                     "platform_markers, platform-specific wheels must be listed explicitly in " +
                     "'wheels' so they can be built for all target platforms.") % (
                        whl.dist_name,
                        member.label,
                    ),
                )
            if _claim(whl.dist_name, whl.label, seen_names, seen_labels, _warn_conflict):
                wheels.append(struct(
                    label = whl.label,
                    dist_name = whl.dist_name,
                    frozen = whl.frozen,
                    variants = [struct(wheel = whl.wheel, marker = "")],
                ))
                wheel_inputs.append(whl.wheel)

    return members, wheels, wheel_inputs

def _uv_py_manifest_impl(ctx):
    packages, wheels, wheel_inputs = _collect_members_and_wheels(
        ctx.attr.members,
        ctx.split_attr.wheels,
        bool(ctx.attr.platform_markers),
    )

    manifest_content = {
        "project_name": ctx.attr.project_name,
        "host_python": ctx.attr.host_python,
        "requires_python": ctx.attr.requires_python,
        "lock_path": ctx.file.lock.path,
        "lock_short_path": ctx.file.lock.short_path,
        "packages": [
            {
                "name": p.dist_name,
                "pyproject_path": p.pyproject.path,
                "pyproject_short_path": p.pyproject.short_path,
            }
            for p in packages
        ],
        "wheels": [
            {
                "name": w.dist_name,
                "frozen": w.frozen,
                "variants": [
                    {"path": v.wheel.path, "short_path": v.wheel.short_path, "marker": v.marker}
                    for v in w.variants
                ],
            }
            for w in wheels
        ],
        "dependency_groups": ctx.attr.dependency_groups,
        "extra_pyproject_content": ctx.attr.extra_pyproject_content,
        "environments": sorted(ctx.attr.platform_markers.values()) if ctx.attr.platform_markers else [],
    }

    manifest_file = ctx.actions.declare_file(ctx.attr.name + ".json")
    ctx.actions.write(output = manifest_file, content = json.encode(manifest_content))

    return [
        DefaultInfo(files = depset([manifest_file])),
        UvPyManifestInfo(
            manifest_file = manifest_file,
            lock_file = ctx.file.lock,
            wheel_inputs = wheel_inputs,
            pyproject_inputs = [pkg.pyproject for pkg in packages],
            src_files = depset(transitive = [pkg.srcs for pkg in packages]),
            data_files = depset(transitive = [pkg.data for pkg in packages]),
            member_files = depset(
                direct = [pkg.pyproject for pkg in packages],
                transitive = [pkg.srcs for pkg in packages] + [pkg.data for pkg in packages],
            ),
            host_python = ctx.attr.host_python,
        ),
    ]

_uv_py_manifest_rule = rule(
    implementation = _uv_py_manifest_impl,
    attrs = {
        "project_name": attr.string(mandatory = True),
        "members": attr.label_list(providers = [UvPyPackageInfo]),
        "wheels": attr.label_list(providers = [UvPyWheelInfo], cfg = _uv_multi_platform_transition),
        "platform_markers": attr.label_keyed_string_dict(default = {}),
        "lock": attr.label(allow_single_file = True),
        "host_python": attr.string(mandatory = True),
        "requires_python": attr.string(default = ""),
        "dependency_groups": attr.string_list_dict(),
        "extra_pyproject_content": attr.string(default = ""),
        # See https://bazel.build/versions/7.4.0/extending/config#user-defined-transitions
        "_allowlist_function_transition": attr.label(
            default = "@bazel_tools//tools/allowlists/function_transition_allowlist",
        ),
    },
)

def _build_env(ctx):
    env = {}
    for provider_target in ctx.attr.build_env_deps:
        env.update(provider_target[UvBuildEnvInfo].env)
    env.update(ctx.attr.env)

    # Apply defaults after user overrides so UV_PYTHON_INSTALL_DIR follows any
    # user-set UV_CACHE_DIR.
    env = with_uv_env_defaults(env)

    files = [provider_target[UvBuildEnvInfo].files for provider_target in ctx.attr.build_env_deps]
    return env, files

# Shared attrs for the dev-build and bundle workspace rules.
_ENV_ATTRS = {
    "env": attr.string_dict(
        doc = "Environment variables to set when running uv sync.",
        default = {},
    ),
    "inherit_host_env": attr.bool(
        doc = "If True, inherit the host shell environment when running uv sync. " +
              "Prefer build_env_deps for reproducible builds.",
        default = False,
    ),
    "build_env_deps": attr.label_list(
        doc = "Targets providing UvBuildEnvInfo with additional environment variables.",
        providers = [UvBuildEnvInfo],
        default = [],
    ),
}

_TOOL_ATTRS = {
    "_workspace_tool_py": attr.label(
        default = Label("@rules_uv_bare//uv/private:workspace_tool.py"),
        allow_single_file = [".py"],
    ),
    "_uv": attr.label(
        default = Label("@multitool//tools/uv"),
        executable = True,
        cfg = "exec",
    ),
}

def _run_workspace_tool(ctx, info, config_file, verb, outputs, env, env_provider_files):
    all_inputs = depset(
        direct = info.pyproject_inputs + [info.lock_file, info.manifest_file, config_file, ctx.file._workspace_tool_py] + info.wheel_inputs,
        transitive = [info.src_files, info.data_files] + env_provider_files,
    )
    ctx.actions.run(
        executable = ctx.executable._uv,
        arguments = [
            "run",
            "--script",
            "--no-project",
            ctx.file._workspace_tool_py.path,
            "--manifest",
            info.manifest_file.path,
            "--config",
            config_file.path,
            verb,
        ],
        outputs = outputs,
        inputs = all_inputs,
        tools = [ctx.executable._uv],
        env = env,
        execution_requirements = {"local": "1"},
        use_default_shell_env = ctx.attr.inherit_host_env,
    )

def _uv_py_workspace_rule_impl(ctx):
    for c in ctx.attr._host_constraints:
        if not ctx.target_platform_has_constraint(c[platform_common.ConstraintValueInfo]):
            fail("Workspace cannot be built if the target platform doesn't match the host since it runs `uv sync` locally and produces host-platform artifacts. " +
                 "Use `.bundle` target, uv_py_lock or uv_py_export instead.")

    info = ctx.attr.manifest[UvPyManifestInfo]

    # Marker file whose first line is the abs path to the venv dir (read by uv_py_entrypoint).
    venv_marker = ctx.actions.declare_file(ctx.attr.name + "_root")
    venv_dir = ctx.actions.declare_directory(ctx.attr.name + "_venv")

    env, env_provider_files = _build_env(ctx)

    build_config = {
        "wdir_path": venv_dir.path,
        "root_file_path": venv_marker.path,
        "uv_path": ctx.executable._uv.path,
    }
    config_file = ctx.actions.declare_file(ctx.attr.name + ".build.config.json")
    ctx.actions.write(output = config_file, content = json.encode(build_config))

    _run_workspace_tool(ctx, info, config_file, "build", [venv_marker, venv_dir], env, env_provider_files)

    runfiles = ctx.runfiles(
        files = [venv_marker, venv_dir] + info.wheel_inputs,
        transitive_files = info.member_files,
    )
    return [DefaultInfo(files = depset([venv_marker]), runfiles = runfiles)]

_uv_py_workspace_rule = rule(
    implementation = _uv_py_workspace_rule_impl,
    attrs = {
        "manifest": attr.label(mandatory = True, providers = [UvPyManifestInfo]),
        "_host_constraints": attr.label_list(
            default = HOST_CONSTRAINTS,
            providers = [platform_common.ConstraintValueInfo],
        ),
    } | _ENV_ATTRS | _TOOL_ATTRS,
)

def _uv_py_workspace_bundle_rule_impl(ctx):
    # Unlike the dev workspace rule, this does NOT check host constraints since it doesn't require running a target-platform binary on the host.
    info = ctx.attr.manifest[UvPyManifestInfo]
    bundle_dir = ctx.actions.declare_directory(ctx.attr.name + "_dir")

    env, env_provider_files = _build_env(ctx)

    bundle_config = {
        "bundle_dir_path": bundle_dir.path,
        "uv_path": ctx.executable._uv.path,
        "bundle_target_platform": ctx.attr.bundle_target_platform,
        "manylinux": ctx.attr.bundle_manylinux,
        "build_deps": ctx.attr.bundle_build_deps,
        "bundle_interpreter": ctx.attr.bundle_interpreter,
    }
    config_file = ctx.actions.declare_file(ctx.attr.name + ".bundle.config.json")
    ctx.actions.write(output = config_file, content = json.encode(bundle_config))

    _run_workspace_tool(ctx, info, config_file, "bundle", [bundle_dir], env, env_provider_files)

    runfiles = ctx.runfiles(files = [bundle_dir])
    return [DefaultInfo(files = depset([bundle_dir]), runfiles = runfiles)]

_uv_py_workspace_bundle_rule = rule(
    implementation = _uv_py_workspace_bundle_rule_impl,
    attrs = {
        "manifest": attr.label(mandatory = True, providers = [UvPyManifestInfo]),
        "bundle_target_platform": attr.string(default = ""),
        "bundle_manylinux": attr.string(default = ""),
        "bundle_build_deps": attr.string_list(default = []),
        "bundle_interpreter": attr.bool(default = True),
    } | _ENV_ATTRS | _TOOL_ATTRS,
)

def uv_py_workspace(
        name,
        members,
        lock,
        host_python,
        wheels = [],
        platform_markers = {},
        requires_python = "",
        dependency_groups = {},
        extra_pyproject_content = "",
        env = {},
        inherit_host_env = False,
        build_env_deps = [],
        bundle_target_platform = "",
        bundle_manylinux = "",
        bundle_build_deps = [],
        bundle_interpreter = True,
        target_compatible_with = [],
        visibility = ["//visibility:public"]):
    """Define and builds a uv workspace from uv_py_package targets.

    Also creates the following sub-targets:

    - ``<name>.run``: runs commands in the workspace venv
    - ``<name>.activate``: prints the path to the venv activate script for shell sourcing
    - ``<name>.bundle``: builds a self-contained env with a bundled Python interpreter

    Use ``uv_py_lock`` and ``uv_py_export`` for lock-file management and workspace export.

    **Example**

    ```bzl
    uv_py_workspace(
        name = "my_workspace",
        members = ["//pkg_a", "//pkg_b"],
        lock = "uv.lock",
        host_python = "cpython-3.12",
    )
    ```

    Args:
        name: target name.
        members: uv_py_package targets (workspace members).
        lock: the uv.lock file.
        host_python: uv python key for the **host** interpreter that runs
            ``uv lock`` / ``uv sync`` / ``uv build`` (e.g. ``"cpython-3.12"`` or
            ``"cpython-3.12.5"``). Anything ``uv python list`` resolves is
            accepted. The interpreter is fetched via ``uv python install`` at
            action time and reused across actions via the uv cache.
        wheels: uv_py_import_wheel targets whose .whl files are registered
            as ``[tool.uv.sources]`` path entries in the generated pyproject.toml.
        platform_markers: dict of platform label to PEP 508 marker string.
            When provided, each wheel is built under every listed platform via
            a split transition. Keys are platform labels (e.g. ``":linux_x86_64"``), values
            are marker expressions (e.g. ``"platform_machine == 'x86_64'"``).
        requires_python: optional Python version constraint written to
            ``project.requires-python`` in the generated workspace pyproject.toml.
            Leave empty to omit the field. uv lock will then use the
            ``host_python`` interpreter (and member pyprojects'
            ``requires-python``) for resolution scope. Set explicitly (e.g.
            ``">=3.10"``) when you need a specific range.
        dependency_groups: dict of group name to dep list (e.g. ``{"test": ["pytest>=8.0"]}``).
        extra_pyproject_content: additional TOML content appended verbatim to
            the generated pyproject.toml.
        env: dict of environment variable name to value, forwarded to
            ``uv sync`` (e.g. ``{"CC": "/usr/bin/gcc"}``).
        inherit_host_env: if True, inherit the host shell environment when
            running ``uv sync``. Prefer ``build_env_deps`` for reproducible builds.
        build_env_deps: list of targets providing ``UvBuildEnvInfo``.
            If the ``env`` attr sets the same variable, it takes precedence.
        bundle_target_platform: cross-compile platform suffix for the ``.bundle``
            target (e.g. ``"linux-aarch64-gnu"`` / ``"macos-aarch64-none"``).
            The target uv python key is constructed with ``host_python`` as
            ``{host_python.impl}-{host_python.version}-{bundle_target_platform}``.
            Typically a ``select()`` over target platforms.
            Leave empty (default) for a non-cross-compile bundle where the
            bundled Python matches the host.
        bundle_manylinux: optional manylinux baseline override for Linux+gnu
            cross-compile (e.g. ``"manylinux_2_28"``). The default value is
            ``manylinux2014`` (glibc 2.17). Ignored for musl and other OS.
        bundle_build_deps: Python packages to pre-install as host-platform
            build tools (e.g. ``["setuptools", "wheel", "uv-build>=0.7"]``).
        bundle_interpreter: if ``True`` (default), bundle a standalone Python
            interpreter. If ``False``, the bundle doesn't include an
            interpreter, and puts a ``bin/python3`` shim instead that searches
            ``python3.X``/``python3`` over ``PATH``.
        target_compatible_with: standard Bazel ``target_compatible_with``
            constraint list. Targets whose platform doesn't satisfy these
            constraints are skipped. It also applied to the sub-targets.
        visibility: Bazel visibility.
    """
    _uv_py_manifest_rule(
        name = name + ".manifest",
        project_name = name,
        members = members,
        wheels = wheels,
        platform_markers = platform_markers,
        lock = lock,
        host_python = host_python,
        requires_python = requires_python,
        dependency_groups = dependency_groups,
        extra_pyproject_content = extra_pyproject_content,
    )

    _uv_py_workspace_rule(
        name = name,
        manifest = ":" + name + ".manifest",
        env = env,
        inherit_host_env = inherit_host_env,
        build_env_deps = build_env_deps,
        target_compatible_with = target_compatible_with,
        visibility = visibility,
    )
    sh_binary(
        name = name + ".run",
        srcs = [Label("@rules_uv_bare//uv/private:venv_run.sh")],
        args = ["$(rootpath " + name + ")"],
        data = [name],
        target_compatible_with = target_compatible_with,
        visibility = visibility,
    )
    sh_binary(
        name = name + ".activate",
        srcs = [Label("@rules_uv_bare//uv/private:venv_activate.sh")],
        args = ["$(rootpath " + name + ")"],
        data = [name],
        target_compatible_with = target_compatible_with,
        visibility = visibility,
    )
    _uv_py_workspace_bundle_rule(
        name = name + ".bundle",
        manifest = ":" + name + ".manifest",
        bundle_target_platform = bundle_target_platform,
        bundle_manylinux = bundle_manylinux,
        bundle_build_deps = bundle_build_deps,
        bundle_interpreter = bundle_interpreter,
        env = env,
        inherit_host_env = inherit_host_env,
        build_env_deps = build_env_deps,
        target_compatible_with = target_compatible_with,
        tags = ["manual"],
        visibility = visibility,
    )
