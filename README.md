# 听悦客户端 · Ting Reader Flutter

听悦的跨平台有声书客户端，使用 Flutter 开发，支持 Android、iOS、Windows、macOS 和 Linux。连接自己的听悦服务端，即可浏览书库、管理书架与书单、收听有声书，以及下载章节离线播放。

本项目基于 [dqsq2e2/ting-reader-flutter](https://github.com/dqsq2e2/ting-reader-flutter) 开源项目进行改进，持续完善客户端的使用体验。

## 下载

前往本仓库的 [Releases 页面](https://github.com/sliencio/ting-reader-flutter/releases) 下载客户端，也可以查看[之前发布的 Beta 测试版](https://github.com/sliencio/ting-reader-flutter/releases/tag/beta)。

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
dart format --output=none --set-exit-if-changed lib test
flutter analyze --no-fatal-infos
flutter test --no-pub
flutter run
```

提交或发布前，可运行 `bash scripts/check.sh` 完成本地依赖、格式、静态分析与全量测试，检查项与 GitHub Actions 一致。任一步失败都会立即退出。

各平台的环境要求、打包命令和输出位置见 [本地打包说明](scripts/README.md)。跨平台传输源码时，请保留 `third_party/` 目录。

GitHub Actions 的配置位于 [`.github/workflows/`](.github/workflows/)：手动运行 `Build Releases` 只构建各平台客户端，成品可在该次运行的 Artifacts 中下载；推送新的 `v版本号` 标签会构建并创建独立的 Release。

每次发布都必须递增 `pubspec.yaml` 的版本号和构建号，并将 `CHANGELOG.md` 中的“未发布”内容整理为对应版本条目。例如 `1.4.5+46` 对应标签 `v1.4.5`，更新日志标题使用 `## 1.4.5 - 发布日期`。提交并推送代码后，再推送这个新标签。工作流会校验版本与标签是否一致，并拒绝不高于历史版本的发布。

历史标签、Release 和附件予以保留。工作流不再移动固定的 `beta` 标签，也不会覆盖已有的 Release；重新发布需要新的版本号和新标签。

日常更新默认只递增补丁版本和构建号，例如 `1.5.0+50` 的下次发布使用 `1.5.1+51`；重大版本调整另行确认。每次 Release 说明仅整理上个版本之后的新改动。

## 来源与致谢

- 原客户端仓库：[dqsq2e2/ting-reader-flutter](https://github.com/dqsq2e2/ting-reader-flutter)
- 听悦服务端仓库：[dqsq2e2/ting-reader](https://github.com/dqsq2e2/ting-reader)

感谢原作者开源听悦项目，也感谢所有贡献者的开发与维护。这个客户端建立在原项目及相关开源组件的工作之上。

## 开源协议

本项目沿用原项目的 [GNU Affero General Public License v3.0](LICENSE) 协议（SPDX：`AGPL-3.0-only`），保留原项目的版权与许可声明。
