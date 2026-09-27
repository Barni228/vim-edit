#!/usr/bin/env bash
# Builds target/release/VimEdit.app and registers it with LaunchServices so
# it appears in Finder's "Open With" menu for .txt files.
#
#   scripts/bundle-macos.sh           # bundle linking against the local Qt
#   scripts/bundle-macos.sh --deploy  # also copy Qt into the bundle (macdeployqt)
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
app="$root/target/release/VimEdit.app"
version="$(sed -n 's/^version = "\(.*\)"/\1/p' "$root/Cargo.toml" | head -1)"

cargo build --release --manifest-path "$root/Cargo.toml"

rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$root/target/release/vim-edit" "$app/Contents/MacOS/VimEdit"
sed "s/@VERSION@/$version/g" "$root/packaging/macos/Info.plist" > "$app/Contents/Info.plist"

if [[ "${1:-}" == "--deploy" ]]; then
    macdeployqt "$app" -qmldir="$root/qml"
    # macdeployqt rewrites library paths, which breaks the linker's ad-hoc
    # signature; Apple Silicon refuses to run unsigned code, so re-sign.
    codesign --force --deep --sign - "$app"
fi

/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$app"

echo "Built $app"
