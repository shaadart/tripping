#!/usr/bin/env bash
# The quality gate every iteration must pass before it is called done.
set -euo pipefail
cd "$(dirname "$0")/.."

python3 -m unittest discover -s tool -p 'test_*.py'
python3 tool/disclosure_check.py
dart format --output=none --set-exit-if-changed lib test integration_test
flutter analyze
flutter test
