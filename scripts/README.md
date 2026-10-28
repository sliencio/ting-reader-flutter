# 本地打包

在工程根目录执行命令。脚本使用 PATH 中的 Flutter，当前工程使用 Flutter 3.47.0；Dart 随 Flutter 提供。也可以通过环境变量 `FLUTTER_BIN` 指定 Flutter 可执行文件的完整路径。

脚本会先执行 `flutter pub get --enforce-lockfile`，保留工程锁定的依赖版本，再构建 release。默认复用构建缓存，Bash 脚本加 `--clean`、PowerShell 脚本加 `-Clean` 可在构建前清理缓存。构建失败会停止，不会继续封装旧文件。

成品统一放在工程根目录 `dist/`。传源码到另一台电脑时，无需传 `build/`、`dist/`、`.dart_tool/`、`ios/Pods/`、`ios/.symlinks/`，需要保留 `third_party/`。

## iOS：在 Mac 或 SSH 终端执行

先安装完整 Xcode、Flutter 和 CocoaPods，并完成 Xcode 首次初始化。可用 `flutter doctor -v`、`xcodebuild -version`、`pod --version` 检查环境。

```bash
bash scripts/build_ios.sh
```

输出 `dist/TingReader-ios-unsigned.ipa`。这是未签名的真机包，需要再自行签名后安装到 iPhone。

通过 FTP 从 Windows 上传工程后，首次打包可以清理原平台的构建缓存：

```bash
bash scripts/build_ios.sh --clean
```

如果 Mac 已配置匹配的开发者团队、Bundle Identifier、证书和描述文件，可以导出签名包：

```bash
bash scripts/build_ios.sh --signed
bash scripts/build_ios.sh --signed --export-method development
```

第一条使用 Flutter 默认的 App Store 导出方式，用于后续上传 App Store Connect；第二条用于符合描述文件要求的开发设备。只选择需要的一条。输出均为 `dist/TingReader-ios-signed.ipa`，脚本不会自动上传或发布。通过 SSH 签名时还需要确保签名私钥所在钥匙串可用；脚本不保存账号或密码。

## Android

安装 Android SDK、兼容的 JDK，并通过 `flutter doctor --android-licenses` 接受相关许可。

Mac / Linux：

```bash
bash scripts/build_android.sh
bash scripts/build_android.sh --aab
```

Windows PowerShell：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\build.ps1 android
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\build.ps1 android -Aab
```

分别输出 `dist/TingReader-android.apk`、`dist/TingReader-android.aab`。正式签名使用工程原有的 `android/key.properties` 和 keystore；未配置时，当前 Gradle 配置会回退到调试签名。需要分发或上架时应先配置自己的正式签名。

## Windows

安装 Flutter 和 Visual Studio 的“使用 C++ 的桌面开发”工作负载，包含相应 Windows SDK、CMake 和 ATL 组件。生成 EXE 安装包还需要安装 [Inno Setup 6 或 7](https://jrsoftware.org/isdl.php)，脚本会自动查找常见安装目录；自定义安装位置可通过环境变量 `INNO_SETUP_COMPILER` 指定 `ISCC.exe` 的完整路径。PowerShell 5.1 或更新版本执行：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\build.ps1 windows
```

默认同时输出两个文件：

- `dist/TingReader-windows-x64-setup.exe`：双击安装，提供开始菜单快捷方式和卸载入口。
- `dist/TingReader-windows-x64.zip`：便携版，解压整个压缩包后启动 `ting_reader_flutter.exe`，不要只拷贝 EXE。

如果已经运行过 `flutter build windows --release`，已有 `build/windows/x64/runner/Release` 目录，可以直接封装，无需重新编译：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\build.ps1 windows -PackageOnly
```

只需要便携版、不使用 Inno Setup 时执行：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\build.ps1 windows -PortableOnly
```

`-PackageOnly` 可以与 `-PortableOnly` 一起使用，但不能与 `-Clean` 一起使用。脚本会尝试附带本机 Visual Studio 的 VC++ 运行库；找不到时，目标电脑需要安装 Visual C++ x64 运行库。

## macOS

安装完整 Xcode、Flutter 和 CocoaPods，在 Mac 执行：

```bash
bash scripts/build_macos.sh
```

输出 `dist/TingReader-macos.zip`，包含完整 `.app`。签名沿用本机 Xcode 工程设置，脚本不执行公证或发布。

## Linux

在 Linux 安装 Flutter、Clang、CMake、Ninja、pkg-config，以及 GTK、libsecret、WebKitGTK 等项目依赖后执行：

```bash
bash scripts/build_linux.sh
```

输出 `dist/TingReader-linux-x64.tar.gz` 或 `dist/TingReader-linux-arm64.tar.gz`，取决于构建机器架构。解压后保留整个运行目录。
