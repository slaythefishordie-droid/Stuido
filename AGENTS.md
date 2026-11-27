# Knowledge Studio 开发约定

当前性能分支交接必须先读 [PERFORMANCE_HANDOFF.md](PERFORMANCE_HANDOFF.md)，尤其是用户暂停验证的最新决定；依据新对话指示接续，不将未验证候选标为稳定版。

开始任务先核对分支、未提交改动及用户目标，读本文件和 [开发进度](docs/progress.md) 的当前基线。按任务定位 [产品计划](docs/product-spec.md)、[Safari 路线图](docs/web-capture-roadmap.md) 的相关章节，以及涉及模块和问题 ID；不每轮通读全部历史。详细执行规则见 [工作流](docs/workflow.md)，排障查 [工程问题](docs/engineering-issues.md)。

## 分支与交付

沿用进度日志中的当前维护分支。日常修复、文档更新与例行发布继续在该分支推进，发布以标签定位。重大功能更新或重大开发转向需要并行维护时才新建分支，并在进度中注明基线和用途。IPA 由用户授权后通过现有工作流手动启用 `package_ipa=true`，真机验收单独记录。FSRS 题型沿用现有实现。

## 产品与设计职责

同时承担产品与 UX/UI 设计职责。界面任务遵循 [产品设计章程](docs/product-spec.md) 和 [设计工作方式](docs/workflow.md)：温暖安静的私人书房、内容优先、常用操作可见，点击打开、长按快捷操作、选择模式批量处理。较大界面开工前给 2–4 句设计判断，不写冗长报告。普通体验优化自主推进；重大页面方案先说明，方向/功能删除/对象关系或数据规则重大调整等必须取得用户同意。既有授权不重复询问。研究相关成熟模式，不为研究或完美主义阻塞交付。

## 架构与技术栈

- 网页采集统一在 Safari 网站原页面，由主 App 随附的一个 Web Extension 和多个站点适配器承担。本地 Native Messaging 与 App Groups 完成交接。先验证免费重签、扩展识别和共享读写，再实现 QuickMark 到 My Inbox。
- 第一版基线中，`Sources/KnowledgeCore` 是 Swift 6 的 SwiftPM 包。`YouTubeVideoID` 校验输入，`MarkCapture` 管理会话和异步取时，`MarkStore` 验证快照并原子落盘。
- `ios/KnowledgeStudio` 是 SwiftUI 应用层。以下播放器类只描述 v0.1.0 旧原型。`YouTubeStudyView` 展示界面，`YouTubeStudyModel` 协调播放器和状态，`YouTubeClock` 通过核心层的 `VideoClock` 接口接入 YouTubePlayerKit。编辑 XcodeGen 的 `ios/project.yml` 维护工程配置。
- 当前主 App 使用 My Inbox / 卡片 / Library / AI Inbox / Data Manager / 设置；`ExtensionSetupView` 保留里程碑 1 双向共享诊断。`ios/Shared/SharedProbeStore.swift` 由主 App 和 Safari 扩展共用，各端独立原子写入自己的记录文件；这不是正式 Mark 队列。AltStore 提供的 `ALTAppGroups` 存在时必须有效，不可静默回退至原组。缺失记录表示尚未写入，损坏、来源不符和其他读取错误必须报告。
- `ios/SafariExtension/Resources/popup.js` 处理诊断面板，原生处理器接收 `readProbe` / `writeProbe`，另以 `saveMark` 接收里程碑 2 的不可变记录。正式记录使用 `WebMarkStore`，不能复用诊断文件。请求设定超时并防止重入；超时不代表原生写入已取消，应先读取核实结果。扩展资源必须复制到包根目录以便 Safari 找到 manifest。
- `schemas/` 维护 Draft 2020-12 导入协议。`tools/protocol/` 使用 Node.js 22+、Ajv、ajv-formats 和 jsonc-parser。文件和粘贴文本共用校验入口。`examples/import/` 提供可运行的协议样例。
- 原型快照格式、导入协议、未来的数据库迁移与备份格式分别演进。变更持久化或协议时，应验证现有数据能重新打开，以及失败后的数据完整性。

## 开发约定

- 使用中文沟通，代码标识符和 JSON 字段使用英文。
- 原生 SwiftUI，最低 iPadOS 17；先保持 macOS GitHub Actions 可编译再扩展功能。勿将项目替换为 Web App。
- 一级卡片只有 word / expression / keyword / key_sentence。发现来源、整理状态、复习状态分开；Mark 不自动建卡，收藏不自动复习。
- 不加入内置 AI 聊天、云同步、字典 API、完整浏览器或 YouTube 媒体直链提取。
- 不清空用户数据来修复数据库/迁移；保留稳定 ID、原始定位、字段 provenance。导入需要显式确认、引用重映射和事务。
- 依赖通过薄适配层隔离，锁定版本；修改依赖时更新 docs/dependencies.md、锁文件与许可证声明。
- 不提交 Apple 账户密码、证书、签名密钥、临时签名下载 URL。AltStore 在用户端重签，CI 产出经过设备架构检查、需要用户重新签名的 IPA 候选。扩展开发包以 ad-hoc 签名保存权限声明。

## 相关检查

- Swift 核心：`bash scripts/test-core.sh`（需要 Swift 6.1+）。
- 协议及 Safari 面板：`npm ci --ignore-scripts`，`npm test`，`npm run validate -- examples/import/valid-four-types.json`。面板测试位于 `tools/safari/`，以模拟 Native Messaging 验证错误恢复；协议指纹优化必须保持已有指纹兼容。
- 原生：`.github/workflows/ipados.yml`，默认标准 macos-15-intel / Xcode 26.2，规避近期 ARM64 调度容量不足；手动运行仍可选 macos-26 (ARM64)，两者固定相同工具链和测试要求。本地 macOS 可用 `bash scripts/bootstrap-xcodegen.sh` 生成工程。
- 只运行与本次更改相称的检查。文档修改无需重复 macOS 构建。
- 分开记录核心测试、原生编译、模拟器测试、IPA 结构、AltStore 免费签名安装、Safari 识别扩展、App Groups 实际共享及真机交互。Mock 测试不是 YouTube 播放成功；Linux 不能验证 SwiftUI 或签名安装。

当前范围与交接事项见 PROJECT_STATUS.md，历次验证和限制见 docs/progress.md。复发问题先按 docs/engineering-issues.md 定位，新的问题记录现象、证据、处理与验证边界。每阶段更新进度、实际结果与阻塞，不把下一阶段计划写成已实现功能。

## 用户更新的功能优先规范（2026-11-19）

本轮按 docs/progress.md 完成两份计划阶段 1–4。优先端到端功能，仅阅读相关代码和运行针对性测试，不重复全量审计、无关重构或重复验证已通过部分。普通非阻塞优化写入待办。数据删除/迁移/备份恢复、对象关联与持久化、共享传输及权限安全必须保留关键验证。同一错误连续两次修复无进展则记录阻塞和尝试，继续独立功能。阶段稳定化时集中完整构建回归；未经验证不得宣称通过或发布稳定版。用户已报告里程碑 1 真机双向共享成功。

v1.0.0 模块：LibraryRepository/LibraryState 负责事务与引用校验，ImportService 使用核心资源副本的 1.0 Schema；修改 schemas/import-package-1.0.schema.json 时同步 Sources/KnowledgeCore/Resources 中同名文件。StudioModel/StudioView、ManagementViews、SourceReaders、BackupService 分别承担应用协调、主界面、管理/导入、阅读和备份。新测试仅按修改风险运行，版本稳定化才做完整原生回归。

## v3.7 性能重构接续

本轮用户授权的独立分支为 `performance/v3.7-low-power`；发行与恢复基线见进度顶部。接续性能工作必须先阅读根目录 `PERFORMANCE_AUDIT.md`、`PERFORMANCE_RESULTS.md` 和 `docs/performance/IPAD_TEST_GUIDE.md`，区分合成基准、原生测试与真机结果。恢复标签不移动；不在 main 或发行分支直接试验。

- SQLite 快照缓存只能在 GRDB 串行连接内访问，以 `data_version` 失效，写入成功提交后才发布；禁止取消引用校验来提速。必须测试外部连接、回滚、损坏及重开。
- SwiftUI 消费 `StudioModel` 的集合属性和 `markIndex`；不要重新引入整个 ObservableObject 的广播依赖。完整 `state` 用于确实需要完整快照的操作。
- 阅读位置可以合并；Mark、笔迹、复习、编辑不能被丢弃。后台保存成功前不宣布成功，失败保持错误和冲突保护。
- 封面等可重建资源使用 `PerformancePolicy`、有界缓存及异步工作；主线程仍负责 UIKit/SwiftUI。不能让资源策略禁用核心功能或强制显示刷新率。
