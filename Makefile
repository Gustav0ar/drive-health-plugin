SHELL := /bin/sh

PLUGIN_DIR := drive-health

.PHONY: test plugin-test distribution

test: plugin-test distribution

plugin-test:
	$(MAKE) -C $(PLUGIN_DIR) test

distribution:
	sh -n tools/check-distribution.sh tools/test-distribution.sh
	@if command -v shellcheck >/dev/null 2>&1; then shellcheck tools/*.sh; fi
	sh tools/check-distribution.sh
	sh tools/test-distribution.sh
