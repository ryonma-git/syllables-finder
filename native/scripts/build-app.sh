#!/bin/bash
set -euo pipefail
project_dir="$(cd "$(dirname "$0")/.." && pwd)"
"$project_dir/scripts/swift-tool.sh" build
binary_dir="$("$project_dir/scripts/swift-tool.sh" build --show-bin-path)"
app_dir="$project_dir/build/Singing Workspace.app"
mkdir -p "$app_dir/Contents/MacOS" "$app_dir/Contents/Resources"
cp "$binary_dir/SingingWorkspace" "$app_dir/Contents/MacOS/SingingWorkspace"
cp "$project_dir/Resources/Info.plist" "$app_dir/Contents/Info.plist"
codesign --force --sign - "$app_dir"
printf '%s\n' "$app_dir"
