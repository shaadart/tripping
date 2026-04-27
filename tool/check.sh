#!/usr/bin/env bash
# The quality gate every iteration must pass before it is called done.
set -euo pipefail
cd "$(dirname "$0")/.."

dart format --output=none --set-exit-if-changed lib test integration_test
flutter analyze
flutter test
