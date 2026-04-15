"""uv_py_workspace rule and macro."""

load("@platforms//host:constraints.bzl", "HOST_CONSTRAINTS")
load("@rules_shell//shell:sh_binary.bzl", "sh_binary")
load("//uv/private:providers.bzl", "UvBuildEnvInfo", "UvPyManifestInfo", "UvPyPackageInfo", "UvPyRuntimeInfo", "UvPyWheelInfo")

def _uv_multi_platform_transition_impl(settings, attr):
    # Use split-transition to iterate over possible platforms.
    target_platforms = attr.target_platforms
    if not target_platforms:
        # Identity: preserve current config
        return {"_current": {"//command_line_option:platforms": settings["//command_line_option:platforms"]}}
    return {
        marker: {"//command_line_option:platforms": [str(platform_label)]}
        for platform_label, marker in target_platforms.items()
    }

_uv_multi_platform_transition = transition(
    implementation = _uv_multi_platform_transition_impl,
    inputs = ["//command_line_option:platforms"],
    outputs = ["//command_line_option:platforms"],
)

def _collect_members_and_wheels(members_attr, split_wheels_attr, has_target_platforms):
    seen_package_names = {}  # python_package_name -> label
    seen_labels = {}  # label_name -> True

    members = []
    wheels = []  # list of structs with variants
    wheel_files = []

    # Identify direct member labels
    direct_member_labels = {}
    for m in members_attr:
        direct_member_labels[m[UvPyPackageInfo].label_name] = True

    # direct member members
    for m in members_attr:
        for pkg in m[UvPyPackageInfo].transitive_packages:
            if pkg.label_name not in direct_member_labels:
                continue
            if pkg.label_name in seen_labels:
                continue
            seen_labels[pkg.label_name] = True
            if pkg.python_package_name in seen_package_names:
                fail("python_package_name '%s' is claimed by both '%s' and '%s'" % (
                    pkg.python_package_name,
                    seen_package_names[pkg.python_package_name],
                    pkg.label_name,
                ))
            else:
                seen_package_names[pkg.python_package_name] = pkg.label_name
            members.append(pkg)

    # explicit wheels
    # Build a dict: python_package_name -> {label_name, frozen, variants: [{wheel, marker}, ...]}
    explicit_wheel_data = {}  # python_package_name -> struct-like dict
    for config_key, wheel_targets in split_wheels_attr.items():
        marker = "" if config_key == "_current" else config_key
        for w in wheel_targets:
            whl = w[UvPyWheelInfo]
            if whl.python_package_name not in explicit_wheel_data:
                explicit_wheel_data[whl.python_package_name] = {
                    "label_name": whl.label_name,
                    "python_package_name": whl.python_package_name,
                    "frozen": whl.frozen,
                    "variants": [],
                }
            explicit_wheel_data[whl.python_package_name]["variants"].append(
                struct(wheel = whl.wheel, marker = marker),
            )

    for _, data in explicit_wheel_data.items():
        if data["label_name"] in seen_labels:
            continue
        seen_labels[data["label_name"]] = True

        if data["python_package_name"] in seen_package_names:
            fail("python_package_name '%s' is claimed by both '%s' and '%s'" % (
                data["python_package_name"],
                seen_package_names[data["python_package_name"]],
                data["label_name"],
            ))
        seen_package_names[data["python_package_name"]] = data["label_name"]

        variant_structs = data["variants"]
        wheels.append(struct(
            label_name = data["label_name"],
            python_package_name = data["python_package_name"],
            frozen = data["frozen"],
            variants = variant_structs,
        ))
        for v in variant_structs:
            wheel_files.append(v.wheel)

    # transitive members + wheels
    for member in members_attr:
        for pkg in member[UvPyPackageInfo].transitive_packages:
            if pkg.label_name in seen_labels:
                continue
            seen_labels[pkg.label_name] = True
            if pkg.python_package_name in seen_package_names:
                # buildifier: disable=print
                print("WARNING: python_package_name '%s' is already claimed by '%s': transitive target '%s' is ignored" % (
                    pkg.python_package_name,
                    seen_package_names[pkg.python_package_name],
                    pkg.label_name,
                ))
            else:
                seen_package_names[pkg.python_package_name] = pkg.label_name
                members.append(pkg)

        for whl in member[UvPyPackageInfo].transitive_wheels:
            if whl.label_name in seen_labels:
                continue
            seen_labels[whl.label_name] = True
            if whl.python_package_name in seen_package_names:
                # buildifier: disable=print
                print("WARNING: python_package_name '%s' is already claimed by '%s': transitive target '%s' is ignored" % (
                    whl.python_package_name,
                    seen_package_names[whl.python_package_name],
                    whl.label_name,
                ))
            else:
                # Validate: when target_platforms is set, platform-specific transitive wheels
                # must be listed explicitly in 'wheels' to get the split transition.
                if has_target_platforms and not whl.wheel.basename.endswith("-none-any.whl"):
                    fail(
                        "Cross-platform wheel '%s' (from wheel_deps of '%s') has a platform-specific " +
                        "filename but is not listed in 'wheels' of uv_py_workspace. When using " +
                        "target_platforms, platform-specific wheels must be listed explicitly in " +
                        "'wheels' so they can be built for all target platforms." % (
                            whl.python_package_name,
                            member.label,
                        ),
                    )
                seen_package_names[whl.python_package_name] = whl.label_name

                # Wrap transitive wheels in variants format with empty marker
                wheels.append(struct(
                    label_name = whl.label_name,
                    python_package_name = whl.python_package_name,
                    frozen = whl.frozen,
                    variants = [struct(wheel = whl.wheel, marker = "")],
                ))
                wheel_files.append(whl.wheel)

    return members, wheels, wheel_files

def _uv_py_manifest_impl(ctx):
    packages, wheels, wheel_files = _collect_members_and_wheels(
        ctx.attr.members,
        ctx.split_attr.wheels,
        bool(ctx.attr.target_platforms),
    )

    manifest_content = {
        "ws_name": ctx.attr.ws_name,
        "python_requires": ctx.attr.python_requires,
        "lock_path": ctx.file.lock.path,
        "lock_short_path": ctx.file.lock.short_path,
        "packages": [
            {
                "name": p.python_package_name,
                "pyproject_path": p.pyproject.path,
                "pyproject_short_path": p.pyproject.short_path,
            }
            for p in packages
        ],
        "wheels": [
            {
                "name": w.python_package_name,
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
        "environments": sorted(ctx.attr.target_platforms.values()) if ctx.attr.target_platforms else [],
    }

    manifest_file = ctx.actions.declare_file(ctx.attr.name + ".json")
    ctx.actions.write(output = manifest_file, content = json.encode(manifest_content))

    return [
        DefaultInfo(files = depset([manifest_file])),
        UvPyManifestInfo(
            manifest_file = manifest_file,
            lock_file = ctx.file.lock,
            wheel_files = wheel_files,
            pyproject_inputs = [pkg.pyproject for pkg in packages],
            src_files = depset(transitive = [pkg.srcs for pkg in packages]),
            data_files = depset(transitive = [pkg.data for pkg in packages]),
            member_files = depset(
                transitive = [m[DefaultInfo].files for m in ctx.attr.members],
            ),
        ),
    ]

_uv_py_manifest_rule = rule(
    implementation = _uv_py_manifest_impl,
    attrs = {
        "ws_name": attr.string(mandatory = True),
        "members": attr.label_list(providers = [UvPyPackageInfo]),
        "wheels": attr.label_list(providers = [UvPyWheelInfo], cfg = _uv_multi_platform_transition),
        "target_platforms": attr.label_keyed_string_dict(default = {}),
        "lock": attr.label(allow_single_file = True),
        "python_requires": attr.string(default = ">=3.11"),
        "dependency_groups": attr.string_list_dict(),
        "extra_pyproject_content": attr.string(default = ""),
        # See https://bazel.build/versions/7.4.0/extending/config#user-defined-transitions
        "_allowlist_function_transition": attr.label(
            default = "@bazel_tools//tools/allowlists/function_transition_allowlist",
        ),
    },
    toolchains = [],
)

def _build_env(ctx, exec_py_runtime):
    env = {}
    for provider_target in ctx.attr.env_providers:
        env.update(provider_target[UvBuildEnvInfo].env)
    env.update(ctx.attr.env)

    if env:
        # when `env` is non-empty, `ctx.actions.run` strips the default PATH,
        # which may break py_binary bootstrap required for workspace_tool.py.
        # As a workaround, we maunally put the PATH enrty back if it is missing.
        py_bin_dir = exec_py_runtime.interpreter_path.rsplit("/", 1)[0] if "/" in exec_py_runtime.interpreter_path else ""
        existing_path = env.get("PATH", "")
        if py_bin_dir and py_bin_dir not in existing_path:
            env["PATH"] = py_bin_dir + (":" + existing_path if existing_path else "")

    files = [provider_target[UvBuildEnvInfo].files for provider_target in ctx.attr.env_providers]
    return env, files

def _uv_py_workspace_rule_impl(ctx):
    for c in ctx.attr._host_constraints:
        if not ctx.target_platform_has_constraint(c[platform_common.ConstraintValueInfo]):
            fail("Workspace cannot be built if the target platform doesn't match the host since it runs `uv sync` locally and produces host-platform artifacts. " +
                 "Use `.deploy` target, uv_py_lock or uv_py_export instead.")

    info = ctx.attr.manifest[UvPyManifestInfo]
    root_file = ctx.actions.declare_file(ctx.attr.name + "_root")
    wdir_dir = ctx.actions.declare_directory(ctx.attr.name + "_venv")
    exec_py_runtime = ctx.attr._exec_py_runtime[UvPyRuntimeInfo]

    env, env_provider_files = _build_env(ctx, exec_py_runtime)

    build_config = {
        "wdir_path": wdir_dir.path,
        "root_file_path": root_file.path,
        "python_interpreter_path": exec_py_runtime.interpreter_path,
        "uv_path": ctx.executable._uv.path,
    }
    config_file = ctx.actions.declare_file(ctx.attr.name + ".build.config.json")
    ctx.actions.write(output = config_file, content = json.encode(build_config))

    all_inputs = depset(
        direct = info.pyproject_inputs + [info.lock_file, info.manifest_file, config_file] + info.wheel_files,
        transitive = [info.src_files, info.data_files, exec_py_runtime.files] + env_provider_files,
    )

    ctx.actions.run(
        executable = ctx.executable._workspace_tool,
        arguments = [
            "--manifest",
            info.manifest_file.path,
            "--config",
            config_file.path,
            "build",
        ],
        outputs = [root_file, wdir_dir],
        inputs = all_inputs,
        tools = [ctx.executable._workspace_tool, ctx.executable._uv],
        env = env,
        execution_requirements = {"local": "1"},
        use_default_shell_env = ctx.attr.env_inherit,
    )

    runfiles = ctx.runfiles(
        files = [root_file, wdir_dir] + info.wheel_files,
        transitive_files = info.member_files,
    )
    return [DefaultInfo(files = depset([root_file]), runfiles = runfiles)]

_uv_py_workspace_rule = rule(
    implementation = _uv_py_workspace_rule_impl,
    attrs = {
        "manifest": attr.label(mandatory = True, providers = [UvPyManifestInfo]),
        "env": attr.string_dict(
            doc = "Environment variables to set when running uv sync.",
            default = {},
        ),
        "env_inherit": attr.bool(
            doc = "If True, inherit the host shell environment when running uv sync. " +
                  "Prefer env_providers for reproducible builds.",
            default = False,
        ),
        "env_providers": attr.label_list(
            doc = "Targets providing UvBuildEnvInfo with additional environment variables.",
            providers = [UvBuildEnvInfo],
            default = [],
        ),
        "_workspace_tool": attr.label(
            default = Label("@rules_uv_bare//uv/private:workspace_tool"),
            executable = True,
            cfg = "exec",
        ),
        "_uv": attr.label(
            default = Label("@multitool//tools/uv"),
            executable = True,
            cfg = "exec",
        ),
        "_exec_py_runtime": attr.label(
            default = Label("@rules_uv_bare//uv/private:py_runtime"),
            cfg = "exec",
            providers = [UvPyRuntimeInfo],
        ),
        "_host_constraints": attr.label_list(
            default = HOST_CONSTRAINTS,
            providers = [platform_common.ConstraintValueInfo],
        ),
    },
)

def _uv_py_workspace_deploy_rule_impl(ctx):
    # Unlike the dev workspace rule, this does NOT check host constraints since it doesn't require running a target-platform binary on the host.
    if not ctx.attr.uv_python_key:
        fail(
            "deploy_uv_python is required for the .deploy target. " +
            'Set it on uv_py_workspace (e.g. deploy_uv_python = "cpython-3.12" ' +
            'or a cross-compile key like "cpython-3.12-linux-aarch64-gnu").',
        )
    info = ctx.attr.manifest[UvPyManifestInfo]
    deploy_dir = ctx.actions.declare_directory(ctx.attr.name + "_dir")
    exec_py_runtime = ctx.attr._exec_py_runtime[UvPyRuntimeInfo]

    env, env_provider_files = _build_env(ctx, exec_py_runtime)

    deploy_config = {
        "deploy_dir_path": deploy_dir.path,
        "uv_path": ctx.executable._uv.path,
        "uv_python_key": ctx.attr.uv_python_key,
        "manylinux": ctx.attr.manylinux,
        "build_deps": ctx.attr.build_deps,
        "bundle_python": ctx.attr.bundle_python,
    }
    config_file = ctx.actions.declare_file(ctx.attr.name + ".deploy.config.json")
    ctx.actions.write(output = config_file, content = json.encode(deploy_config))

    all_inputs = depset(
        direct = info.pyproject_inputs + [info.lock_file, info.manifest_file, config_file] + info.wheel_files,
        transitive = [info.src_files, info.data_files, exec_py_runtime.files] + env_provider_files,
    )

    ctx.actions.run(
        executable = ctx.executable._workspace_tool,
        arguments = [
            "--manifest",
            info.manifest_file.path,
            "--config",
            config_file.path,
            "deploy",
        ],
        outputs = [deploy_dir],
        inputs = all_inputs,
        tools = [ctx.executable._workspace_tool, ctx.executable._uv],
        env = env,
        execution_requirements = {"local": "1"},
        use_default_shell_env = ctx.attr.env_inherit,
    )

    runfiles = ctx.runfiles(files = [deploy_dir])
    return [DefaultInfo(files = depset([deploy_dir]), runfiles = runfiles)]

_uv_py_workspace_deploy_rule = rule(
    implementation = _uv_py_workspace_deploy_rule_impl,
    attrs = {
        "manifest": attr.label(mandatory = True, providers = [UvPyManifestInfo]),
        "uv_python_key": attr.string(mandatory = True),
        "manylinux": attr.string(default = ""),
        "build_deps": attr.string_list(default = []),
        "bundle_python": attr.bool(default = True),
        "env": attr.string_dict(default = {}),
        "env_inherit": attr.bool(default = False),
        "env_providers": attr.label_list(providers = [UvBuildEnvInfo], default = []),
        "_workspace_tool": attr.label(
            default = Label("@rules_uv_bare//uv/private:workspace_tool"),
            executable = True,
            cfg = "exec",
        ),
        "_uv": attr.label(
            default = Label("@multitool//tools/uv"),
            executable = True,
            cfg = "exec",
        ),
        "_exec_py_runtime": attr.label(
            default = Label("@rules_uv_bare//uv/private:py_runtime"),
            cfg = "exec",
            providers = [UvPyRuntimeInfo],
        ),
    },
)

def uv_py_workspace(
        name,
        members,
        lock,
        wheels = [],
        target_platforms = {},
        python_requires = ">=3.11",
        dependency_groups = {"test": ["pytest>=8.0"]},
        extra_pyproject_content = "",
        env = {},
        env_inherit = False,
        env_providers = [],
        deploy_uv_python = "",
        deploy_manylinux = "",
        deploy_build_deps = [],
        deploy_bundle_python = True,
        target_compatible_with = [],
        visibility = ["//visibility:public"]):
    """Define and builds a uv workspace from uv_py_package targets.

    Also creates the following sub-targets:

    - ``<name>.run``: runs commands in the workspace venv
    - ``<name>.activate``: prints the path to the venv activate script for shell sourcing
    - ``<name>.deploy``: builds a self-contained env with a bundled Python interpreter

    Use ``uv_py_lock`` and ``uv_py_export`` for lock-file management and workspace export.

    **Example**

    ```bzl
    uv_py_workspace(
        name = "my_workspace",
        members = ["//pkg_a", "//pkg_b"],
        lock = "uv.lock",
    )
    ```

    Args:
        name: target name.
        members: uv_py_package targets (workspace members).
        lock: the uv.lock file.
        wheels: uv_py_import_wheel targets whose .whl files are registered
            as ``[tool.uv.sources]`` path entries in the generated pyproject.toml.
        target_platforms: dict of platform label to PEP 508 marker string.
            When provided, each wheel is built under every listed platform via
            a split transition. Keys are platform labels (e.g. ``":linux_x86_64"``), values
            are marker expressions (e.g. ``"platform_machine == 'x86_64'"``).
        python_requires: Python version constraint.
        dependency_groups: dict of group name to dep list
            (default ``{"test": ["pytest>=8.0"]}``). Pass ``{}`` to disable.
        extra_pyproject_content: additional TOML content appended verbatim to
            the generated pyproject.toml.
        env: dict of environment variable name to value, forwarded to
            ``uv sync`` (e.g. ``{"CC": "/usr/bin/gcc"}``).
        env_inherit: if True, inherit the host shell environment when
            running ``uv sync``. Prefer ``env_providers`` for reproducible builds.
        env_providers: list of targets providing ``UvBuildEnvInfo``.
            If the ``env`` attr sets the same variable, it takes precedence.
        deploy_uv_python: uv python install key for the ``.deploy`` target
            (e.g. ``"cpython-3.12"`` for host-native, or a full cross-compile
            key like ``"cpython-3.12-linux-aarch64-gnu"`` /
            ``"cpython-3.12-macos-aarch64-none"``). Accepts anything
            ``uv python list`` resolves; typically a ``select()`` over target
            platforms. Cross-compile is detected automatically by comparing
            the resolved entry's ``(os, arch)`` to the host's.
        deploy_manylinux: optional manylinux baseline override for Linux+gnu
            cross-compile (e.g. ``"manylinux_2_28"``). The default value is
            ``manylinux2014`` (glibc 2.17). Ignored for musl and other OS.
        deploy_build_deps: Python packages to pre-install as host-platform
            build tools (e.g. ``["setuptools", "wheel", "uv-build>=0.7"]``).
        deploy_bundle_python: if ``True`` (default), bundle a standalone Python
            interpreter. If ``False``, the deploy artifact doesn't bundle
            interpreter, and put a ``bin/python3`` shim instead that searches
            ``python3.X``/``python3`` over ``PATH``.
        target_compatible_with: standard Bazel ``target_compatible_with``
            constraint list. Targets whose platform doesn't satisfy these
            constraints are skipped. It also applied to the sub-targets.
        visibility: Bazel visibility.
    """
    _uv_py_manifest_rule(
        name = name + ".manifest",
        ws_name = name,
        members = members,
        wheels = wheels,
        target_platforms = target_platforms,
        lock = lock,
        python_requires = python_requires,
        dependency_groups = dependency_groups,
        extra_pyproject_content = extra_pyproject_content,
    )

    _uv_py_workspace_rule(
        name = name,
        manifest = ":" + name + ".manifest",
        env = env,
        env_inherit = env_inherit,
        env_providers = env_providers,
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
    _uv_py_workspace_deploy_rule(
        name = name + ".deploy",
        manifest = ":" + name + ".manifest",
        uv_python_key = deploy_uv_python,
        manylinux = deploy_manylinux,
        build_deps = deploy_build_deps,
        bundle_python = deploy_bundle_python,
        env = env,
        env_inherit = env_inherit,
        env_providers = env_providers,
        target_compatible_with = target_compatible_with,
        tags = ["manual"],
        visibility = visibility,
    )
