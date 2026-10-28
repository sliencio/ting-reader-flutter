#!/usr/bin/env bash
set -euo pipefail
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/build_common.sh"
prepare_build ios "$@"

if [[ "$SIGNED_IPA" == 1 ]]; then
  start_package
  touch "$PACKAGE_STAGE/export-start"
  export_args=()
  if [[ -n "$EXPORT_METHOD" ]]; then
    export_args+=(--export-method "$EXPORT_METHOD")
  fi
  "$FLUTTER_BIN" build ipa --release --no-pub "${export_args[@]}"
  shopt -s nullglob
  packages=()
  for candidate in "$PROJECT_ROOT"/build/ios/ipa/*.ipa; do
    if [[ "$candidate" -nt "$PACKAGE_STAGE/export-start" ]]; then
      packages+=("$candidate")
    fi
  done
  [[ ${#packages[@]} == 1 ]] || fail '没有找到本次新导出的唯一签名 IPA，请检查签名配置和 build/ios/ipa'
  cp "${packages[0]}" "$PACKAGE_STAGE/TingReader-ios-signed.ipa"
  output="$PROJECT_ROOT/dist/TingReader-ios-signed.ipa"
  mv -f "$PACKAGE_STAGE/TingReader-ios-signed.ipa" "$output"
else
  "$FLUTTER_BIN" build ios --release --no-pub --no-codesign
  [[ -d "$PROJECT_ROOT/build/ios/iphoneos/Runner.app" ]] || fail '未生成 Runner.app，无法封装 IPA'
  start_package
  mkdir -p "$PACKAGE_STAGE/Payload"
  ditto "$PROJECT_ROOT/build/ios/iphoneos/Runner.app" "$PACKAGE_STAGE/Payload/Runner.app"
  ditto -c -k --keepParent "$PACKAGE_STAGE/Payload" "$PACKAGE_STAGE/TingReader-ios-unsigned.ipa"
  output="$PROJECT_ROOT/dist/TingReader-ios-unsigned.ipa"
  mv -f "$PACKAGE_STAGE/TingReader-ios-unsigned.ipa" "$output"
  printf '%s\n' '此 IPA 未签名，需要自行签名后安装到 iPhone。'
fi
finish_package "$output"
