#!/bin/bash
set -euo pipefail
umask 022
web_dir="$(cd "$(dirname "$0")" && pwd)"
package_dir="$web_dir/tools/Lexicon"
core_dir="$web_dir/../native/Sources/SongCore"
dict_dir="$core_dir/Resources/CMUDict"
out_dir="$web_dir/dist"
target="$out_dir/dictionary.js"
mkdir -p "$out_dir"
for asset in engine.js index.html style.css app.js worksheet.js openai.js; do
    install -m 0644 "$web_dir/$asset" "$out_dir/$asset"
done
install -m 0644 "$dict_dir/LICENSE" "$out_dir/CMUdict-LICENSE.txt"
if [[ -s "$target" && "$target" -nt "$0" ]] &&
   [[ -z "$(find "$core_dir" "$package_dir/Sources" "$package_dir/Package.swift" -type f -newer "$target" -print -quit)" ]]; then
    chmod 0644 "$target"
    exit 0
fi

# Use the same SDK selection as the native project, without changing the selected developer tools.
sdk="${SINGING_SDK_PATH:-$(xcrun --show-sdk-path)}"
stable_sdk="$(dirname "$sdk")/MacOSX26.5.sdk"
if [[ -z "${SINGING_SDK_PATH:-}" && "$sdk" == *CommandLineTools* && -d "$stable_sdk" ]]; then
    sdk="$stable_sdk"
fi
swift run --package-path "$package_dir" --sdk "$sdk" -c release Lexicon "$dict_dir" "$target"
chmod 0644 "$target"
