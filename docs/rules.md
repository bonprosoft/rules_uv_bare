<!-- Generated with Stardoc: http://skydoc.bazel.build -->

Rules for rules_uv_bare.

Provides:
  - uv_py_package: declares a Python package with its pyproject.toml
  - uv_py_workspace: defines and creates a uv workspace from packages
      - .run: runs commands in the workspace venv
      - .activate: prints path to venv activate script for shell sourcing
      - .bundle: builds a self-contained directory with a bundled Python interpreter
  - uv_py_lock: updates uv.lock in-place
  - uv_py_export: exports a portable workspace directory
  - uv_py_entrypoint: runs commands in the workspace venv
  - uv_py_test: runs tests in the workspace venv
  - uv_py_wheel: builds a .whl from a uv_py_package target
  - uv_py_import_wheel: imports a wheel file for use with uv_py_package or uv_py_workspace
  - uv_py_deploy: copies the built .bundle into a standalone directory

For writing custom rules:
  - UvPyPackageInfo / UvPyWheelInfo / UvBuildEnvInfo: providers emitted/consumed by these rules
  - DEFAULT_PY_EXCLUDES: default glob excludes used by uv_py_package
  - to_exec_root_path: prefix an exec-root-relative path with EXEC_ROOT_MARKER
  - EXEC_ROOT_MARKER: marker prefix substituted to the absolute exec root at runtime

<a id="uv_py_import_wheel"></a>

## uv_py_import_wheel

<pre>
load("@rules_uv_bare//uv:defs.bzl", "uv_py_import_wheel")

uv_py_import_wheel(<a href="#uv_py_import_wheel-name">name</a>, <a href="#uv_py_import_wheel-src">src</a>, <a href="#uv_py_import_wheel-dist_name">dist_name</a>, <a href="#uv_py_import_wheel-frozen">frozen</a>)
</pre>

Imports a pre-built .whl file for use in a uv workspace.

The wheel is registered as a ``[tool.uv.sources]`` in the generated pyproject.toml.
Use ``wheel_deps`` on ``uv_py_package`` or ``wheels`` on ``uv_py_workspace`` to include it.

**Example**

```bzl
uv_py_import_wheel(
    name = "my_ext",
    src = ":my_ext_wheel",
)
```

**ATTRIBUTES**


| Name  | Description | Type | Mandatory | Default |
| :------------- | :------------- | :------------- | :------------- | :------------- |
| <a id="uv_py_import_wheel-name"></a>name |  A unique name for this target.   | <a href="https://bazel.build/concepts/labels#target-names">Name</a> | required |  |
| <a id="uv_py_import_wheel-src"></a>src |  The .whl file to import.   | <a href="https://bazel.build/concepts/labels">Label</a> | required |  |
| <a id="uv_py_import_wheel-dist_name"></a>dist_name |  Python distribution name override (i.e. ``[project].name``). Inferred from the wheel filename if not set. Underscores are normalized to hyphens.   | String | optional |  `""`  |
| <a id="uv_py_import_wheel-frozen"></a>frozen |  If True (default), trust the wheel's hash in uv.lock. Set False for wheels that Bazel rebuilds (whose contents change between builds); the hash is then re-resolved into uv.lock.   | Boolean | optional |  `True`  |


<a id="UvBuildEnvInfo"></a>

## UvBuildEnvInfo

<pre>
load("@rules_uv_bare//uv:defs.bzl", "UvBuildEnvInfo")

UvBuildEnvInfo(<a href="#UvBuildEnvInfo-env">env</a>, <a href="#UvBuildEnvInfo-files">files</a>)
</pre>

Environment variables and toolchain files to forward to uv sync and wheel builds.

**FIELDS**

| Name  | Description |
| :------------- | :------------- |
| <a id="UvBuildEnvInfo-env"></a>env |  Dict of environment variable name to value    |
| <a id="UvBuildEnvInfo-files"></a>files |  Depset of files required by the environment (e.g. CC toolchain sysroot, runtime libs)    |


<a id="UvPyPackageInfo"></a>

## UvPyPackageInfo

<pre>
load("@rules_uv_bare//uv:defs.bzl", "UvPyPackageInfo")

UvPyPackageInfo(<a href="#UvPyPackageInfo-label">label</a>, <a href="#UvPyPackageInfo-dist_name">dist_name</a>, <a href="#UvPyPackageInfo-pyproject">pyproject</a>, <a href="#UvPyPackageInfo-srcs">srcs</a>, <a href="#UvPyPackageInfo-data">data</a>, <a href="#UvPyPackageInfo-transitive_packages">transitive_packages</a>, <a href="#UvPyPackageInfo-transitive_wheels">transitive_wheels</a>)
</pre>

Package info

**FIELDS**

| Name  | Description |
| :------------- | :------------- |
| <a id="UvPyPackageInfo-label"></a>label |  Stringified Bazel label    |
| <a id="UvPyPackageInfo-dist_name"></a>dist_name |  Python distribution name (PyPI/dist name)    |
| <a id="UvPyPackageInfo-pyproject"></a>pyproject |  The pyproject.toml File    |
| <a id="UvPyPackageInfo-srcs"></a>srcs |  Depset of source files    |
| <a id="UvPyPackageInfo-data"></a>data |  Depset of data files    |
| <a id="UvPyPackageInfo-transitive_packages"></a>transitive_packages |  List of structs(**UvPyPackageInfo) including self    |
| <a id="UvPyPackageInfo-transitive_wheels"></a>transitive_wheels |  List of structs(**UvPyWheelInfo) including self    |


<a id="UvPyWheelInfo"></a>

## UvPyWheelInfo

<pre>
load("@rules_uv_bare//uv:defs.bzl", "UvPyWheelInfo")

UvPyWheelInfo(<a href="#UvPyWheelInfo-label">label</a>, <a href="#UvPyWheelInfo-wheel">wheel</a>, <a href="#UvPyWheelInfo-dist_name">dist_name</a>, <a href="#UvPyWheelInfo-frozen">frozen</a>)
</pre>

Wheel info

**FIELDS**

| Name  | Description |
| :------------- | :------------- |
| <a id="UvPyWheelInfo-label"></a>label |  Stringified Bazel label    |
| <a id="UvPyWheelInfo-wheel"></a>wheel |  .whl File    |
| <a id="UvPyWheelInfo-dist_name"></a>dist_name |  Python distribution name (PyPI/dist name)    |
| <a id="UvPyWheelInfo-frozen"></a>frozen |  If False, the wheel hash is re-resolved into uv.lock each build    |


<a id="to_exec_root_path"></a>

## to_exec_root_path

<pre>
load("@rules_uv_bare//uv:defs.bzl", "to_exec_root_path")

to_exec_root_path(<a href="#to_exec_root_path-path">path</a>)
</pre>

Return `path` with the exec-root marker if it is a relative path. Absolute paths are returned as-is.

**PARAMETERS**


| Name  | Description | Default Value |
| :------------- | :------------- | :------------- |
| <a id="to_exec_root_path-path"></a>path |  <p align="center"> - </p>   |  none |


<a id="uv_py_deploy"></a>

## uv_py_deploy

<pre>
load("@rules_uv_bare//uv:defs.bzl", "uv_py_deploy")

uv_py_deploy(<a href="#uv_py_deploy-name">name</a>, <a href="#uv_py_deploy-workspace">workspace</a>, <a href="#uv_py_deploy-kwargs">**kwargs</a>)
</pre>

Copies the ``.bundle`` build artifact to a user-specified directory.

**PARAMETERS**


| Name  | Description | Default Value |
| :------------- | :------------- | :------------- |
| <a id="uv_py_deploy-name"></a>name |  target name.   |  none |
| <a id="uv_py_deploy-workspace"></a>workspace |  uv_py_workspace target.   |  none |
| <a id="uv_py_deploy-kwargs"></a>kwargs |  additional arguments forwarded to ``sh_binary``.   |  none |


<a id="uv_py_entrypoint"></a>

## uv_py_entrypoint

<pre>
load("@rules_uv_bare//uv:defs.bzl", "uv_py_entrypoint")

uv_py_entrypoint(<a href="#uv_py_entrypoint-name">name</a>, <a href="#uv_py_entrypoint-workspace">workspace</a>, <a href="#uv_py_entrypoint-cmd">cmd</a>, <a href="#uv_py_entrypoint-kwargs">**kwargs</a>)
</pre>

Runs a command in the workspace venv.

Also creates a ``<name>.bundle`` sub-target that uses the relocatable self-contained env.

``cmd`` is embedded in the built binary, so both ``bazel run``
and direct invocation (``./bazel-bin/<name>``) work.

``rlocation`` bash function is supported in ``cmd`` to reference data files.

```bzl
# Creates :run (dev) and :run.bundle (self-contained, bundle)
uv_py_entrypoint(
    name = "run",
    workspace = ":ws",
    cmd = ["my-app"],
)
```


**PARAMETERS**


| Name  | Description | Default Value |
| :------------- | :------------- | :------------- |
| <a id="uv_py_entrypoint-name"></a>name |  target name.   |  none |
| <a id="uv_py_entrypoint-workspace"></a>workspace |  uv_py_workspace target.   |  none |
| <a id="uv_py_entrypoint-cmd"></a>cmd |  command as a list of strings (e.g. ``["my-app"]`` or ``["python", "script.py"]``). Supports ``$(rlocation REPO/path)`` for referencing runfiles.   |  none |
| <a id="uv_py_entrypoint-kwargs"></a>kwargs |  additional arguments forwarded to the underlying rule.   |  none |


<a id="uv_py_export"></a>

## uv_py_export

<pre>
load("@rules_uv_bare//uv:defs.bzl", "uv_py_export")

uv_py_export(<a href="#uv_py_export-name">name</a>, <a href="#uv_py_export-workspace">workspace</a>, <a href="#uv_py_export-visibility">visibility</a>)
</pre>

Exports a portable workspace directory via ``bazel run``.

**Example**

```bzl
uv_py_export(
    name = "ws.export",
    workspace = ":ws",
)
```


**PARAMETERS**


| Name  | Description | Default Value |
| :------------- | :------------- | :------------- |
| <a id="uv_py_export-name"></a>name |  target name.   |  none |
| <a id="uv_py_export-workspace"></a>workspace |  the ``uv_py_workspace`` target to export from.   |  none |
| <a id="uv_py_export-visibility"></a>visibility |  Bazel visibility.   |  `["//visibility:public"]` |


<a id="uv_py_lock"></a>

## uv_py_lock

<pre>
load("@rules_uv_bare//uv:defs.bzl", "uv_py_lock")

uv_py_lock(<a href="#uv_py_lock-name">name</a>, <a href="#uv_py_lock-workspace">workspace</a>, <a href="#uv_py_lock-visibility">visibility</a>)
</pre>

Updates ``uv.lock`` in-place via ``bazel run``.

**Example**

```bzl
uv_py_lock(
    name = "ws.lock",
    workspace = ":ws",
)
```


**PARAMETERS**


| Name  | Description | Default Value |
| :------------- | :------------- | :------------- |
| <a id="uv_py_lock-name"></a>name |  target name.   |  none |
| <a id="uv_py_lock-workspace"></a>workspace |  the ``uv_py_workspace`` target to lock.   |  none |
| <a id="uv_py_lock-visibility"></a>visibility |  Bazel visibility.   |  `["//visibility:public"]` |


<a id="uv_py_package"></a>

## uv_py_package

<pre>
load("@rules_uv_bare//uv:defs.bzl", "uv_py_package")

uv_py_package(<a href="#uv_py_package-name">name</a>, <a href="#uv_py_package-pyproject">pyproject</a>, <a href="#uv_py_package-srcs">srcs</a>, <a href="#uv_py_package-data">data</a>, <a href="#uv_py_package-deps">deps</a>, <a href="#uv_py_package-wheel_deps">wheel_deps</a>, <a href="#uv_py_package-dist_name">dist_name</a>, <a href="#uv_py_package-visibility">visibility</a>)
</pre>

Declares a Python package by a pyproject.toml.

Note that ``srcs`` and ``data`` are used only for triggering a build.
The actual build is done by ``uv`` outside of the Bazel sandbox, and these attributes are completely ignored.

**Example**

```bzl
uv_py_package(name = "my_package")
```


**PARAMETERS**


| Name  | Description | Default Value |
| :------------- | :------------- | :------------- |
| <a id="uv_py_package-name"></a>name |  target name.   |  none |
| <a id="uv_py_package-pyproject"></a>pyproject |  path to pyproject.toml (default "pyproject.toml").   |  `"pyproject.toml"` |
| <a id="uv_py_package-srcs"></a>srcs |  Python source files. Defaults to ``glob(["**/*.py"])`` with ``build/``, ``dist/``, ``.venv/``, and ``__pycache__/`` excluded.   |  `None` |
| <a id="uv_py_package-data"></a>data |  non-Python data files to include in the package (YAML, JSON, CSV, .pyi stubs, py.typed markers, templates, etc.).   |  `None` |
| <a id="uv_py_package-deps"></a>deps |  first-party uv_py_package targets this package depends on. Enables automatic transitive member resolution in uv_py_workspace.   |  `[]` |
| <a id="uv_py_package-wheel_deps"></a>wheel_deps |  uv_py_import_wheel targets this package depends on. Wheels are collected transitively by uv_py_workspace.   |  `[]` |
| <a id="uv_py_package-dist_name"></a>dist_name |  Python distribution name override (i.e. ``[project].name`` in its pyproject.toml). Defaults to ``name``. Underscores are normalized to hyphens.   |  `None` |
| <a id="uv_py_package-visibility"></a>visibility |  Bazel visibility.   |  `["//visibility:public"]` |


<a id="uv_py_test"></a>

## uv_py_test

<pre>
load("@rules_uv_bare//uv:defs.bzl", "uv_py_test")

uv_py_test(<a href="#uv_py_test-name">name</a>, <a href="#uv_py_test-workspace">workspace</a>, <a href="#uv_py_test-cmd">cmd</a>, <a href="#uv_py_test-kwargs">**kwargs</a>)
</pre>

Runs a command in the workspace venv as a test.

See ``uv_py_entrypoint`` for details on ``cmd`` and ``rlocation`` support.

```bzl
uv_py_test(
    name = "test",
    workspace = ":ws",
    cmd = ["pytest", "tests/"],
)
```


**PARAMETERS**


| Name  | Description | Default Value |
| :------------- | :------------- | :------------- |
| <a id="uv_py_test-name"></a>name |  target name.   |  none |
| <a id="uv_py_test-workspace"></a>workspace |  uv_py_workspace target.   |  none |
| <a id="uv_py_test-cmd"></a>cmd |  command as a list of strings (e.g. ``["pytest", "tests/"]``). Supports ``$(rlocation REPO/path)`` for referencing runfiles.   |  none |
| <a id="uv_py_test-kwargs"></a>kwargs |  additional arguments forwarded to the underlying rule.   |  none |


<a id="uv_py_wheel"></a>

## uv_py_wheel

<pre>
load("@rules_uv_bare//uv:defs.bzl", "uv_py_wheel")

uv_py_wheel(<a href="#uv_py_wheel-name">name</a>, <a href="#uv_py_wheel-package">package</a>, <a href="#uv_py_wheel-workspace">workspace</a>, <a href="#uv_py_wheel-visibility">visibility</a>)
</pre>

Builds a .whl from a uv_py_package target.

**Example**

```bzl
uv_py_wheel(
    name = "wheel",
    package = ":my_package",
)
```


**PARAMETERS**


| Name  | Description | Default Value |
| :------------- | :------------- | :------------- |
| <a id="uv_py_wheel-name"></a>name |  target name.   |  none |
| <a id="uv_py_wheel-package"></a>package |  uv_py_package target to build.   |  none |
| <a id="uv_py_wheel-workspace"></a>workspace |  optional ``uv_py_workspace`` target. When set, the wheel is built with that workspace's ``host_python`` via ``uv build --python <path>``. When unset (default), ``uv build`` is run without ``--python`` and uv auto-discovers an interpreter, which is sufficient for pure-Python wheels. Set this when the package has a native extension that should pin a specific Python ABI.   |  `None` |
| <a id="uv_py_wheel-visibility"></a>visibility |  Bazel visibility.   |  `["//visibility:public"]` |


<a id="uv_py_workspace"></a>

## uv_py_workspace

<pre>
load("@rules_uv_bare//uv:defs.bzl", "uv_py_workspace")

uv_py_workspace(<a href="#uv_py_workspace-name">name</a>, <a href="#uv_py_workspace-members">members</a>, <a href="#uv_py_workspace-lock">lock</a>, <a href="#uv_py_workspace-host_python">host_python</a>, <a href="#uv_py_workspace-wheels">wheels</a>, <a href="#uv_py_workspace-platform_markers">platform_markers</a>, <a href="#uv_py_workspace-requires_python">requires_python</a>,
                <a href="#uv_py_workspace-dependency_groups">dependency_groups</a>, <a href="#uv_py_workspace-extra_pyproject_content">extra_pyproject_content</a>, <a href="#uv_py_workspace-env">env</a>, <a href="#uv_py_workspace-inherit_host_env">inherit_host_env</a>, <a href="#uv_py_workspace-build_env_deps">build_env_deps</a>,
                <a href="#uv_py_workspace-bundle_target_platform">bundle_target_platform</a>, <a href="#uv_py_workspace-bundle_manylinux">bundle_manylinux</a>, <a href="#uv_py_workspace-bundle_build_deps">bundle_build_deps</a>, <a href="#uv_py_workspace-bundle_interpreter">bundle_interpreter</a>,
                <a href="#uv_py_workspace-target_compatible_with">target_compatible_with</a>, <a href="#uv_py_workspace-visibility">visibility</a>)
</pre>

Define and builds a uv workspace from uv_py_package targets.

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


**PARAMETERS**


| Name  | Description | Default Value |
| :------------- | :------------- | :------------- |
| <a id="uv_py_workspace-name"></a>name |  target name.   |  none |
| <a id="uv_py_workspace-members"></a>members |  uv_py_package targets (workspace members).   |  none |
| <a id="uv_py_workspace-lock"></a>lock |  the uv.lock file.   |  none |
| <a id="uv_py_workspace-host_python"></a>host_python |  uv python key for the **host** interpreter that runs ``uv lock`` / ``uv sync`` / ``uv build`` (e.g. ``"cpython-3.12"`` or ``"cpython-3.12.5"``). Anything ``uv python list`` resolves is accepted. The interpreter is fetched via ``uv python install`` at action time and reused across actions via the uv cache.   |  none |
| <a id="uv_py_workspace-wheels"></a>wheels |  uv_py_import_wheel targets whose .whl files are registered as ``[tool.uv.sources]`` path entries in the generated pyproject.toml.   |  `[]` |
| <a id="uv_py_workspace-platform_markers"></a>platform_markers |  dict of platform label to PEP 508 marker string. When provided, each wheel is built under every listed platform via a split transition. Keys are platform labels (e.g. ``":linux_x86_64"``), values are marker expressions (e.g. ``"platform_machine == 'x86_64'"``).   |  `{}` |
| <a id="uv_py_workspace-requires_python"></a>requires_python |  optional Python version constraint written to ``project.requires-python`` in the generated workspace pyproject.toml. Leave empty to omit the field. uv lock will then use the ``host_python`` interpreter (and member pyprojects' ``requires-python``) for resolution scope. Set explicitly (e.g. ``">=3.10"``) when you need a specific range.   |  `""` |
| <a id="uv_py_workspace-dependency_groups"></a>dependency_groups |  dict of group name to dep list (e.g. ``{"test": ["pytest>=8.0"]}``).   |  `{}` |
| <a id="uv_py_workspace-extra_pyproject_content"></a>extra_pyproject_content |  additional TOML content appended verbatim to the generated pyproject.toml.   |  `""` |
| <a id="uv_py_workspace-env"></a>env |  dict of environment variable name to value, forwarded to ``uv sync`` (e.g. ``{"CC": "/usr/bin/gcc"}``).   |  `{}` |
| <a id="uv_py_workspace-inherit_host_env"></a>inherit_host_env |  if True, inherit the host shell environment when running ``uv sync``. Prefer ``build_env_deps`` for reproducible builds.   |  `False` |
| <a id="uv_py_workspace-build_env_deps"></a>build_env_deps |  list of targets providing ``UvBuildEnvInfo``. If the ``env`` attr sets the same variable, it takes precedence.   |  `[]` |
| <a id="uv_py_workspace-bundle_target_platform"></a>bundle_target_platform |  cross-compile platform suffix for the ``.bundle`` target (e.g. ``"linux-aarch64-gnu"`` / ``"macos-aarch64-none"``). The target uv python key is constructed with ``host_python`` as ``{host_python.impl}-{host_python.version}-{bundle_target_platform}``. Typically a ``select()`` over target platforms. Leave empty (default) for a non-cross-compile bundle where the bundled Python matches the host.   |  `""` |
| <a id="uv_py_workspace-bundle_manylinux"></a>bundle_manylinux |  optional manylinux baseline override for Linux+gnu cross-compile (e.g. ``"manylinux_2_28"``). The default value is ``manylinux2014`` (glibc 2.17). Ignored for musl and other OS.   |  `""` |
| <a id="uv_py_workspace-bundle_build_deps"></a>bundle_build_deps |  Python packages to pre-install as host-platform build tools (e.g. ``["setuptools", "wheel", "uv-build>=0.7"]``).   |  `[]` |
| <a id="uv_py_workspace-bundle_interpreter"></a>bundle_interpreter |  if ``True`` (default), bundle a standalone Python interpreter. If ``False``, the bundle doesn't include an interpreter, and puts a ``bin/python3`` shim instead that searches ``python3.X``/``python3`` over ``PATH``.   |  `True` |
| <a id="uv_py_workspace-target_compatible_with"></a>target_compatible_with |  standard Bazel ``target_compatible_with`` constraint list. Targets whose platform doesn't satisfy these constraints are skipped. It also applied to the sub-targets.   |  `[]` |
| <a id="uv_py_workspace-visibility"></a>visibility |  Bazel visibility.   |  `["//visibility:public"]` |


