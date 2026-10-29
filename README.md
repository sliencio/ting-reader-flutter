# 听悦客户端 · Ting Reader Flutter

听悦的跨平台有声书客户端，使用 Flutter 开发，支持 Android、iOS、Windows、macOS 和 Linux。连接自己的听悦服务端，即可浏览书库、管理书架与书单、收听有声书，以及下载章节离线播放。

本项目基于 [dqsq2e2/ting-reader-flutter](https://github.com/dqsq2e2/ting-reader-flutter) 开源项目进行改进，持续完善客户端的使用体验。

## 下载

前往本仓库的 [Releases 页面](https://github.com/sliencio/ting-reader-flutter/releases) 下载客户端，也可以直接查看 [Beta 测试版](https://github.com/sliencio/ting-reader-flutter/releases/tag/beta)。

| 平台 | 文件 | 使用方式 |
| --- | --- | --- |
| Android | `ting-reader-flutter-android.apk` | 下载并安装 APK。 |
| Windows | `TingReader-windows-x64-setup.exe` | 运行安装程序。 |
| macOS | `TingReader-macos.zip` | 解压后使用其中的 `.app`。 |
| Linux | `TingReader-linux-x64.tar.gz` | 解压并保留完整目录后运行。 |
| iOS | `TingReader-ios-self-sign.ipa` | 未签名的真机包，需要自行签名后安装。 |

具体更新内容见各版本的 Release 说明和 [更新日志](CHANGELOG.md)。

## 开始使用

1. 准备可访问的 [听悦服务端](https://github.com/dqsq2e2/ting-reader)。
2. 安装对应平台的客户端，填写服务端地址并登录。
3. 浏览书库，选择书籍和章节开始收听。

## 开发与打包

当前工程使用 Flutter 3.47.0，Dart 随 Flutter 提供。在工程根目录执行：

```bash
flutter pub get --enforce-lockfile
flutter analyze --no-fatal-infos
flutter test --no-pub
flutter run
```

各平台的环境要求、打包命令和输出位置见 [本地打包说明](scripts/README.md)。跨平台传输源码时，请保留 `third_party/` 目录。

GitHub Actions 的配置位于 [`.github/workflows/`](.github/workflows/)：手动运行 `Build Releases` 会构建各平台客户端并更新 Beta Release；推送 `v*` 版本标签会构建并发布对应的正式版本。发布说明维护在 `CHANGELOG.md` 中，Beta 读取“未发布”条目，正式版读取对应版本条目。

## 来源与致谢

- 原客户端仓库：[dqsq2e2/ting-reader-flutter](https://github.com/dqsq2e2/ting-reader-flutter)
- 听悦服务端仓库：[dqsq2e2/ting-reader](https://github.com/dqsq2e2/ting-reader)

感谢原作者开源听悦项目，也感谢所有贡献者的开发与维护。这个客户端建立在原项目及相关开源组件的工作之上。

## 开源协议

本项目沿用原项目的 [GNU Affero General Public License v3.0](LICENSE) 协议（SPDX：`AGPL-3.0-only`），保留原项目的版权与许可声明。
