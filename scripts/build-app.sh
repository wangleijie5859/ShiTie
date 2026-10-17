#!/bin/zsh
set -euo pipefail
cd "${0:A:h}/.."
configuration="${1:-release}"
if [[ "$configuration" != "release" && "$configuration" != "debug" ]]; then
    print -u2 'Usage: ./scripts/build-app.sh [release|debug]'
    exit 1
fi
export CLANG_MODULE_CACHE_PATH="$PWD/.build/module-cache"
mkdir -p "$CLANG_MODULE_CACHE_PATH"
swift -module-cache-path "$CLANG_MODULE_CACHE_PATH" scripts/make-icon.swift
package_options=(--disable-sandbox --cache-path "$PWD/.build/cache" --config-path "$PWD/.build/config" --security-path "$PWD/.build/security")
swift build "${package_options[@]}" --product Shitie --configuration "$configuration" -Xswiftc -module-cache-path -Xswiftc "$CLANG_MODULE_CACHE_PATH"
binary_dir="$(swift build "${package_options[@]}" --configuration "$configuration" --show-bin-path)"
app_dir="$PWD/dist/拾贴.app"
mkdir -p "$app_dir/Contents/MacOS" "$app_dir/Contents/Resources"
cp "$binary_dir/Shitie" "$app_dir/Contents/MacOS/Shitie"
cp Resources/Info.plist "$app_dir/Contents/Info.plist"
cp Resources/AppIcon.icns "$app_dir/Contents/Resources/AppIcon.icns"
codesign --force --sign - "$app_dir"
touch "$app_dir"
print "已构建：$app_dir"
print '运行：open "dist/拾贴.app"'
