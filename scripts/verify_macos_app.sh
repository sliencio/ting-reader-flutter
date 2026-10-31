#!/usr/bin/env bash
set -euo pipefail
app="${1:?请指定待检查的应用路径}"
temporary="$(mktemp -d)"
pid=''
cleanup() {
  if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
    kill "$pid" 2>/dev/null || true
    wait "$pid" 2>/dev/null || true
  fi
  rm -f "$temporary/entitlements.plist" "$temporary/launch.log"
  rmdir "$temporary"
}
trap cleanup EXIT
codesign --verify --deep --strict --verbose=2 "$app"
codesign -d --entitlements :- "$app" > "$temporary/entitlements.plist"
python3 - "$temporary/entitlements.plist" <<'PY'
import plistlib
import sys
with open(sys.argv[1], 'rb') as stream:
    entitlements = plistlib.load(stream)
assert 'keychain-access-groups' not in entitlements, '独立发行包不能申请钥匙串共享权限'
assert not entitlements.get('com.apple.security.get-task-allow'), '发行包不能携带调试权限'
PY
executable="$(/usr/libexec/PlistBuddy -c 'Print CFBundleExecutable' "$app/Contents/Info.plist")"
lipo -verify_arch arm64 "$app/Contents/MacOS/$executable"
if [[ "${2:-}" == '--smoke' ]]; then
  "$app/Contents/MacOS/$executable" > "$temporary/launch.log" 2>&1 &
  pid=$!
  sleep 8
  if ! kill -0 "$pid" 2>/dev/null; then
    cat "$temporary/launch.log"
    wait "$pid" || true
    echo 'macOS 应用启动后提前退出' >&2
    exit 1
  fi
fi
echo 'macOS 签名、权限、ARM64 架构与所选启动检查通过'
