SHELL := /bin/bash
SCRIPTS := bootstrap.sh lib/*.sh steps/*.sh tools/pi-doctor tools/sdbench tools/restore-test

.PHONY: check lint test dry-run doctor

check: lint test

lint:
	shellcheck --external-sources --source-path=SCRIPTDIR --source-path=. $(SCRIPTS)

test:
	bats tests

dry-run:
	bash bootstrap.sh --dry-run --env tests/fixtures/test.env

doctor:
	bash tools/pi-doctor
