.DEFAULT_GOAL := help
SHELL := /bin/bash

# `make gate` is the single definition of "verified" for this repo. CI
# (.github/workflows/build-test.yml) runs exactly this target and restates
# nothing, so local and CI cannot drift apart.
#
# Requires: Flutter (stable) and Chrome. Chrome is not optional — this package
# imports dart:html and dart:js, so the Dart VM cannot even compile its tests.
# `flutter test` without --platform chrome fails to LOAD; that is not a broken
# test, it is the VM refusing web-only libraries.

.PHONY: help install format format-fix analyze analyze-update test surface surface-update gate clean example-build

help: ## Show this help
	@grep -hE '^[a-zA-Z_-]+:.*?## ' $(MAKEFILE_LIST) | awk 'BEGIN{FS=":.*?## "};{printf "  \033[36m%-18s\033[0m %s\n", $$1, $$2}'

install: ## flutter pub get (root + example)
	flutter pub get

format: ## Fail if any Dart file is unformatted
	dart format --output=none --set-exit-if-changed .

format-fix: ## Reformat every Dart file in place
	dart format .

analyze: ## flutter analyze + info-baseline drift check
	./scripts/check-analyzer-baseline.sh

analyze-update: ## Accept the current analyzer info list as the baseline
	./scripts/check-analyzer-baseline.sh --update

test: ## Unit tests (Chrome — the VM cannot compile this package)
	flutter test --platform chrome

surface: ## Diff the public Dart + JS-interop surfaces against api/*.txt
	dart run tool/api_dump.dart

surface-update: ## Accept the current surfaces as the new goldens
	dart run tool/api_dump.dart --update

gate: format analyze test surface ## THE canonical verification gate
	@echo ""
	@echo "gate: PASS"
	@echo ""
	@echo "  Scope note: every test stubs the OTPLESS browser bundle"
	@echo "  (https://otpless.com/v2/flutter.js). No test in this repo loads it"
	@echo "  or reaches the OTPLESS backend, and there is no widget or"
	@echo "  integration test. Green means the JS-interop marshalling did not"
	@echo "  regress — it is NOT evidence that authentication works, and it is"
	@echo "  not a coverage claim."

example-build: ## Build the example web app (not in the gate — see CLAUDE.md)
	cd example && flutter build web

clean: ## Remove build output
	flutter clean
	rm -rf example/build
