<!-- Generated with Stardoc: http://skydoc.bazel.build -->

Rules for rules_uv_bare.

Provides:
  - uv_py_package: declares a Python package with its pyproject.toml
  - uv_py_workspace: defines and creates a uv workspace from packages
      - .run: runs commands in the workspace venv
      - .activate: prints path to venv activate script for shell sourcing
  - uv_py_lock: updates uv.lock in-place
  - uv_py_export: exports a portable workspace directory
  - uv_py_entrypoint: runs commands in the workspace venv
  - uv_py_test: runs tests in the workspace venv
  - uv_py_wheel: builds a .whl from a uv_py_package target
  - uv_py_import_wheel: imports a wheel file for use with uv_py_package or uv_py_workspace
  - uv_py_deploy: deploys workspace into a standalone directory

<a id="uv_py_import_wheel"></a>

## uv_py_import_wheel

<pre>
load("@rules_uv_bare//uv:defs.bzl", "uv_py_import_wheel")

uv_py_import_wheel(<a href="#uv_py_import_wheel-name">name</a>, <a href="#uv_py_import_wheel-src">src</a>, <a href="#uv_py_import_wheel-frozen">frozen</a>, <a href="#uv_py_import_wheel-python_package_name">python_package_name</a>)
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
| <a id="uv_py_import_wheel-frozen"></a>frozen |  If False, the wheel hash is recomputed every build. Use when the wheel is built by Bazel and changes frequently.   | Boolean | optional |  `True`  |
| <a id="uv_py_import_wheel-python_package_name"></a>python_package_name |  Python package name override. Inferred from the wheel filename if not set. Underscores are normalized to hyphens.   | String | optional |  `""`  |


<a id="UvBuildEnvInfo"></a>

## UvBuildEnvInfo

<pre>
load("@rules_uv_bare//uv:defs.bzl", "UvBuildEnvInfo")

UvBuildEnvInfo(<a href="#UvBuildEnvInfo-env">env</a>)
</pre>

Environment variables to forward to uv sync and wheel builds.

**FIELDS**

| Name  | Description |
| :------------- | :------------- |
| <a id="UvBuildEnvInfo-env"></a>env |  Dict of environment variable name to value    |


<a id="UvPyPackageInfo"></a>

## UvPyPackageInfo

<pre>
load("@rules_uv_bare//uv:defs.bzl", "UvPyPackageInfo")

UvPyPackageInfo(<a href="#UvPyPackageInfo-label_name">label_name</a>, <a href="#UvPyPackageInfo-python_package_name">python_package_name</a>, <a href="#UvPyPackageInfo-pyproject">pyproject</a>, <a href="#UvPyPackageInfo-srcs">srcs</a>, <a href="#UvPyPackageInfo-data">data</a>, <a href="#UvPyPackageInfo-transitive_packages">transitive_packages</a>,
                <a href="#UvPyPackageInfo-transitive_wheels">transitive_wheels</a>)
</pre>

Package info

**FIELDS**

| Name  | Description |
| :------------- | :------------- |
| <a id="UvPyPackageInfo-label_name"></a>label_name |  Bazel label    |
| <a id="UvPyPackageInfo-python_package_name"></a>python_package_name |  Python package name    |
| <a id="UvPyPackageInfo-pyproject"></a>pyproject |  The pyproject.toml File    |
| <a id="UvPyPackageInfo-srcs"></a>srcs |  Depset of source files    |
| <a id="UvPyPackageInfo-data"></a>data |  Depset of data files    |
| <a id="UvPyPackageInfo-transitive_packages"></a>transitive_packages |  List of structs(**UvPyPackageInfo) including self    |
| <a id="UvPyPackageInfo-transitive_wheels"></a>transitive_wheels |  List of structs(**UvPyWheelInfo) including self    |


<a id="UvPyWheelInfo"></a>

## UvPyWheelInfo

<pre>
load("@rules_uv_bare//uv:defs.bzl", "UvPyWheelInfo")

UvPyWheelInfo(<a href="#UvPyWheelInfo-label_name">label_name</a>, <a href="#UvPyWheelInfo-wheel">wheel</a>, <a href="#UvPyWheelInfo-python_package_name">python_package_name</a>, <a href="#UvPyWheelInfo-frozen">frozen</a>)
</pre>

Wheel info

**FIELDS**

| Name  | Description |
| :------------- | :------------- |
| <a id="UvPyWheelInfo-label_name"></a>label_name |  Bazel label    |
| <a id="UvPyWheelInfo-wheel"></a>wheel |  .whl File    |
| <a id="UvPyWheelInfo-python_package_name"></a>python_package_name |  Python package name    |
| <a id="UvPyWheelInfo-frozen"></a>frozen |  If false, the hash is recomputed at build time    |


<a id="uv_py_deploy"></a>

## uv_py_deploy

<pre>
load("@rules_uv_bare//uv:defs.bzl", "uv_py_deploy")

uv_py_deploy(<a href="#uv_py_deploy-name">name</a>, <a href="#uv_py_deploy-workspace">workspace</a>, <a href="#uv_py_deploy-python_version">python_version</a>, <a href="#uv_py_deploy-target_platform">target_platform</a>)
</pre>

Creates a deployment directory.

**Usage**

```shell
bazel run //:target -- /path/to/output
```

For cross-platform packaging, use ``select()`` on ``target_platform``:

```bzl
uv_py_deploy(
    name = "deploy",
    workspace = ":ws",
    python_version = "3.12",
    target_platform = select({
        "//:linux_x86_64": "x86_64-manylinux2014",
        "//:linux_aarch64": "aarch64-manylinux2014",
    }),
)
```


**PARAMETERS**


| Name  | Description | Default Value |
| :------------- | :------------- | :------------- |
| <a id="uv_py_deploy-name"></a>name |  target name.   |  none |
| <a id="uv_py_deploy-workspace"></a>workspace |  uv_py_workspace target.   |  none |
| <a id="uv_py_deploy-python_version"></a>python_version |  Target Python version (e.g. "3.12").   |  none |
| <a id="uv_py_deploy-target_platform"></a>target_platform |  uv platform string (e.g. "x86_64-manylinux2014"), typically from ``select({...})``. Empty string means host.   |  `""` |


<a id="uv_py_entrypoint"></a>

## uv_py_entrypoint

<pre>
load("@rules_uv_bare//uv:defs.bzl", "uv_py_entrypoint")

uv_py_entrypoint(<a href="#uv_py_entrypoint-name">name</a>, <a href="#uv_py_entrypoint-workspace">workspace</a>, <a href="#uv_py_entrypoint-cmd">cmd</a>, <a href="#uv_py_entrypoint-kwargs">**kwargs</a>)
</pre>

Runs a command in the workspace venv.

**Example**
```bzl
uv_py_entrypoint(
    name = "run_app",
    workspace = ":my_workspace",
    cmd = ["python", "-m", "my_app"],
)
```


**PARAMETERS**


| Name  | Description | Default Value |
| :------------- | :------------- | :------------- |
| <a id="uv_py_entrypoint-name"></a>name |  target name.   |  none |
| <a id="uv_py_entrypoint-workspace"></a>workspace |  uv_py_workspace target.   |  none |
| <a id="uv_py_entrypoint-cmd"></a>cmd |  command as a list of strings (e.g. ``["python", "script.py"]``).   |  none |
| <a id="uv_py_entrypoint-kwargs"></a>kwargs |  additional arguments forwarded to ``sh_binary``.   |  none |


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

uv_py_package(<a href="#uv_py_package-name">name</a>, <a href="#uv_py_package-pyproject">pyproject</a>, <a href="#uv_py_package-srcs">srcs</a>, <a href="#uv_py_package-data">data</a>, <a href="#uv_py_package-deps">deps</a>, <a href="#uv_py_package-wheel_deps">wheel_deps</a>, <a href="#uv_py_package-python_package_name">python_package_name</a>, <a href="#uv_py_package-visibility">visibility</a>)
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
| <a id="uv_py_package-python_package_name"></a>python_package_name |  Python package name override. Defaults to ``name``. Underscores are normalized to hyphens.   |  `None` |
| <a id="uv_py_package-visibility"></a>visibility |  Bazel visibility.   |  `["//visibility:public"]` |


<a id="uv_py_test"></a>

## uv_py_test

<pre>
load("@rules_uv_bare//uv:defs.bzl", "uv_py_test")

uv_py_test(<a href="#uv_py_test-name">name</a>, <a href="#uv_py_test-workspace">workspace</a>, <a href="#uv_py_test-cmd">cmd</a>, <a href="#uv_py_test-kwargs">**kwargs</a>)
</pre>

Runs a command in the workspace venv as a test.

**Example**
```bzl
uv_py_test(
    name = "test_app",
    workspace = ":my_workspace",
    cmd = ["python", "-m", "pytest", "tests/"],
)
```


**PARAMETERS**


| Name  | Description | Default Value |
| :------------- | :------------- | :------------- |
| <a id="uv_py_test-name"></a>name |  target name.   |  none |
| <a id="uv_py_test-workspace"></a>workspace |  uv_py_workspace target.   |  none |
| <a id="uv_py_test-cmd"></a>cmd |  command as a list of strings (e.g. ``["python", "-m", "pytest", "tests/"]``).   |  none |
| <a id="uv_py_test-kwargs"></a>kwargs |  additional arguments forwarded to ``sh_test``.   |  none |


<a id="uv_py_wheel"></a>

## uv_py_wheel

<pre>
load("@rules_uv_bare//uv:defs.bzl", "uv_py_wheel")

uv_py_wheel(<a href="#uv_py_wheel-name">name</a>, <a href="#uv_py_wheel-package">package</a>, <a href="#uv_py_wheel-visibility">visibility</a>)
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
| <a id="uv_py_wheel-visibility"></a>visibility |  Bazel visibility.   |  `["//visibility:public"]` |


<a id="uv_py_workspace"></a>

## uv_py_workspace

<pre>
load("@rules_uv_bare//uv:defs.bzl", "uv_py_workspace")

uv_py_workspace(<a href="#uv_py_workspace-name">name</a>, <a href="#uv_py_workspace-members">members</a>, <a href="#uv_py_workspace-lock">lock</a>, <a href="#uv_py_workspace-wheels">wheels</a>, <a href="#uv_py_workspace-target_platforms">target_platforms</a>, <a href="#uv_py_workspace-python_requires">python_requires</a>, <a href="#uv_py_workspace-dependency_groups">dependency_groups</a>,
                <a href="#uv_py_workspace-extra_pyproject_content">extra_pyproject_content</a>, <a href="#uv_py_workspace-uv_sync_args">uv_sync_args</a>, <a href="#uv_py_workspace-env">env</a>, <a href="#uv_py_workspace-env_inherit">env_inherit</a>, <a href="#uv_py_workspace-env_providers">env_providers</a>,
                <a href="#uv_py_workspace-target_compatible_with">target_compatible_with</a>, <a href="#uv_py_workspace-visibility">visibility</a>)
</pre>

Define and builds a uv workspace from uv_py_package targets.

Also creates the following sub-targets:

- ``<name>.run``: runs commands in the workspace venv
- ``<name>.activate``: prints the path to the venv activate script for shell sourcing

Use ``uv_py_lock`` and ``uv_py_export`` for lock-file management and workspace export.

**Example**

```bzl
uv_py_workspace(
    name = "my_workspace",
    members = ["//pkg_a", "//pkg_b"],
    lock = "uv.lock",
)
```


**PARAMETERS**


| Name  | Description | Default Value |
| :------------- | :------------- | :------------- |
| <a id="uv_py_workspace-name"></a>name |  target name.   |  none |
| <a id="uv_py_workspace-members"></a>members |  uv_py_package targets (workspace members).   |  none |
| <a id="uv_py_workspace-lock"></a>lock |  the uv.lock file.   |  none |
| <a id="uv_py_workspace-wheels"></a>wheels |  uv_py_import_wheel targets whose .whl files are registered as ``[tool.uv.sources]`` path entries in the generated pyproject.toml.   |  `[]` |
| <a id="uv_py_workspace-target_platforms"></a>target_platforms |  dict of platform label to PEP 508 marker string. When provided, each wheel is built under every listed platform via a split transition. Keys are platform labels (e.g. ``":linux_x86_64"``), values are marker expressions (e.g. ``"platform_machine == 'x86_64'"``).   |  `{}` |
| <a id="uv_py_workspace-python_requires"></a>python_requires |  Python version constraint.   |  `">=3.11"` |
| <a id="uv_py_workspace-dependency_groups"></a>dependency_groups |  dict of group name to dep list (default ``{"test": ["pytest>=8.0"]}``). Pass ``{}`` to disable.   |  `{"test": ["pytest>=8.0"]}` |
| <a id="uv_py_workspace-extra_pyproject_content"></a>extra_pyproject_content |  additional TOML content appended verbatim to the generated pyproject.toml (e.g. ``[tool.pytest.ini_options]``).   |  `""` |
| <a id="uv_py_workspace-uv_sync_args"></a>uv_sync_args |  additional arguments passed to ``uv sync`` (e.g. ``["--index-url", "https://private.pypi.org/simple"]``).   |  `[]` |
| <a id="uv_py_workspace-env"></a>env |  dict of environment variable name to value, forwarded to ``uv sync`` (e.g. ``{"CC": "/usr/bin/gcc"}``).   |  `{}` |
| <a id="uv_py_workspace-env_inherit"></a>env_inherit |  if True, inherit the host shell environment when running ``uv sync``. Prefer ``env_providers`` for reproducible builds.   |  `False` |
| <a id="uv_py_workspace-env_providers"></a>env_providers |  list of targets providing ``UvBuildEnvInfo``. If the ``env`` attr sets the same variable, it takes precedence.   |  `[]` |
| <a id="uv_py_workspace-target_compatible_with"></a>target_compatible_with |  standard Bazel ``target_compatible_with`` constraint list. Targets whose platform doesn't satisfy these constraints are skipped. It also applied to the sub-targets.   |  `[]` |
| <a id="uv_py_workspace-visibility"></a>visibility |  Bazel visibility.   |  `["//visibility:public"]` |


