#!/bin/zsh
set -euo pipefail
cd "${0:A:h}/.."
export CLANG_MODULE_CACHE_PATH="$PWD/.build/module-cache"
mkdir -p "$CLANG_MODULE_CACHE_PATH"
swift run --disable-sandbox --cache-path "$PWD/.build/cache" --config-path "$PWD/.build/config" --security-path "$PWD/.build/security" -Xswiftc -module-cache-path -Xswiftc "$CLANG_MODULE_CACHE_PATH" ShitieChecks
xcrun swiftc -parse-as-library -module-name ShitieInlineChecks -module-cache-path "$CLANG_MODULE_CACHE_PATH" Sources/ShitieCore/*.swift Sources/Shitie/AppModel.swift Tests/ShitieAppTests/InlineEditingChecks.swift -lsqlite3 -o .build/ShitieInlineChecks
.build/ShitieInlineChecks
