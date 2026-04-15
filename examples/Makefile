# Run every example workspace end-to-end and verify deploy artifacts.
#
# Usage:
#   make                            # every example + native_cross matrix
#   make basic                      # one example by directory name
#   make cross                      # only native_cross cross-platform builds
#   make cross-linux_x86_64         # a single cross-platform build
#   make clean                      # bazel clean every example; wipe /tmp artifacts

SHELL := /bin/bash

EXAMPLES        := basic native env_provider import_from_rules_python native_cross
CROSS_PLATFORMS := linux_x86_64 linux_aarch64 darwin_aarch64
CROSS_TARGETS   := $(addprefix cross-,$(CROSS_PLATFORMS))

.PHONY: all clean cross $(EXAMPLES) $(CROSS_TARGETS)

all: $(EXAMPLES) cross

clean:
	@for ex in $(EXAMPLES); do \
		(cd $$ex && bazel clean --expunge >/dev/null 2>&1) || true; \
	done
	rm -rf /tmp/deploy_test_* /tmp/bazel-uv-cache

# $(call run_example,<dir>)
# Expands into one backslash-continued shell command so `cd` persists.
define run_example
	@set -e; \
	printf '\n\033[1;36m=== Example: %s ===\033[0m\n' '$(1)'; \
	cd $(1); \
	bazel clean --expunge >/dev/null 2>&1; \
	bazel build //:ws //:ws.lock //:ws.export; \
	bazel run //:run; \
	bazel run //:run.deploy; \
	bazel test //:test; \
	chmod -R +w /tmp/deploy_test_$(1) 2>/dev/null || true; \
	rm -rf /tmp/deploy_test_$(1); \
	bazel run //:deploy -- /tmp/deploy_test_$(1); \
	test -x /tmp/deploy_test_$(1)/bin/python3 || { echo "FAIL: /tmp/deploy_test_$(1)/bin/python3 missing" >&2; exit 1; }; \
	test -x /tmp/deploy_test_$(1)/bin/app     || { echo "FAIL: /tmp/deploy_test_$(1)/bin/app missing ([project.scripts] not installed?)" >&2; exit 1; }; \
	/tmp/deploy_test_$(1)/bin/app; \
	printf '\033[1;32m=== %s PASSED ===\033[0m\n' '$(1)'
endef

$(EXAMPLES):
	$(call run_example,$@)

# native_cross cross-platform matrix: build //:ws.deploy for each target
# platform, then verify that msgpack + native_lib .so files and the deployed
# bin/python3 all have the requested architecture.
cross: $(CROSS_TARGETS)

$(CROSS_TARGETS):
	@set -e; \
	plat=$(@:cross-%=%); \
	case "$$plat" in \
		linux_x86_64)   arch="x86-64";      suffix="x86_64-linux-gnu";;  \
		linux_aarch64)  arch="ARM aarch64"; suffix="aarch64-linux-gnu";; \
		darwin_aarch64) arch="arm64";       suffix="darwin";;            \
	esac; \
	printf '\n\033[1;36m=== native_cross --platforms=//:%s ===\033[0m\n' "$$plat"; \
	if [ "$$plat" = darwin_aarch64 ] && [ "$$(uname -s)" != Darwin ]; then \
		printf '  skipping (requires Darwin host)\n'; exit 0; \
	fi; \
	cd native_cross; \
	bazel clean --expunge >/dev/null 2>&1; \
	bazel build --platforms=//:$$plat //:ws.deploy; \
	site=bazel-bin/ws.deploy_dir/lib/python3.12/site-packages; \
	ls   $$site/msgpack/*.so    | grep -q "$$suffix" || { echo "FAIL: msgpack .so suffix != $$suffix" >&2; exit 1; }; \
	file $$site/msgpack/*.so    | grep -q "$$arch"   || { echo "FAIL: msgpack .so not $$arch" >&2; exit 1; }; \
	file $$site/native_lib/*.so | grep -q "$$arch"   || { echo "FAIL: native_lib .so not $$arch" >&2; exit 1; }; \
	out=/tmp/deploy_test_native_cross_$$plat; \
	chmod -R +w $$out 2>/dev/null || true; \
	rm -rf $$out; \
	bazel run --platforms=//:$$plat //:deploy -- $$out; \
	file -L $$out/bin/python3 | grep -q "$$arch" || { echo "FAIL: deployed bin/python3 not $$arch" >&2; exit 1; }; \
	printf '\033[1;32m=== native_cross %s PASSED ===\033[0m\n' "$$plat"
