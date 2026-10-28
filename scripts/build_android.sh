#!/usr/bin/env bash
set -euo pipefail
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/build_common.sh"
prepare_build android "$@"

if [[ "$ANDROID_AAB" == 1 ]]; then
  "$FLUTTER_BIN" build appbundle --release --no-pub
  source_file="$PROJECT_ROOT/build/app/outputs/bundle/release/app-release.aab"
  name=TingReader-android.aab
else
  "$FLUTTER_BIN" build apk --release --no-pub
  source_file="$PROJECT_ROOT/build/app/outputs/flutter-apk/app-release.apk"
  name=TingReader-android.apk
fi
[[ -f "$source_file" ]] || fail "没有找到构建产物：$source_file"
start_package
cp "$source_file" "$PACKAGE_STAGE/$name"
output="$PROJECT_ROOT/dist/$name"
mv -f "$PACKAGE_STAGE/$name" "$output"
finish_package "$output"
