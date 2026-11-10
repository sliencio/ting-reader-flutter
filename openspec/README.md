# 本项目的 OpenSpec 用法

本仓库使用 `spec-driven` 流程，配置见 [config.yaml](config.yaml)。需求文档使用中文，OpenSpec 要求的结构标题和关键词保留英文。

## 在 Codex 中使用

请在 Codex 中打开本仓库根目录 `D:\Projects\GitHub\ting-reader-flutter`。安装后重新打开项目或新建对话，让项目技能被加载；桌面版可从技能列表选择以下技能，也可以在消息中直接写出技能名称和需求。

1. `openspec-explore`：调查问题、核对代码和分析方案。
2. `openspec-propose`：描述需求，生成提案、规格、设计和任务清单。
3. `openspec-update-change`：根据补充需求更新已有方案。
4. `openspec-apply-change`：按已有任务清单实施改动并验证。
5. `openspec-sync-specs`：将变更中的规格合并到长期规格。
6. `openspec-archive-change`：完成后归档变更。

例如，先发送：

```text
使用 openspec-propose，为“书架先显示本地缓存，再后台刷新”整理方案和验收标准。
```

看过方案后发送：

```text
使用 openspec-apply-change，实施刚才的变更并运行相关检查。
```

Codex CLI 支持 `$openspec-propose` 和 `$openspec-apply-change` 形式。桌面版以技能列表和自然语言调用为准，不需要输入 `/opsx:...`。

## 在终端中查看

打开新终端后，在仓库根目录执行：

```powershell
openspec --version
openspec list
openspec list --specs
openspec doctor
```

有了具体变更后，可执行 `openspec validate <变更名> --strict` 检查文档结构。

`specs/` 保存长期规格，`changes/` 保存进行中的变更，`changes/archive/` 保存归档。项目技能位于 `.agents/skills/`。这些文件应随项目一起纳入版本管理。

本次只初始化工作流，没有创建产品变更，也没有打包或发布客户端。
