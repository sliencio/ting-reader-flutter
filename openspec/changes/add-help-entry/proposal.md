# Proposal

## Why

当前关于页提供项目仓库、更新日志、问题反馈和开源许可，但没有直接标明用途的帮助入口。用户需要自行判断去哪里查阅使用说明，本次计划让用户从关于页直接打开现有客户端说明。

## What Changes

- 在关于页的链接卡片增加“使用帮助 / Help”入口，说明其用途为查看客户端使用说明。
- 默认打开本仓库 README：`https://github.com/sliencio/ting-reader-flutter/blob/main/README.md`。这是本方案采用的默认目的地，实施前若另有帮助文档，可在此变更中统一修订。
- 复用现有链接打开、异常提示、页面滚动和中英文文案模式。
- 覆盖入口展示、点击目的地、打开失败、小窗口和大字体等验收场景。

## Capabilities

### New Capabilities

- `about-help`: 用户从关于页找到并打开客户端使用帮助，打开失败时获得反馈。

### Modified Capabilities

无。当前 `openspec/specs/` 没有已建立的相关能力规格；本次不补写整个关于页的历史行为。

## Impact

- 预计涉及 `lib/src/features/mine/about_update_dialog.dart` 的链接展示、`lib/src/core/utils/external_links.dart` 的帮助地址，以及对应的关于页与链接测试。
- 影响 Android、iOS、Windows、macOS 和 Linux 共用的关于页；平台原生浏览器打开行为需要按条件实际验收。
- 不新增依赖，不调整服务端接口，不改变版本检查、下载、问题反馈和其他既有链接的目标。
- 本次只生成提案、规格、设计和任务；业务实现、测试执行、打包及发布均未开始。
