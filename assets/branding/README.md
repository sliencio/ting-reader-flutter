# 客户端图标

新图标沿用原客户端的耳机、字母 T 和展开书页造型，通过青绿、薄荷绿与暖白的配色区分本分支。感谢 [dqsq2e2/ting-reader-flutter](https://github.com/dqsq2e2/ting-reader-flutter) 提供原始图标与客户端。

- 母版：`icon-teal-master.png`，最初由内置 imagegen 基于原 `assets/images/logo.png` 改色生成，随后按用户授权通过本地像素修补补齐底部两角；其余图形、书页上沿和中间折口保持原样。
- 主色参考：深青绿 `#146C78`、薄荷绿 `#A6DCCB`、暖白 `#FFF8EF`。
- 导出：在 Windows 工程根目录运行 `powershell -ExecutionPolicy Bypass -File scripts/export_app_icons.ps1`。脚本只转换尺寸、圆角与文件格式，不重新设计图案。
- 应用内、Android、macOS、Windows 和普通网页图标保留圆角；iOS 和网页 maskable 图标使用不透明正方形，由系统进行遮罩。
- 导出时使用镜像边界采样，避免四边混入透明像素形成暗线；脚本会先用纯色基准检查 11 种尺寸的四边和圆角透明度，再导出正式图标。
- 母版必须是真正满版的正方形，底部书页需铺满左右两角，不能预先裁成圆角书页后露出青绿色缺口。脚本会检查母版底部整行，发现此类缺口时停止导出。
- 各平台导出的资源已随源码保存，构建时不需要运行导出脚本或调用图片服务。
- 本次不递增版本、不创建 tag、不触发发布，留到下次重大更新一并发布。

生成提示词见 `icon-prompt.txt`。仓库内历史提交仍保留原版图标。
