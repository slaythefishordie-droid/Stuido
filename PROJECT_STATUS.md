# Knowledge Studio 第一版交接

新模型须先读 [AGENTS.md](AGENTS.md)、本文件、[现行产品需求](docs/product-spec.md)和[四个里程碑](docs/web-capture-roadmap.md)。第一版标签保存的是旧原型。主分支现行的网页采集架构为随 App 分发的 Safari Web Extension，扩展分发与双向共享验证代码已在 `feature/safari-extension` 通过构建，等待免费签名后的 iPad 验证。My Inbox 交接尚待实现。

## v0.1.0 已有实现

| 工作流 | 当前可用行为 |
| --- | --- |
| 旧 YouTube 原型 | 粘贴 HTTPS 链接，在 App 内播放。原生 Mark 按钮保存播放器返回的秒数，支持回看和可选提前 3 秒。切换视频或重连时重新绑定播放器，放大和收起复用同一实例。 |
| 本地保存 | 恢复最近选中的视频及其标记。原型文件保留稳定 ID、来源关联和原始秒数。取时失败或会话过期时放弃写入，0 秒是有效位置。 |
| 四类卡片导入协议 | 交付 Schema、中文提示词、合法及错误样例。命令行工具可校验内容、字段来源与引用，预览批次和内容重复。 |
| 构建与安装路线 | macOS 26 ARM64、Xcode 26.2、XcodeGen 2.44.1。Actions 锁定 Swift 包，执行核心及 iPad 模拟器测试，对设备归档并校验未签名 IPA。Windows 与 iPad 使用 AltStore Classic 重签。 |

## 验证记录与已知限制

- 本轮在 Linux Swift 6.2.1 复跑核心测试，8 项通过。协议测试 26 项通过，联合样例得到 4 张候选卡、0 条警告。测试命令见 AGENTS.md。
- 标签 `v0.1.0` 指向 `7df6ef1`。该提交的两项 CI 均已通过，原生流程覆盖模拟器、设备归档和未签名 IPA 校验。Actions Artifact 保留 7 天，标签附注及进度文档长期保留结果摘要。[原生 CI](https://github.com/slaythefishordie-droid/Stuido/actions/runs/44227526926) · [协议 CI](https://github.com/slaythefishordie-droid/Stuido/actions/runs/44227553771)
- 旧构建没有 Safari 扩展。免费账户重签能否保留扩展和共享权限仍是工程条件。新方案的构建、安装、Safari 识别及 App Groups 读写分别记录。[验收清单](docs/device-validation.md)
- 存储仍是 Application Support 下的 `KnowledgeStudio/prototype-v1.json`。正式数据库、迁移、回收站、备份与恢复尚未交付。协议工具独立运行；原生 AI Inbox、Source 匹配、确认导入事务和四类卡片编辑界面尚未交付。

## 后续开发必须保留的决策

- 采用原生 SwiftUI，最低 iPadOS 17，本地优先。网页数据由 Safari 原页面采集，以本地 Native Messaging 和 App Groups 交接，按唯一 ID 去重。[依赖评估](docs/dependencies.md)
- 只有 word、expression、keyword、key_sentence 四类卡片。发现来源、字段作者身份、整理状态、复习状态分别保存。标记、收藏和加入复习各由独立操作触发。[数据模型](docs/data-model.md)
- ChatGPT 在 App 外使用。导入需要用户预览、确认、引用重映射和原子写入。项目归属、个人笔记和复习状态由用户控制。[导入协议](docs/protocol.md)

## 下一阶段

依次验证含扩展的构建、免费签名安装、Safari 识别和共享读写；打通 Safari Mark 到 My Inbox；迁移完整 QuickMark；完善文章及播客可复用的适配器接口。[实施顺序与验收](docs/web-capture-roadmap.md)

其余产品工作仍包括正式数据库和旧记录迁移、回收站与备份、四类卡片及双 Inbox、PDF/EPUB/本地视频学习、知识组织和用户自选复习。各项验收条件见[产品需求](docs/product-spec.md)。

里程碑 1 构建及测试证据见[运行记录](docs/verification/safari-m1-run-44245690553.json)，安装与实测见[操作步骤](docs/build-and-install.md)。
