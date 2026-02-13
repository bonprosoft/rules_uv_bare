"""Rules for rules_uv_bare.

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
"""

load("//uv/private:deploy.bzl", _uv_py_deploy = "uv_py_deploy")
load("//uv/private:entrypoint.bzl", _uv_py_entrypoint = "uv_py_entrypoint", _uv_py_test = "uv_py_test")
load("//uv/private:import_wheel.bzl", _uv_py_import_wheel = "uv_py_import_wheel")
load("//uv/private:lock.bzl", _uv_py_export = "uv_py_export", _uv_py_lock = "uv_py_lock")
load("//uv/private:package.bzl", _DEFAULT_PY_EXCLUDES = "DEFAULT_PY_EXCLUDES", _uv_py_package = "uv_py_package")
load("//uv/private:providers.bzl", _UvPyPackageInfo = "UvPyPackageInfo", _UvPyWheelInfo = "UvPyWheelInfo")
load("//uv/private:wheel.bzl", _uv_py_wheel = "uv_py_wheel")
load("//uv/private:workspace.bzl", _uv_py_workspace = "uv_py_workspace")

DEFAULT_PY_EXCLUDES = _DEFAULT_PY_EXCLUDES
UvPyPackageInfo = _UvPyPackageInfo
UvPyWheelInfo = _UvPyWheelInfo
uv_py_deploy = _uv_py_deploy
uv_py_entrypoint = _uv_py_entrypoint
uv_py_export = _uv_py_export
uv_py_import_wheel = _uv_py_import_wheel
uv_py_lock = _uv_py_lock
uv_py_package = _uv_py_package
uv_py_test = _uv_py_test
uv_py_wheel = _uv_py_wheel
uv_py_workspace = _uv_py_workspace
