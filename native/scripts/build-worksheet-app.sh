#!/bin/bash
set -euo pipefail
project_dir="$(cd "$(dirname "$0")/.." && pwd)"
build=( "$project_dir/scripts/swift-tool.sh" build -c release --product SingingWorksheet --arch arm64 --arch x86_64 )
"${build[@]}"
product_dir="$("${build[@]}" --show-bin-path)"
output_dir="$project_dir/build"
mkdir -p "$output_dir"
staging="$(mktemp -d "$output_dir/.worksheet-build.XXXXXX")"
trap 'rm -rf "$staging"' EXIT
app_dir="$staging/Singing Worksheet.app"
executable="$app_dir/Contents/MacOS/SingingWorksheet"
mkdir -p "$app_dir/Contents/MacOS" "$app_dir/Contents/Resources"
cp "$product_dir/SingingWorksheet" "$executable"
/usr/bin/lipo -verify_arch arm64 "$executable"
/usr/bin/lipo -verify_arch x86_64 "$executable"
/usr/bin/ditto "$product_dir/SingingWorkspace_SongCore.bundle" "$app_dir/Contents/Resources/SingingWorkspace_SongCore.bundle"
cp "$project_dir/Resources/Worksheet-Info.plist" "$app_dir/Contents/Info.plist"
source_revision="$(git -C "$project_dir" rev-parse --short=12 HEAD)"
if [[ -n "$(git -C "$project_dir" status --porcelain -- Package.swift Sources/SingingWorksheet Sources/SongCore Sources/SongPrint Sources/SongServices Resources/Worksheet-Info.plist scripts/build-worksheet-app.sh)" ]]; then
    source_revision="$source_revision (変更あり)"
fi
/usr/libexec/PlistBuddy -c "Add :SingingWorkspaceSourceRevision string $source_revision" "$app_dir/Contents/Info.plist"
signing=( --sign "${WORKSHEET_SIGN_IDENTITY:--}" )
if [[ "${WORKSHEET_SIGN_IDENTITY:--}" != "-" ]]; then
    signing+=( --timestamp --options runtime )
fi
/usr/bin/codesign --force "${signing[@]}" "$app_dir"
/usr/bin/codesign --verify --strict --deep "$app_dir"
destination="$output_dir/Singing Worksheet.app"
if [[ -e "$destination" ]]; then
    identifier="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$destination/Contents/Info.plist")"
    if [[ "$identifier" != "jp.singingworkspace.worksheet" ]]; then
        printf 'Unexpected app at %s\n' "$destination" >&2
        exit 1
    fi
    mv "$destination" "$staging/previous.app"
fi
if ! mv "$app_dir" "$destination"; then
    if [[ -d "$staging/previous.app" ]]; then mv "$staging/previous.app" "$destination"; fi
    exit 1
fi
if [[ -n "${1:-}" ]]; then
    mkdir -p "$(dirname "$1")"
    /usr/bin/ditto -c -k --keepParent --norsrc "$destination" "$1"
fi
printf '%s\n' "$destination"
