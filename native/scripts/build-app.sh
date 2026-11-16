#!/bin/bash
set -euo pipefail
project_dir="$(cd "$(dirname "$0")/.." && pwd)"
"$project_dir/scripts/swift-tool.sh" build
binary_dir="$("$project_dir/scripts/swift-tool.sh" build --show-bin-path)"
app_dir="$project_dir/build/Singing Workspace.app"
mkdir -p "$app_dir/Contents/MacOS" "$app_dir/Contents/Resources"
cp "$binary_dir/SingingWorkspace" "$app_dir/Contents/MacOS/SingingWorkspace"
cp "$project_dir/Resources/Info.plist" "$app_dir/Contents/Info.plist"
cp -R "$binary_dir/SingingWorkspace_SongCore.bundle" "$app_dir/Contents/Resources/"
source_revision="$(git -C "$project_dir" rev-parse --short=12 HEAD 2>/dev/null || printf 'unknown')"
if [ -n "$(git -C "$project_dir" status --porcelain 2>/dev/null)" ]; then
    source_revision="$source_revision (変更あり)"
fi
/usr/libexec/PlistBuddy -c "Add :SingingWorkspaceSourceRevision string $source_revision" "$app_dir/Contents/Info.plist"
codesign --force --sign - "$app_dir"
printf '%s\n' "$app_dir"
