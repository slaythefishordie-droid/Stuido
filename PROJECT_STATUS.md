# Knowledge Studio 第一版交接

新模型开始新任务前，先读 [AGENTS.md](AGENTS.md) 和本文件。第一版交付范围是阶段 0 的 iPad 学习原型、导入协议工具及构建流程。产品全貌见[原始计划](docs/product-spec.md)。

## 已完成

| 工作流 | 当前可用行为 |
| --- | --- |
| YouTube 学习 | 粘贴 HTTPS 链接，在 App 内播放。原生 Mark 按钮保存播放器返回的秒数，支持回看和可选提前 3 秒。切换视频或重连时重新绑定播放器，放大和收起复用同一实例。 |
| 本地保存 | 恢复最近选中的视频及其标记。原型文件保留稳定 ID、来源关联和原始秒数。取时失败或会话过期时放弃写入，0 秒是有效位置。 |
| 四类卡片导入协议 | 交付 Schema、中文提示词、合法及错误样例。命令行工具可校验内容、字段来源与引用，预览批次和内容重复。 |
| 构建与安装路线 | macOS 26 ARM64、Xcode 26.2、XcodeGen 2.44.1。Actions 锁定 Swift 包，执行核心及 iPad 模拟器测试，对设备归档并校验未签名 IPA。Windows 与 iPad 使用 AltStore Classic 重签。 |

## 验证记录与已知限制

- 本轮在 Linux Swift 6.2.1 复跑核心测试，8 项通过。协议测试 26 项通过，联合样例得到 4 张候选卡、0 条警告。测试命令见 AGENTS.md。
- 本次原生与协议 CI 的运行链接和结果随通过测试的版本写入附注标签，可用 `git show --no-patch v0.1.0` 查阅。GitHub Actions 的构建日志、模拟器 xcresult、打包报告及 IPA 的 Artifact 保留期为 7 天。
- 当前没有 AltStore 重签安装或 iPad 实际学习视频的验收记录。实际播放、重签后的应用身份、切换后 Mark 归属、回跳、旋转和分屏均待验证。[真机清单](docs/device-validation.md) · [安装说明](docs/build-and-install.md)
- 存储仍是 Application Support 下的 `KnowledgeStudio/prototype-v1.json`。正式数据库、迁移、回收站、备份与恢复尚未交付。协议工具独立运行；原生 AI Inbox、Source 匹配、确认导入事务和四类卡片编辑界面尚未交付。

## 后续开发必须保留的决策

- 采用原生 SwiftUI，最低 iPadOS 17，本地优先。播放器使用官方 YouTube IFrame API，经锁定的 YouTubePlayerKit 2.0.5 接入；测试可替换核心层的时钟接口。[依赖评估](docs/dependencies.md)
- 只有 word、expression、keyword、key_sentence 四类卡片。发现来源、字段作者身份、整理状态、复习状态分别保存。标记、收藏和加入复习各由独立操作触发。[数据模型](docs/data-model.md)
- ChatGPT 在 App 外使用。导入需要用户预览、确认、引用重映射和原子写入。项目归属、个人笔记和复习状态由用户控制。[导入协议](docs/protocol.md)

## 下一阶段

1. 用此版 IPA 完成 AltStore 与 iPad 验收，记录设备、构建、视频和复现步骤。
2. 阶段 1 优先验证 GRDB/SQLite 的迁移和事务。用现有快照验证 Source 与 Mark 的稳定 ID、关联和小数秒数，覆盖首次迁移、重复打开和失败回滚；保留旧文件。
3. 基于同一存储实现基础 Data Manager、回收站和备份还原。阶段 1 以重启后可读取、删除后可恢复、备份还原后引用完整为验收条件。
4. 按计划继续四类卡片与双 Inbox、PDF 学习、EPUB 和本地视频、知识图谱、复习与 Today。这些属于后续开发，FSRS、Readium、ZIPFoundation 等仍是待接入和验证的候选。
