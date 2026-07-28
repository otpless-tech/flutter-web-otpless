#!/usr/bin/env bash
# Analyzer drift check.
#
# Why a baseline instead of `--fatal-infos`: this package legitimately imports
# `dart:html` and `dart:js`, which the analyzer reports as deprecated and as
# "web-only libraries outside a Flutter web plugin". Those infos are real and
# must stay VISIBLE — `dart:html`/`dart:js` are on their way out, and this
# package will need a `package:web` + `dart:js_interop` rewrite. Suppressing
# them with `// ignore:` would hide the single largest piece of technical risk
# in the repo, and turning on `--fatal-infos` today would just force someone to
# suppress them.
#
# So: the current info list is committed as a baseline. `flutter analyze` must
# still exit 0 (no errors, no warnings), AND the set of infos must not grow.
# A new lint or a new deprecation fails the gate; fixing one also fails it,
# loudly, and you accept it with `make analyze-update`.
#
# Usage:
#   scripts/check-analyzer-baseline.sh
#   scripts/check-analyzer-baseline.sh --update

set -uo pipefail

BASELINE="analysis/analyzer-baseline.txt"
UPDATE=0
[[ "${1:-}" == "--update" ]] && UPDATE=1

# --no-fatal-infos: errors and warnings still fail here; infos are governed by
# the baseline diff below.
raw="$(flutter analyze --no-fatal-infos 2>&1)"
status=$?

# Keep only the issue lines, and drop the file:line:column coordinates so the
# baseline does not churn on every unrelated edit above an existing issue.
normalised="$(printf '%s\n' "$raw" \
  | grep -E '^[[:space:]]+(info|warning|error) •' \
  | sed -E 's/ • ([^ •]+):[0-9]+:[0-9]+ • / • \1 • /' \
  | sed -E 's/^[[:space:]]+//' \
  | LC_ALL=C sort)"

if (( UPDATE )); then
  mkdir -p "$(dirname "$BASELINE")"
  {
    echo "# flutter analyze baseline — GENERATED, regenerate with: make analyze-update"
    echo "# File:line:column coordinates are stripped on purpose."
    echo "#"
    echo "# These are INFOS, deliberately not suppressed. The dart:html / dart:js"
    echo "# deprecations are this package's biggest piece of technical debt: it"
    echo "# needs a package:web + dart:js_interop rewrite. See CLAUDE.md."
    printf '%s\n' "$normalised"
  } > "$BASELINE"
  echo "updated $BASELINE"
  exit 0
fi

if (( status != 0 )); then
  echo "flutter analyze exited $status — errors or warnings present:"
  printf '%s\n' "$raw"
  exit 1
fi

if [[ ! -f "$BASELINE" ]]; then
  echo "error: $BASELINE is missing. Run: make analyze-update"
  exit 1
fi

expected="$(grep -v '^#' "$BASELINE" | grep -v '^[[:space:]]*$')"
actual="$normalised"

if [[ "$expected" == "$actual" ]]; then
  count=$(printf '%s\n' "$actual" | grep -c . || true)
  echo "analyzer: 0 errors, 0 warnings; ${count} infos, all in the committed baseline"
  exit 0
fi

echo ""
echo "ANALYZER OUTPUT CHANGED — $BASELINE is out of date."
echo ""
echo "  - = baseline   + = current"
echo ""
diff <(printf '%s\n' "$expected") <(printf '%s\n' "$actual") \
  | grep -E '^[<>]' | sed -e 's/^</  -/' -e 's/^>/  +/'
echo ""
echo "New infos: fix them. Removed infos: good — run 'make analyze-update'"
echo "and say so in CHANGELOG.md."
exit 1
