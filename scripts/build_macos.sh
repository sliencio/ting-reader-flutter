#!/usr/bin/env bash
set -euo pipefail
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/build_common.sh"
prepare_build macos "$@"

"$FLUTTER_BIN" build macos --release --no-pub
shopt -s nullglob
apps=("$PROJECT_ROOT"/build/macos/Build/Products/Release/*.app)
[[ ${#apps[@]} == 1 ]] || fail '没有找到唯一的 macOS 应用'
start_package
mkdir -p "$PACKAGE_STAGE/TingReader-macos"
ditto "${apps[0]}" "$PACKAGE_STAGE/TingReader-macos/$(basename "${apps[0]}")"
cp "$PROJECT_ROOT/LICENSE" "$PACKAGE_STAGE/TingReader-macos/LICENSE"
ditto -c -k --keepParent "$PACKAGE_STAGE/TingReader-macos" "$PACKAGE_STAGE/TingReader-macos.zip"
output="$PROJECT_ROOT/dist/TingReader-macos.zip"
mv -f "$PACKAGE_STAGE/TingReader-macos.zip" "$output"
finish_package "$output"
