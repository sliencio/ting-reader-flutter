#!/usr/bin/env bash
set -euo pipefail
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/build_common.sh"
prepare_build linux "$@"

"$FLUTTER_BIN" build linux --release --no-pub
case "$(uname -m)" in
  x86_64) architecture=x64 ;;
  aarch64|arm64) architecture=arm64 ;;
  *) fail '暂不支持此 Linux CPU 架构' ;;
esac
bundle="$PROJECT_ROOT/build/linux/$architecture/release/bundle"
[[ -d "$bundle" ]] || fail "没有找到运行目录：$bundle"
start_package
mkdir -p "$PACKAGE_STAGE/TingReader-linux-$architecture"
cp -a "$bundle/." "$PACKAGE_STAGE/TingReader-linux-$architecture/"
cp "$PROJECT_ROOT/LICENSE" "$PACKAGE_STAGE/TingReader-linux-$architecture/LICENSE"
name="TingReader-linux-$architecture.tar.gz"
tar -czf "$PACKAGE_STAGE/$name" -C "$PACKAGE_STAGE" "TingReader-linux-$architecture"
output="$PROJECT_ROOT/dist/$name"
mv -f "$PACKAGE_STAGE/$name" "$output"
finish_package "$output"
