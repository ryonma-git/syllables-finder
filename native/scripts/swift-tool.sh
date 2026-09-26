#!/bin/bash
set -euo pipefail
# Local SDK override only; never change xcode-select or system settings.
project_dir="$(cd "$(dirname "$0")/.." && pwd)"
selected_sdk="${SINGING_SDK_PATH:-}"
if [ -z "$selected_sdk" ]; then
    default_sdk="$(xcrun --show-sdk-path)"
    # This host's CLT 27 SDK refers to a SwiftUI macro plugin absent from CLT.
    # Prefer the installed stable SDK in that environment; Xcode users can override.
    stable_sdk="$(dirname "$default_sdk")/MacOSX26.5.sdk"
    if [[ "$default_sdk" == *CommandLineTools* ]] && [ -d "$stable_sdk" ]; then
        selected_sdk="$stable_sdk"
    else
        selected_sdk="$default_sdk"
    fi
fi
operation="${1:-build}"
shift || true
if [ "$operation" = test ] && [[ "$selected_sdk" == *CommandLineTools* ]]; then
    testing_plugin="$(xcrun --find swift | sed 's|/bin/swift$|/lib/swift/host/plugins/testing/libTestingMacros.dylib|')"
    exec swift test --package-path "$project_dir" --sdk "$selected_sdk" --disable-xctest \
        -Xswiftc -load-plugin-library -Xswiftc "$testing_plugin" "$@"
fi
exec swift "$operation" --package-path "$project_dir" --sdk "$selected_sdk" "$@"
