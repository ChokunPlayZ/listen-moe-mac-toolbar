#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SWIFTC="$(xcrun --find swiftc)"
TESTING_PLUGIN="$(dirname "$SWIFTC")/../lib/swift/host/plugins/testing/libTestingMacros.dylib"
# Some Command Line Tools releases ship this plugin without auto-discovering it.
if [[ -f "$TESTING_PLUGIN" ]]; then
    exec swift test --package-path "$ROOT" -Xswiftc -load-plugin-library -Xswiftc "$TESTING_PLUGIN" "$@"
else
    exec swift test --package-path "$ROOT" "$@"
fi
