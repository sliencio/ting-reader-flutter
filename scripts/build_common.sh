#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
FLUTTER_BIN="${FLUTTER_BIN:-flutter}"
PACKAGE_STAGE=""

fail() {
  printf '错误：%s\n' "$*" >&2
  exit 1
}

cleanup_package() {
  if [[ -n "$PACKAGE_STAGE" && "$PACKAGE_STAGE" == "$PROJECT_ROOT"/build/package-"$BUILD_TARGET".* ]]; then
    rm -rf -- "$PACKAGE_STAGE"
  fi
}

prepare_build() {
  BUILD_TARGET="$1"
  shift
  CLEAN_BUILD=0
  SIGNED_IPA=0
  ANDROID_AAB=0
  EXPORT_METHOD=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --clean) CLEAN_BUILD=1 ;;
      --signed)
        [[ "$BUILD_TARGET" == ios ]] || fail '--signed 只适用于 iOS'
        SIGNED_IPA=1
        ;;
      --export-method)
        [[ "$BUILD_TARGET" == ios && $# -ge 2 ]] || fail '--export-method 后需要提供 iOS 导出方式'
        EXPORT_METHOD="$2"
        case "$EXPORT_METHOD" in
          app-store|ad-hoc|development|enterprise) ;;
          *) fail '导出方式应为 app-store、ad-hoc、development 或 enterprise' ;;
        esac
        shift
        ;;
      --aab)
        [[ "$BUILD_TARGET" == android ]] || fail '--aab 只适用于 Android'
        ANDROID_AAB=1
        ;;
      --help|-h)
        printf '%s\n' "用法：bash scripts/build_${BUILD_TARGET}.sh [--clean]" \
          'iOS 可选：--signed [--export-method development|ad-hoc|app-store|enterprise]' \
          'Android 可选：--aab；默认构建 APK。' \
          '成品统一放在工程根目录 dist；Flutter 版本使用 3.47.0。'
        exit 0
        ;;
      *) fail "未知参数：$1；使用 --help 查看用法" ;;
    esac
    shift
  done
  [[ -z "$EXPORT_METHOD" || "$SIGNED_IPA" == 1 ]] || fail '--export-method 必须与 --signed 一起使用'
  case "$BUILD_TARGET:$(uname -s)" in
    ios:Darwin|macos:Darwin|linux:Linux|android:Darwin|android:Linux) ;;
    *) fail 'iOS/macOS 需要在 Mac 执行，Linux 需要在 Linux 执行；Windows 请使用 build.ps1' ;;
  esac
  command -v "$FLUTTER_BIN" >/dev/null 2>&1 || fail '找不到 Flutter，请先安装并加入 PATH'
  if [[ "$BUILD_TARGET" == ios || "$BUILD_TARGET" == macos ]]; then
    xcodebuild -version
    command -v pod >/dev/null 2>&1 || fail '找不到 CocoaPods，请先安装'
    if [[ "$BUILD_TARGET" == ios ]]; then
      xcrun --sdk iphoneos --show-sdk-path >/dev/null
    fi
  fi
  cd "$PROJECT_ROOT"
  "$FLUTTER_BIN" --version
  if [[ "$CLEAN_BUILD" == 1 ]]; then
    "$FLUTTER_BIN" clean
  fi
  "$FLUTTER_BIN" pub get --enforce-lockfile
}

start_package() {
  mkdir -p "$PROJECT_ROOT/build" "$PROJECT_ROOT/dist"
  PACKAGE_STAGE="$(mktemp -d "$PROJECT_ROOT/build/package-${BUILD_TARGET}.XXXXXX")"
  trap cleanup_package EXIT
}

finish_package() {
  cp "$PROJECT_ROOT/LICENSE" "$PROJECT_ROOT/dist/LICENSE"
  printf '\n打包完成：%s\n' "$1"
}
