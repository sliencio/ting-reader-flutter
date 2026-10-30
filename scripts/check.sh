#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

if ! command -v flutter >/dev/null 2>&1; then
  echo '未找到 Flutter SDK，请先安装 Flutter 3.47.0 并将其 bin 目录加入 PATH。' >&2
  exit 127
fi

flutter pub get --enforce-lockfile
dart format --output=none --set-exit-if-changed lib test
flutter analyze --no-fatal-infos
flutter test --no-pub
