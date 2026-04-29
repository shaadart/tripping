#!/usr/bin/env bash
# Isolated rule tests: a demo project cannot reach a production Firebase project.
# Requirements: Node/npm, Python 3, and Java 21 on PATH.
set -euo pipefail
cd "$(dirname "$0")/.."
rules_scratch=$(mktemp -d "${TMPDIR:-/tmp}/tripping-rules.XXXXXX")
trap 'rm -rf "$rules_scratch"' EXIT
cp firebase/database.rules.json firebase/emulator.json "$rules_scratch/"
cp tool/firebase_rules_test.py "$rules_scratch/rules_test.py"
cd "$rules_scratch"
# The CLI's debug logger can dump its environment. Do not pass application
# credentials, DEBUG flags or a developer's Firebase login into the test.
env -i PATH="$PATH" HOME="$HOME" \
  XDG_CONFIG_HOME="$rules_scratch/config" \
  npm_config_cache="${npm_config_cache:-$HOME/.npm}" \
  FIREBASE_EMULATORS_PATH="${FIREBASE_EMULATORS_PATH:-$HOME/.cache/firebase/emulators}" \
  CI=true npm exec --yes --package=firebase-tools@15.34.2 -- firebase emulators:exec \
  --only database,auth --project demo-tripping-rules \
  --config emulator.json "python3 rules_test.py"
